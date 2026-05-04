import Foundation

public enum CaptureDateResolver {
    public static func resolve(exifOriginal: Date?, quickTimeCreation: Date?, assetCreationDate: Date?, exportRunDate: Date) -> CaptureDateDecision {
        if let exifOriginal {
            return CaptureDateDecision(date: exifOriginal, source: .exifOriginal, warnings: [])
        }

        if let quickTimeCreation {
            return CaptureDateDecision(date: quickTimeCreation, source: .quickTimeCreation, warnings: [])
        }

        if let assetCreationDate {
            return CaptureDateDecision(date: assetCreationDate, source: .assetCreationDate, warnings: [])
        }

        return CaptureDateDecision(date: exportRunDate, source: .exportRunDate, warnings: ["missing_capture_date"])
    }
}
