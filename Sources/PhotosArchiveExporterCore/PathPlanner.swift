import Foundation

public struct PathPlanner {
    private let calendar: Calendar
    private let timeZone: TimeZone

    public init(calendar: Calendar = Calendar(identifier: .gregorian), timeZone: TimeZone = .current) {
        var configured = calendar
        configured.timeZone = timeZone
        self.calendar = configured
        self.timeZone = timeZone
    }

    public func preferredDestination(root: URL, captureDate: Date, originalFilename: String) -> URL {
        let year = format(captureDate, "yyyy")
        let month = format(captureDate, "yyyy-MM")
        let day = format(captureDate, "yyyy-MM-dd")
        let timePrefix = format(captureDate, "yyyy-MM-dd_HH-mm-ss")
        let safeFilename = FilenameSanitizer.sanitize(originalFilename)
        return root
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
            .appendingPathComponent(day, isDirectory: true)
            .appendingPathComponent("\(timePrefix)_\(safeFilename)", isDirectory: false)
    }

    public static func resolveConflict(for preferred: URL, exists: (URL) -> Bool) -> URL {
        if !exists(preferred) {
            return preferred
        }

        let directory = preferred.deletingLastPathComponent()
        let base = preferred.deletingPathExtension().lastPathComponent
        let ext = preferred.pathExtension
        var counter = 2

        while true {
            let filename = ext.isEmpty ? "\(base)__\(counter)" : "\(base)__\(counter).\(ext)"
            let candidate = directory.appendingPathComponent(filename, isDirectory: false)
            if !exists(candidate) {
                return candidate
            }
            counter += 1
        }
    }

    private func format(_ date: Date, _ template: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = template
        return formatter.string(from: date)
    }
}
