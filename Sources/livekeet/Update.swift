import ArgumentParser
import Foundation
import LivekeetCore

struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Update a source-installed CLI, or check its tracked branch for updates.")
    @Flag(help: "Only check for updates; do not rebuild or install.") var check = false
    @Option(help: "Source checkout to update; required for an uninstalled development binary.") var source: String?

    func run() async throws {
        let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        let metadata = executable.deletingLastPathComponent().appendingPathComponent("install.json")
        let installation = (try? Data(contentsOf: metadata)).flatMap { try? JSONDecoder().decode(Installation.self, from: $0) }
        guard let path = source ?? installation?.source else {
            throw ValidationError("Use livekeet update --source /path/to/checkout, or install with make install. Update the Mac app through Check for Updates.")
        }
        let directory = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        // Updating source must never discard local changes or switch branches.
        let dirty = try runProcess("git", ["status", "--porcelain"], at: directory)
        let upstream = try runProcess("git", ["rev-parse", "--abbrev-ref", "@{upstream}"], at: directory).trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = try runProcess("git", ["config", "--get", "branch.\(try runProcess("git", ["branch", "--show-current"], at: directory).trimmingCharacters(in: .whitespacesAndNewlines)).remote"], at: directory).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try runProcess("git", ["fetch", remote], at: directory)
        let counts = try runProcess("git", ["rev-list", "--left-right", "--count", "HEAD...\(upstream)"], at: directory)
            .split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        guard counts.count == 2 else { throw ValidationError("Could not compare the checkout with its upstream.") }
        if counts[1] == 0 { print("Source is up to date with \(upstream).") }
        else { print("\(counts[1]) upstream commits available on \(upstream).") }
        if check { return }
        guard counts[0] == 0 || counts[1] == 0 else {
            throw ValidationError("The source branch has diverged from \(upstream). Merge or rebase it before updating.")
        }
        guard dirty.isEmpty else { throw ValidationError("The source checkout has local changes. Commit or stash them before updating.") }
        _ = try runProcess("git", ["merge", "--ff-only", upstream], at: directory)
        let prefix = installation?.prefix ?? NSHomeDirectory() + "/.local"
        _ = try runProcess("make", ["install", "PREFIX=\(prefix)"], at: directory, capture: false)
        print("CLI updated. The Mac app updates separately through Sparkle.")
    }

    struct Installation: Decodable { let source: String; let prefix: String }

    private func runProcess(_ command: String, _ arguments: [String], at directory: URL, capture: Bool = true) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        if capture { process.standardOutput = pipe }
        process.standardError = FileHandle.standardError
        try process.run()
        let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ValidationError("\(command) failed (exit \(process.terminationStatus)).") }
        return String(decoding: data, as: UTF8.self)
    }
}
