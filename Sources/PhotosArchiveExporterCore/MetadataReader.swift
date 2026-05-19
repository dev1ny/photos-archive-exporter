import AVFoundation
import Foundation
import ImageIO

public struct ResourceMetadataDates: Equatable {
    public let exifOriginal: Date?
    public let quickTimeCreation: Date?

    public init(exifOriginal: Date?, quickTimeCreation: Date?) {
        self.exifOriginal = exifOriginal
        self.quickTimeCreation = quickTimeCreation
    }
}

public enum MetadataReader {
    /// EXIF DateTimeOriginal does not encode a time zone. We anchor it to UTC so
    /// the resulting `Date` is deterministic regardless of the machine running
    /// the export. Downstream code (PathPlanner) should format using the same
    /// zone to avoid drift between metadata and folder names.
    public static let exifAssumedTimeZone = TimeZone(identifier: "UTC") ?? .gmt

    public static func readCaptureDates(from url: URL) -> ResourceMetadataDates {
        ResourceMetadataDates(
            exifOriginal: readExifOriginalDate(from: url),
            quickTimeCreation: readQuickTimeCreationDate(from: url)
        )
    }

    private static func readExifOriginalDate(from url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        guard let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let rawDate = exif[kCGImagePropertyExifDateTimeOriginal] as? String else {
            return nil
        }

        return parseExifDate(rawDate)
    }

    private static func readQuickTimeCreationDate(from url: URL) -> Date? {
        let asset = AVURLAsset(url: url)
        let metadataItems = asset.commonMetadata + asset.metadata
        for item in metadataItems {
            if item.commonKey?.rawValue == "creationDate", let date = item.dateValue {
                return date
            }

            let isCreationDateIdentifier = item.identifier?.rawValue.lowercased().contains("creationdate") == true
            guard isCreationDateIdentifier else { continue }

            if let date = item.dateValue {
                return date
            }

            // Some containers expose creationDate only as a string (e.g. ISO 8601
            // or "yyyy-MM-dd HH:mm:ss"). The previous implementation gated the
            // string fallback on the same `dateValue` check above, making it
            // unreachable. We try a couple of common formats here.
            if let string = item.stringValue, let parsed = parseQuickTimeStringDate(string) {
                return parsed
            }
        }

        return nil
    }

    private static func parseExifDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = exifAssumedTimeZone
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }

    private static func parseQuickTimeStringDate(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: value) {
            return date
        }
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = exifAssumedTimeZone
        for pattern in ["yyyy-MM-dd'T'HH:mm:ssZZZZZ",
                        "yyyy-MM-dd HH:mm:ss ZZZZZ",
                        "yyyy-MM-dd HH:mm:ss",
                        "yyyy:MM:dd HH:mm:ss"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}
