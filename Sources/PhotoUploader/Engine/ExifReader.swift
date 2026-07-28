import CoreGraphics
import Foundation
import ImageIO

/// What we can pull straight out of a photo's embedded metadata, before any
/// user edits. `fields` is everything ImageIO exposes, worth showing to a
/// user; `width`/`height` are kept separate since they're needed for image
/// processing math, not just display.
struct ExtractedExif {
    var fields: [MetadataField] = []
    var width: Int?
    var height: Int?

    func value(_ key: String) -> String? {
        fields.first { $0.key == key }?.value
    }
}

enum ExifReader {
    static func read(from url: URL) -> ExtractedExif {
        var info = ExtractedExif()
        var fields: [MetadataField] = []

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return info
        }

        func add(_ key: String, _ group: String, _ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            fields.append(MetadataField(key: key, group: group, label: label, value: value))
        }

        // MARK: Camera (TIFF + lens info from the Exif sub-IFD)

        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]

        add("make", "Camera", "Make", cleaned(tiff?[kCGImagePropertyTIFFMake]))
        add("model", "Camera", "Model", cleaned(tiff?[kCGImagePropertyTIFFModel]))
        add("software", "Camera", "Software", cleaned(tiff?[kCGImagePropertyTIFFSoftware]))
        add("lens_make", "Camera", "Lens Make", cleaned(exif?[kCGImagePropertyExifLensMake]))
        add("lens", "Camera", "Lens", cleaned(exif?[kCGImagePropertyExifLensModel]))
        if let spec = exif?[kCGImagePropertyExifLensSpecification] as? [Double], spec.count == 4 {
            add("lens_spec", "Camera", "Lens Specification", formatLensSpec(spec))
        }
        if let orientation = props[kCGImagePropertyOrientation] as? Int {
            add("orientation", "Camera", "Orientation", orientationName(orientation))
        }

        // MARK: Exposure

        if let f = exif?[kCGImagePropertyExifFNumber] as? Double, f > 0 {
            // Cameras report the lens's exact computed aperture (e.g.
            // 2.79883), not the nominal marketing stop (f/2.8). Round to the
            // nearest tenth so it reads the way photographers expect.
            let roundedF = (f * 10).rounded() / 10
            add("aperture", "Exposure", "Aperture", "f/\(formatG(roundedF))")
        }
        if let et = exif?[kCGImagePropertyExifExposureTime] as? Double, et > 0 {
            let display = et >= 1 ? "\(formatG(et))s" : "1/\(Int((1 / et).rounded()))s"
            add("shutter", "Exposure", "Shutter Speed", display)
        }
        if let iso = firstInt(exif?[kCGImagePropertyExifISOSpeedRatings]) {
            add("iso", "Exposure", "ISO", "ISO \(iso)")
        }
        if let fl = exif?[kCGImagePropertyExifFocalLength] as? Double, fl > 0 {
            add("focal_length", "Exposure", "Focal Length", "\(formatG(fl))mm")
        }
        if let fl35 = exif?[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int, fl35 > 0 {
            add("focal_length_35mm", "Exposure", "Focal Length (35mm equiv.)", "\(fl35)mm")
        }
        if let bias = exif?[kCGImagePropertyExifExposureBiasValue] as? Double {
            add("exposure_bias", "Exposure", "Exposure Bias", formatBias(bias))
        }
        if let program = exif?[kCGImagePropertyExifExposureProgram] as? Int {
            add("exposure_program", "Exposure", "Exposure Program", exposureProgramName(program))
        }
        if let mode = exif?[kCGImagePropertyExifExposureMode] as? Int {
            add("exposure_mode", "Exposure", "Exposure Mode", mode == 0 ? "Auto" : (mode == 1 ? "Manual" : "Auto bracket"))
        }
        if let metering = exif?[kCGImagePropertyExifMeteringMode] as? Int {
            add("metering_mode", "Exposure", "Metering Mode", meteringModeName(metering))
        }
        if let flash = exif?[kCGImagePropertyExifFlash] as? Int {
            add("flash", "Exposure", "Flash", flashName(flash))
        }
        if let wb = exif?[kCGImagePropertyExifWhiteBalance] as? Int {
            add("white_balance", "Exposure", "White Balance", wb == 0 ? "Auto" : "Manual")
        }
        if let cs = exif?[kCGImagePropertyExifColorSpace] as? Int {
            add("color_space", "Exposure", "Color Space", cs == 1 ? "sRGB" : (cs == 65535 ? "Uncalibrated" : "Other (\(cs))"))
        }
        if let scene = exif?[kCGImagePropertyExifSceneCaptureType] as? Int {
            add("scene_capture_type", "Exposure", "Scene Type", sceneCaptureTypeName(scene))
        }

        // MARK: Date

        if let raw = exif?[kCGImagePropertyExifDateTimeOriginal] as? String {
            add("date_taken", "Date", "Date Taken", formatExifDate(raw))
        }
        if let raw = exif?[kCGImagePropertyExifDateTimeDigitized] as? String {
            add("date_digitized", "Date", "Date Digitized", formatExifDate(raw))
        }
        if let raw = tiff?[kCGImagePropertyTIFFDateTime] as? String {
            add("file_modified_exif", "Date", "File Modified (camera)", formatExifDate(raw))
        }

        // MARK: Location

        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
               let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
               let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
               let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String {
                let latSigned = latRef.uppercased() == "S" ? -lat : lat
                let lonSigned = lonRef.uppercased() == "W" ? -lon : lon
                add("location", "Location", "Coordinates", String(format: "%.5f, %.5f", latSigned, lonSigned))
            }
            if let alt = gps[kCGImagePropertyGPSAltitude] as? Double {
                let ref = gps[kCGImagePropertyGPSAltitudeRef] as? Int ?? 0
                let signedAlt = ref == 1 ? -alt : alt
                add("altitude", "Location", "Altitude", "\(Int(signedAlt.rounded()))m")
            }
            if let direction = gps[kCGImagePropertyGPSImgDirection] as? Double {
                add("gps_direction", "Location", "Direction", "\(Int(direction.rounded()))°")
            }
        }

        info.fields = fields
        info.width = props[kCGImagePropertyPixelWidth] as? Int
        info.height = props[kCGImagePropertyPixelHeight] as? Int
        // The orientation tag can swap the visual width/height for 90°/270°
        // rotations — report the dimensions as they'll actually be displayed.
        if let orientation = props[kCGImagePropertyOrientation] as? Int,
           [5, 6, 7, 8].contains(orientation),
           let w = info.width, let h = info.height {
            info.width = h
            info.height = w
        }

        return info
    }

    // MARK: - Helpers

    private static func cleaned(_ value: Any?) -> String? {
        guard let str = value as? String else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{0}")))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstInt(_ value: Any?) -> Int? {
        if let array = value as? [Int], let first = array.first { return first }
        if let single = value as? Int { return single }
        return nil
    }

    /// Mimics Python's "{:g}" formatting — shows a real, unrounded value but
    /// trims trailing zeros (e.g. 2.0 -> "2", 2.79883 stays as-is).
    private static func formatG(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        var str = String(format: "%.6g", value)
        if str.contains(".") {
            while str.hasSuffix("0") { str.removeLast() }
            if str.hasSuffix(".") { str.removeLast() }
        }
        return str
    }

    /// "2026:07:07 20:57:10" -> "2026-07-07 20:57:10"
    private static func formatExifDate(_ raw: String) -> String {
        let parts = raw.split(separator: " ")
        guard parts.count == 2 else { return raw }
        let datePart = parts[0].replacingOccurrences(of: ":", with: "-")
        return "\(datePart) \(parts[1])"
    }

    private static func formatBias(_ value: Double) -> String {
        if value == 0 { return "0 EV" }
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(formatG(value)) EV"
    }

    private static func formatLensSpec(_ spec: [Double]) -> String {
        let (minF, maxF, minA, maxA) = (spec[0], spec[1], spec[2], spec[3])
        let focal = minF == maxF ? "\(formatG(minF))mm" : "\(formatG(minF))–\(formatG(maxF))mm"
        let aperture = minA == maxA ? "f/\(formatG(minA))" : "f/\(formatG(minA))–\(formatG(maxA))"
        return "\(focal) \(aperture)"
    }

    private static func orientationName(_ value: Int) -> String {
        switch value {
        case 1: return "Normal"
        case 2: return "Mirrored horizontally"
        case 3: return "Rotated 180°"
        case 4: return "Mirrored vertically"
        case 5: return "Mirrored, rotated 90° CCW"
        case 6: return "Rotated 90° CW"
        case 7: return "Mirrored, rotated 90° CW"
        case 8: return "Rotated 90° CCW"
        default: return "Unknown (\(value))"
        }
    }

    private static func exposureProgramName(_ value: Int) -> String {
        let names = [0: "Not defined", 1: "Manual", 2: "Program AE", 3: "Aperture priority",
                     4: "Shutter priority", 5: "Creative", 6: "Action", 7: "Portrait", 8: "Landscape", 9: "Bulb"]
        return names[value] ?? "Unknown (\(value))"
    }

    private static func meteringModeName(_ value: Int) -> String {
        let names = [0: "Unknown", 1: "Average", 2: "Center-weighted", 3: "Spot",
                     4: "Multi-spot", 5: "Multi-segment", 6: "Partial", 255: "Other"]
        return names[value] ?? "Unknown (\(value))"
    }

    private static func sceneCaptureTypeName(_ value: Int) -> String {
        let names = [0: "Standard", 1: "Landscape", 2: "Portrait", 3: "Night"]
        return names[value] ?? "Unknown (\(value))"
    }

    /// Flash is a bitmask (EXIF 2.3): bit 0 = fired, bits 1-2 = return light
    /// status, bits 3-4 = flash mode, bit 6 = red-eye reduction.
    private static func flashName(_ value: Int) -> String {
        let known = [
            0x0: "No Flash", 0x1: "Fired", 0x5: "Fired, return not detected",
            0x7: "Fired, return detected", 0x8: "Did not fire", 0x9: "Fired, compulsory",
            0x10: "Off, did not fire", 0x18: "Auto, did not fire", 0x19: "Auto, fired",
            0x1D: "Auto, fired, return not detected", 0x1F: "Auto, fired, return detected",
            0x20: "No flash function", 0x41: "Fired, red-eye reduction",
            0x59: "Auto, fired, red-eye reduction",
        ]
        return known[value] ?? "Unknown (\(value))"
    }
}
