import Foundation

public enum DeterministicCorrections {
    /// Literal, case-insensitive replacements at word boundaries, longest keys first.
    public static func apply(_ text: String, replacements: [String: String]) -> String {
        replacements.keys.sorted {
            $0.count == $1.count ? $0 < $1 : $0.count > $1.count
        }.reduce(text) { result, key in
            guard !key.isEmpty,
                  let regex = try? NSRegularExpression(
                    pattern: "\\b" + NSRegularExpression.escapedPattern(for: key) + "\\b",
                    options: .caseInsensitive
                  ) else { return result }
            return regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: replacements[key]!)
            )
        }
    }
}
