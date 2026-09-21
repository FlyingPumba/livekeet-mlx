import Foundation

/// Project membership follows the folder, including files recorded by the CLI or moved in Finder.
public struct RecordingProject: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var folder: RecordingFile
    public let createdAt: Date

    public var folderURL: URL { folder.url }
    public var isAvailable: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    public func contains(_ recording: Recording) -> Bool {
        recording.transcriptURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == folderURL.path
    }

    /// Bare names are relative to the project; explicit paths must remain directly in its folder.
    public func outputPath(argument: String?, config: LivekeetConfig) throws -> URL {
        guard isAvailable else { throw RecordingLibrary.LibraryError.projectFolderUnavailable }
        var config = config
        config.outputDirectory = folderURL.path
        var argument = argument
        if let name = argument, !name.isEmpty, !name.contains("/"), !name.hasPrefix("~") {
            argument = folderURL.appendingPathComponent(name).path
        }
        let output = resolveOutputPath(arg: argument, config: config)
        guard output.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == folderURL.path else {
            throw RecordingLibrary.LibraryError.outputOutsideProject
        }
        return output
    }

    public static func suggestedFolder(name: String, base: URL) -> URL {
        let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return base.appendingPathComponent(safeName.isEmpty || safeName == "." || safeName == ".." ? "New project" : safeName, isDirectory: true)
    }
}
