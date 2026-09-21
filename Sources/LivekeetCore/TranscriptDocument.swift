import Foundation

public struct TranscriptLine: Identifiable, Sendable {
    public let id: Int
    public let timestamp: String
    public let speaker: String
    public let text: String
}

/// Edits only timestamped speaker labels, preserving transcript text and metadata.
public struct TranscriptDocument {
    public let content: String
    private static let linePattern = try! NSRegularExpression(
        pattern: #"(?m)^\[\d{2}:\d{2}:\d{2}\] \*\*([^\r\n]+?)\*\*: ([^\r\n]*)"#
    )

    public init(content: String) { self.content = content }

    public var lines: [TranscriptLine] {
        let source = content as NSString
        return matches.enumerated().map { index, match in
            TranscriptLine(id: index, timestamp: source.substring(with: NSRange(location: match.range.location + 1, length: 8)),
                           speaker: source.substring(with: match.range(at: 1)), text: source.substring(with: match.range(at: 2)))
        }
    }

    public var speakers: [String] {
        var seen = Set<String>()
        return matches.compactMap { match in
            let name = (content as NSString).substring(with: match.range(at: 1))
            return seen.insert(name).inserted ? name : nil
        }
    }

    public func quotes(for speaker: String) -> [String] {
        matches.compactMap { match in
            let source = content as NSString
            return source.substring(with: match.range(at: 1)) == speaker
                ? source.substring(with: match.range(at: 2)) : nil
        }
    }

    public func renaming(_ names: [String: String]) throws -> String {
        for name in names.values {
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
                  !name.contains("**"), !name.contains("\n"), !name.contains("\r") else {
                throw DocumentError.invalidName
            }
        }
        let result = NSMutableString(string: content)
        // Replace original ranges backwards: name swaps and placeholder-like names are safe.
        for match in matches.reversed() {
            let range = match.range(at: 1)
            if let name = names[(content as NSString).substring(with: range)] {
                result.replaceCharacters(in: range, with: name)
            }
        }
        return result as String
    }

    private var matches: [NSTextCheckingResult] {
        Self.linePattern.matches(in: content, range: NSRange(content.startIndex..., in: content))
    }

    public enum DocumentError: LocalizedError {
        case invalidName
        public var errorDescription: String? { "Speaker names must be nonempty and cannot contain newlines or **." }
    }
}
