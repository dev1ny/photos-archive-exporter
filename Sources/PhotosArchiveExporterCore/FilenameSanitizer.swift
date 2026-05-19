import Foundation

public enum FilenameSanitizer {
    /// macOS / APFS allow ~255 *bytes* per path component. PathPlanner prepends
    /// a ~20-byte timestamp prefix to the sanitized filename, so we cap the
    /// sanitized portion at 200 bytes to leave headroom for the prefix, the
    /// conflict suffix (`__99`), and the extension separator.
    private static let maxByteLength = 200

    /// Reserved DOS / Windows device names. macOS doesn't reject them, but a
    /// user copying the archive to a Windows volume or sharing it via SMB will
    /// hit failures. Cheap to neutralize here.
    private static let reservedWindowsNames: Set<String> = [
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    ]

    public static func sanitize(_ filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "unnamed"
        }

        // Characters that break on at least one of: HFS+, APFS, FAT/exFAT, NTFS, ext4.
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let scalars = trimmed.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) || CharacterSet.controlCharacters.contains(scalar) ? "_" : Character(scalar)
        }
        var cleaned = String(scalars)

        // FAT32 / exFAT refuse names ending with a space or a dot. macOS doesn't,
        // but cross-volume copies (e.g. archiving to an external Windows-formatted
        // drive) will fail silently. Strip trailing dots and spaces, preserving
        // any internal extension dot via the loop guard.
        while let last = cleaned.last, last == "." || last == " " {
            cleaned.removeLast()
        }
        if cleaned.isEmpty {
            return "unnamed"
        }

        // Neutralize Windows reserved device names (case-insensitive, with or
        // without an extension): `CON`, `CON.txt`, `con.JPG`, … all become
        // `_CON.txt` etc. so they survive a round-trip onto a Windows volume.
        let stem = (cleaned as NSString).deletingPathExtension
        if reservedWindowsNames.contains(stem.uppercased()) {
            cleaned = "_" + cleaned
        }

        // Cap byte length so we don't blow past 255 bytes per path component
        // (macOS/APFS limit). We measure UTF-8 bytes so multi-byte names (CJK,
        // emoji) are accounted for correctly.
        cleaned = truncateToByteLength(cleaned, maxBytes: maxByteLength)

        return cleaned.isEmpty ? "unnamed" : cleaned
    }

    private static func truncateToByteLength(_ value: String, maxBytes: Int) -> String {
        guard value.utf8.count > maxBytes else { return value }

        // Preserve the file extension. If the extension itself is absurdly
        // long, fall back to truncating the whole string.
        let nsValue = value as NSString
        let ext = nsValue.pathExtension
        let stem = nsValue.deletingPathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let suffixBytes = suffix.utf8.count

        guard suffixBytes < maxBytes else {
            return truncateBytes(value, maxBytes: maxBytes)
        }

        let stemBudget = maxBytes - suffixBytes
        return truncateBytes(stem, maxBytes: stemBudget) + suffix
    }

    /// Truncates without splitting a multi-byte UTF-8 scalar.
    private static func truncateBytes(_ value: String, maxBytes: Int) -> String {
        if value.utf8.count <= maxBytes { return value }
        var result = ""
        var bytes = 0
        for scalar in value.unicodeScalars {
            let scalarBytes = String(scalar).utf8.count
            if bytes + scalarBytes > maxBytes { break }
            result.unicodeScalars.append(scalar)
            bytes += scalarBytes
        }
        return result
    }
}
