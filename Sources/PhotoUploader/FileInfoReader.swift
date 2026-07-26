import Foundation
import UniformTypeIdentifiers

/// Local filesystem facts about the photo's file — the same things Finder's
/// Get Info panel shows, minus "Open with" and Sharing & Permissions (which
/// aren't meaningful here and aren't anyone's business but the user's own
/// Mac). This is purely for display in the app; none of it is ever
/// published to the site or stored in photos.json — a local file path in
/// particular has no business being public.
enum FileInfoReader {
    static func read(url: URL, width: Int?, height: Int?) -> [MetadataField] {
        var fields: [MetadataField] = []

        fields.append(MetadataField(key: "file_path", group: "File", label: "Path", value: url.path))

        if let w = width, let h = height {
            fields.append(MetadataField(key: "file_dimensions", group: "File", label: "Dimensions", value: "\(w) × \(h)"))
        }

        if let type = UTType(filenameExtension: url.pathExtension), let description = type.localizedDescription {
            fields.append(MetadataField(key: "file_kind", group: "File", label: "Kind", value: description))
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            if let size = attrs[.size] as? Int {
                fields.append(MetadataField(key: "file_size", group: "File", label: "Size", value: byteFormatter.string(fromByteCount: Int64(size))))
            }
            if let created = attrs[.creationDate] as? Date {
                fields.append(MetadataField(key: "file_created", group: "File", label: "Created", value: dateFormatter.string(from: created)))
            }
            if let modified = attrs[.modificationDate] as? Date {
                fields.append(MetadataField(key: "file_modified", group: "File", label: "Modified", value: dateFormatter.string(from: modified)))
            }
        }

        return fields
    }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
