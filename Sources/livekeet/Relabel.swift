import ArgumentParser
import Darwin
import Foundation
import LivekeetCore

struct Relabel: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Rename speakers in an existing transcript without changing its text.")
    @Argument(help: "Transcript Markdown file.") var file: String
    @Option(name: .customLong("rename"), parsing: .singleValue, help: "Rename OLD=NEW; repeat for multiple names. Swaps are safe.")
    var renames: [String] = []

    func run() throws {
        let url = URL(fileURLWithPath: NSString(string: file).expandingTildeInPath)
        if renames.isEmpty {
            guard isatty(STDIN_FILENO) != 0 else {
                throw ValidationError("Interactive relabeling needs a terminal. Use --rename 'Old=New' for scripts.")
            }
            try Self.interactive(url)
        } else {
            let document = TranscriptDocument(content: try String(contentsOf: url, encoding: .utf8))
            var mapping: [String: String] = [:]
            for rename in renames {
                let parts = rename.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, document.speakers.contains(String(parts[0])) else {
                    throw ValidationError("Use --rename 'Existing speaker=New name'. Speakers: \(document.speakers.joined(separator: ", ")).")
                }
                mapping[String(parts[0])] = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
            try document.renaming(mapping).write(to: url, atomically: true, encoding: .utf8)
            print("Updated: \(url.path)")
        }
    }

    static func interactive(_ url: URL) throws {
        let document = TranscriptDocument(content: try String(contentsOf: url, encoding: .utf8))
        guard document.speakers.count > 1 else { print("No multiple speakers to relabel."); return }
        var mapping: [String: String] = [:]
        print("\nRelabel speakers in \(url.lastPathComponent). Ctrl+C cancels without saving.")
        for speaker in document.speakers {
            let quotes = document.quotes(for: speaker)
            var shown = 0
            print("\nSpeaker \"\(speaker)\" (\(quotes.count) lines):")
            while true {
                let end = min(shown + 3, quotes.count)
                for quote in quotes[shown..<end] { print("  > \(quote)") }
                shown = end
                print("  (n) Name  (m) More  (s) Skip: ", terminator: "")
                fflush(stdout)
                guard let answer = readLine() else { print("\nCancelled; no changes saved."); return }
                if answer.lowercased() == "m", shown < quotes.count { continue }
                if answer.lowercased() == "n" {
                    print("  New name: ", terminator: "")
                    fflush(stdout)
                    guard let name = readLine() else { print("\nCancelled; no changes saved."); return }
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { mapping[speaker] = trimmed }
                }
                break
            }
        }
        guard !mapping.isEmpty else { return }
        try document.renaming(mapping).write(to: url, atomically: true, encoding: .utf8)
        print("Updated: \(url.path)")
    }
}
