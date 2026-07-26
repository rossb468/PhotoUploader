import Foundation

// Mirrors the schema previously written by tools/photogen.py's
// photography/data/photos.json, so the existing library decodes unchanged.

struct Swatch: Codable, Equatable {
    var hex: String
    var rgb: [Int]
    var text: String
}

struct Ambient: Codable, Equatable {
    var bg1: String
    var bg2: String
    var accent: String
    var text: String
}

struct Palette: Codable, Equatable {
    var dominant: Swatch?
    var vibrant: Swatch?
    var light_vibrant: Swatch?
    var dark_vibrant: Swatch?
    var muted: Swatch?
    var light_muted: Swatch?
    var dark_muted: Swatch?
    var ambient: Ambient?
}

/// One piece of extracted metadata — a camera setting, a date, a GPS value,
/// anything ImageIO can pull out of a photo. `key` is a stable identifier
/// (e.g. "focal_length_35mm") independent of the human-readable `label`, so
/// renaming a label later doesn't orphan a user's publish choice for it.
struct MetadataField: Codable, Equatable, Identifiable, Hashable {
    var key: String
    var group: String
    var label: String
    var value: String
    var id: String { key }
}

/// The 9 fields the site showed before this became an open-ended list —
/// still the default "on" set for freshly-extracted metadata, per the
/// original design (show everything, but only these are pre-checked).
let defaultPublishedKeys: Set<String> = [
    "make", "model", "lens", "aperture", "shutter", "iso", "focal_length", "date_taken", "location",
]

struct PostExif: Codable, Equatable {
    /// Every field extracted from the photo, in display order.
    var fields: [MetadataField]

    /// Which field keys actually render on the public page. A key missing
    /// from this dict means "not published" — the default for anything
    /// beyond the original 9 fields, which get explicit `true` entries at
    /// publish time instead of relying on a fallback default here.
    var published: [String: Bool]?

    init(fields: [MetadataField] = [], published: [String: Bool]? = nil) {
        self.fields = fields
        self.published = published
    }

    func isPublished(_ key: String) -> Bool {
        published?[key] ?? false
    }

    func value(_ key: String) -> String? {
        fields.first { $0.key == key }?.value
    }

    // MARK: - Codable, with migration from the old named-property schema

    private enum CodingKeys: String, CodingKey {
        case fields, published
        // Legacy (pre-dynamic-fields) keys, decode-only.
        case make, model, lens, aperture, shutter, iso, focal_length, date_taken, location
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if let existingFields = try c.decodeIfPresent([MetadataField].self, forKey: .fields) {
            self.fields = existingFields
            self.published = try c.decodeIfPresent([String: Bool].self, forKey: .published)
            return
        }

        // Legacy shape: synthesize fields from the old named string properties.
        var migrated: [MetadataField] = []
        var legacyKeysPresent: [String] = []
        func addLegacy(_ codingKey: CodingKeys, _ group: String, _ label: String, _ metaKey: String) {
            if let value = (try? c.decodeIfPresent(String.self, forKey: codingKey)) ?? nil, !value.isEmpty {
                migrated.append(MetadataField(key: metaKey, group: group, label: label, value: value))
                legacyKeysPresent.append(metaKey)
            }
        }
        addLegacy(.make, "Camera", "Make", "make")
        addLegacy(.model, "Camera", "Model", "model")
        addLegacy(.lens, "Camera", "Lens", "lens")
        addLegacy(.aperture, "Exposure", "Aperture", "aperture")
        addLegacy(.shutter, "Exposure", "Shutter Speed", "shutter")
        addLegacy(.iso, "Exposure", "ISO", "iso")
        addLegacy(.focal_length, "Exposure", "Focal Length", "focal_length")
        addLegacy(.date_taken, "Date", "Date Taken", "date_taken")
        addLegacy(.location, "Location", "Coordinates", "location")
        self.fields = migrated

        if let existingPublished = try c.decodeIfPresent([String: Bool].self, forKey: .published) {
            self.published = existingPublished
        } else {
            // Pre-checkbox-feature post: these fields were always shown, so
            // keep them visible rather than having them vanish on migration.
            var defaults: [String: Bool] = [:]
            for key in legacyKeysPresent { defaults[key] = true }
            self.published = defaults
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fields, forKey: .fields)
        try c.encodeIfPresent(published, forKey: .published)
    }
}

struct Post: Codable, Equatable {
    var slug: String
    var date: String
    var created: Int
    var title: String
    var caption: String
    var width: Int
    var height: Int
    var full: String
    var thumb: String
    /// Downsized download tiers and a verbatim copy of the original source
    /// file. Optional because posts published before this feature existed
    /// don't have them — `small`/`medium` get backfilled from `full` on the
    /// next save, but `original` can't be recovered once the source file is
    /// gone, so it's simply omitted from the download menu for those posts.
    var small: String?
    var medium: String?
    var original: String?
    var exif: PostExif
    var palette: Palette
}

struct PhotosData: Codable {
    var posts: [Post]
}

/// What a save/publish actually changes: title/caption/date are freely
/// editable text; the EXIF fields themselves are never user-edited (only
/// extracted automatically), so all a user can do is choose which of the
/// already-extracted fields get published, via `published`.
struct PhotoMetadataInput {
    var title: String
    var caption: String
    var date: String
    var published: [String: Bool]
}
