import Foundation

/// Everything the app needs to manage the photography site, entirely in
/// process — no external tools or interpreters involved.
enum PhotoEngine {
    // MARK: - Data store

    private static func dataURL(repoPath: String) -> URL {
        SiteGenerator.siteRoot(repoPath: repoPath).appendingPathComponent("data/photos.json")
    }

    static func load(repoPath: String) -> PhotosData {
        let url = dataURL(repoPath: repoPath)
        guard let data = try? Data(contentsOf: url),
              var decoded = try? JSONDecoder().decode(PhotosData.self, from: data) else {
            return PhotosData(posts: [])
        }
        if migrateLegacyFullFolder(&decoded, repoPath: repoPath) {
            try? save(decoded, repoPath: repoPath)
            try? SiteGenerator.rebuild(decoded, repoPath: repoPath)
        }
        return decoded
    }

    private static func save(_ data: PhotosData, repoPath: String) throws {
        let url = dataURL(repoPath: repoPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let encoded = try encoder.encode(data)
        try encoded.write(to: url)
    }

    /// One-time cleanup: the "Large" download tier used to live in
    /// images/full/ (back when it was labeled "Original"). Moves any
    /// leftover files into images/large/, repoints posts.json at the new
    /// location, and removes the old folder once it's empty.
    @discardableResult
    private static func migrateLegacyFullFolder(_ data: inout PhotosData, repoPath: String) -> Bool {
        let root = SiteGenerator.siteRoot(repoPath: repoPath)
        let oldDir = root.appendingPathComponent("images/full")
        guard FileManager.default.fileExists(atPath: oldDir.path) else { return false }

        let newDir = root.appendingPathComponent("images/large")
        try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)

        var changed = false
        for i in data.posts.indices where data.posts[i].full.hasPrefix("images/full/") {
            let filename = (data.posts[i].full as NSString).lastPathComponent
            let oldFileURL = root.appendingPathComponent(data.posts[i].full)
            let newFileURL = newDir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: oldFileURL.path) {
                try? FileManager.default.removeItem(at: newFileURL)
                try? FileManager.default.moveItem(at: oldFileURL, to: newFileURL)
            }
            data.posts[i].full = "images/large/\(filename)"
            changed = true
        }

        if let remaining = try? FileManager.default.contentsOfDirectory(atPath: oldDir.path), remaining.isEmpty {
            try? FileManager.default.removeItem(at: oldDir)
        }

        return changed
    }

    // MARK: - Slugs

    static func slugify(_ text: String) -> String {
        var result = ""
        var lastWasDash = false
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash && !result.isEmpty {
                result += "-"
                lastWasDash = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result
    }

    private static func uniqueSlug(base: String, existing: Set<String>) -> String {
        let root = base.isEmpty ? "photo" : base
        var slug = root
        var n = 2
        while existing.contains(slug) {
            slug = "\(root)-\(n)"
            n += 1
        }
        return slug
    }

    // MARK: - Reading

    static func listPhotos(repoPath: String) -> [Post] {
        SiteGenerator.sortedPosts(load(repoPath: repoPath).posts)
    }

    static func fetchExif(sourceURL: URL) -> ExtractedExif {
        ExifReader.read(from: sourceURL)
    }

    // MARK: - Applying which EXIF fields should publish

    /// EXIF values are never user-edited, so there's nothing to write back
    /// except which fields the user chose to publish.
    private static func applyPublishFlags(_ exif: inout PostExif, _ input: PhotoMetadataInput) {
        exif.published = input.published
    }

    /// Re-extracts EXIF from a post's preserved original upload and
    /// overwrites the stored fields, keeping the user's publish-flag choices
    /// intact (matched up by field key). Self-heals stale formatting from
    /// before a rounding/parsing fix shipped (e.g. an un-rounded aperture),
    /// and picks up any newly-supported fields this version of the app can
    /// extract that an older version couldn't — but only for posts that
    /// still have their original file; there's nothing to refresh from for
    /// older posts where the source was never kept.
    private static func refreshExifValuesFromOriginal(_ post: inout Post, repoPath: String) {
        guard let originalPath = post.original else { return }
        let originalURL = SiteGenerator.siteRoot(repoPath: repoPath).appendingPathComponent(originalPath)
        guard FileManager.default.fileExists(atPath: originalURL.path) else { return }

        post.exif.fields = ExifReader.read(from: originalURL).fields
    }

    // MARK: - Publishing a new photo

    @discardableResult
    static func addPhoto(sourceURL: URL, input: PhotoMetadataInput, repoPath: String) throws -> String {
        var data = load(repoPath: repoPath)
        let existingSlugs = Set(data.posts.map(\.slug))

        let titleSlug = slugify(input.title)
        let fileSlug = slugify(sourceURL.deletingPathExtension().lastPathComponent)
        let base = !titleSlug.isEmpty ? titleSlug : (!fileSlug.isEmpty ? fileSlug : "photo")
        let slug = uniqueSlug(base: base, existing: existingSlugs)

        let extractedExif = ExifReader.read(from: sourceURL)
        let root = SiteGenerator.siteRoot(repoPath: repoPath)
        let processed = try ImageProcessor.process(sourceURL: sourceURL, slug: slug, siteRoot: root)
        let palette = ColorPalette.buildPalette(from: processed.fullImage)

        var exif = PostExif(fields: extractedExif.fields)
        applyPublishFlags(&exif, input)

        let post = Post(
            slug: slug,
            date: input.date,
            created: Int(Date().timeIntervalSince1970 * 1000),
            title: input.title,
            caption: input.caption,
            width: processed.width,
            height: processed.height,
            full: processed.fullRelativePath,
            thumb: processed.thumbRelativePath,
            small: processed.smallRelativePath,
            medium: processed.mediumRelativePath,
            original: processed.originalRelativePath,
            exif: exif,
            palette: palette
        )
        data.posts.append(post)
        try save(data, repoPath: repoPath)
        try SiteGenerator.rebuild(data, repoPath: repoPath)
        return slug
    }

    // MARK: - Editing an existing photo

    static func updatePhoto(slug: String, input: PhotoMetadataInput, repoPath: String) throws {
        var data = load(repoPath: repoPath)
        guard let idx = data.posts.firstIndex(where: { $0.slug == slug }) else {
            throw PhotoEngineError.postNotFound(slug)
        }
        data.posts[idx].title = input.title
        data.posts[idx].caption = input.caption
        if !input.date.isEmpty {
            data.posts[idx].date = input.date
        }
        refreshExifValuesFromOriginal(&data.posts[idx], repoPath: repoPath)
        applyPublishFlags(&data.posts[idx].exif, input)

        if data.posts[idx].medium == nil || data.posts[idx].small == nil {
            let root = SiteGenerator.siteRoot(repoPath: repoPath)
            let fullURL = root.appendingPathComponent(data.posts[idx].full)
            let sizes = ImageProcessor.backfillDownloadSizes(fullImageURL: fullURL, slug: slug, siteRoot: root)
            if data.posts[idx].medium == nil { data.posts[idx].medium = sizes.medium }
            if data.posts[idx].small == nil { data.posts[idx].small = sizes.small }
        }

        try save(data, repoPath: repoPath)
        try SiteGenerator.rebuild(data, repoPath: repoPath)
    }

    // MARK: - Removing a photo

    static func removePhoto(slug: String, repoPath: String) throws {
        var data = load(repoPath: repoPath)
        guard let post = data.posts.first(where: { $0.slug == slug }) else {
            throw PhotoEngineError.postNotFound(slug)
        }
        let root = SiteGenerator.siteRoot(repoPath: repoPath)
        for path in [post.full, post.thumb, post.medium, post.small, post.original].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(path))
        }
        data.posts.removeAll { $0.slug == slug }

        try save(data, repoPath: repoPath)
        try SiteGenerator.rebuild(data, repoPath: repoPath)
    }
}
