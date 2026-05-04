import Foundation

public enum FilenameSanitizer {
    public static func sanitize(_ filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "unnamed"
        }

        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let scalars = trimmed.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) || CharacterSet.controlCharacters.contains(scalar) ? "_" : Character(scalar)
        }
        let cleaned = String(scalars)
        return cleaned.isEmpty ? "unnamed" : cleaned
    }
}
