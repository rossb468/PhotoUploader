import Foundation

enum ItemKind: Equatable {
    case existing(slug: String)
    case new
}

enum ItemStatus: Equatable {
    case idle
    case working
    case done(message: String)
    case failed(String)
}

/// A snapshot of everything a user can actually change — title/caption/date
/// plus which EXIF fields are set to publish. Comparing two snapshots is how
/// "Save Changes" knows whether anything is actually different, including
/// the case where a user toggles a checkbox and toggles it back.
struct MetadataSnapshot: Equatable {
    var title: String
    var caption: String
    var date: String
    var publishedKeys: Set<String>
}

/// One photo shown in the app — either an already-published post loaded from
/// the site's photos.json, or a not-yet-published photo just added locally.
/// EXIF values themselves are read-only (extracted automatically, never
/// typed by a user); the only thing a user edits is title/caption/date and
/// which of the extracted fields get published.
struct LibraryItem: Identifiable, Equatable {
    let id: UUID
    var kind: ItemKind

    /// Local file to publish from. Only set for .new items.
    var sourceURL: URL?
    /// Absolute file URL to the on-site thumbnail. Only set for .existing items.
    var thumbFileURL: URL?
    /// Absolute file URL to the on-site full-size image. Only set for .existing items.
    var fullFileURL: URL?
    /// Absolute file URL to the preserved original upload, if the post has
    /// one. Only set for .existing items.
    var originalFileURL: URL?

    var title: String = ""
    var caption: String = ""
    var date: Date = Date()

    /// Every EXIF/camera/GPS field this photo actually has, in display order.
    var metadataFields: [MetadataField] = []
    /// Which of those fields' keys are currently checked to publish.
    var publishedKeys: Set<String> = []

    var width: Int?
    var height: Int?

    /// For .new items: whether we've already pulled EXIF from the source file.
    var exifLoaded = false

    var status: ItemStatus = .idle

    /// Captured once, right after an existing post's data loads (or right
    /// after a successful save). `isDirty` compares the current state
    /// against this, so Save Changes only lights up on a real difference.
    var baseline: MetadataSnapshot?

    init(sourceURL: URL) {
        self.id = UUID()
        self.kind = .new
        self.sourceURL = sourceURL
    }

    init(existing post: Post, repoPath: String) {
        self.id = UUID()
        self.kind = .existing(slug: post.slug)
        self.title = post.title
        self.caption = post.caption
        self.width = post.width
        self.height = post.height
        self.date = LibraryItem.parseDate(post.date) ?? Date()
        self.exifLoaded = true

        self.metadataFields = post.exif.fields
        self.publishedKeys = Set(post.exif.fields.map(\.key).filter { post.exif.isPublished($0) })

        let siteRoot = URL(fileURLWithPath: repoPath).appendingPathComponent("photography")
        self.thumbFileURL = siteRoot.appendingPathComponent(post.thumb)
        self.fullFileURL = siteRoot.appendingPathComponent(post.full)
        if let original = post.original {
            self.originalFileURL = siteRoot.appendingPathComponent(original)
        }

        self.baseline = self.currentSnapshot
    }

    /// Applies freshly-extracted EXIF to a new (not-yet-published) item,
    /// defaulting the publish set to just the fields the site originally
    /// showed — everything else the app can now dig up starts unchecked.
    mutating func applyExtractedExif(_ extracted: ExtractedExif) {
        metadataFields = extracted.fields
        publishedKeys = Set(extracted.fields.map(\.key)).intersection(defaultPublishedKeys)
        width = extracted.width
        height = extracted.height
        if let dt = extracted.value("date_taken"), let parsed = LibraryItem.parseDate(dt) {
            date = parsed
        }
    }

    func fieldValue(_ key: String) -> String {
        metadataFields.first { $0.key == key }?.value ?? ""
    }

    /// Builds the metadata bundle PhotoEngine's add/update calls need.
    func metadataInput() -> PhotoMetadataInput {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        var published: [String: Bool] = [:]
        for field in metadataFields {
            published[field.key] = publishedKeys.contains(field.key)
        }
        return PhotoMetadataInput(title: title, caption: caption, date: df.string(from: date), published: published)
    }

    var currentSnapshot: MetadataSnapshot {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return MetadataSnapshot(title: title, caption: caption, date: df.string(from: date), publishedKeys: publishedKeys)
    }

    /// True only for existing posts with unsaved edits. New (unpublished)
    /// items have no baseline, so this is always false for them — they use
    /// a separate "Publish" action instead of "Save Changes".
    var isDirty: Bool {
        guard let baseline else { return false }
        return currentSnapshot != baseline
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        if case .existing(let slug) = kind { return slug }
        return sourceURL?.lastPathComponent ?? "Untitled"
    }

    var previewURL: URL? {
        switch kind {
        case .new: return sourceURL
        case .existing: return fullFileURL
        }
    }

    var thumbnailURL: URL? {
        switch kind {
        case .new: return sourceURL
        case .existing: return thumbFileURL
        }
    }

    /// The best file to show File Info for: the on-disk source before
    /// publishing, or the preserved original / Large JPEG once published.
    var fileInfoURL: URL? {
        switch kind {
        case .new: return sourceURL
        case .existing: return originalFileURL ?? fullFileURL
        }
    }

    var isExisting: Bool {
        if case .existing = kind { return true }
        return false
    }

    static func parseDate(_ string: String) -> Date? {
        let full = DateFormatter()
        full.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = full.date(from: string) { return date }
        let short = DateFormatter()
        short.dateFormat = "yyyy-MM-dd"
        return short.date(from: String(string.prefix(10)))
    }
}
