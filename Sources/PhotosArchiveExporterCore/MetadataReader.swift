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

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let rawDate = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String

        guard let rawDate else {
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

            if item.identifier?.rawValue.lowercased().contains("creationdate") == true, let date = item.dateValue {
                return date
            }

            if item.identifier?.rawValue.lowercased().contains("creationdate") == true, let string = item.stringValue {
                return ISO8601DateFormatter().date(from: string)
            }
        }

        return nil
    }

    private static func parseExifDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }
}
