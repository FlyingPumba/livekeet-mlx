import Darwin
import Foundation

/// A bookmark follows files renamed or moved in Finder; the path also works when a
/// filesystem cannot supply bookmarks, or when an atomic transcript rewrite changes its inode.
public struct RecordingFile: Codable, Hashable, Sendable {
    public let path: String
    private let bookmark: Data?

    public init(url: URL) {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        path = normalized.path
        bookmark = try? normalized.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public var url: URL {
        let original = URL(fileURLWithPath: path)
        var stale = false
        if let bookmark,
           let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
           FileManager.default.fileExists(atPath: resolved.path) {
            return resolved.standardizedFileURL.resolvingSymlinksInPath()
        }
        return original
    }
}

public struct Recording: Codable, Hashable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable { case unfinished, saved, imported }
    public let id: UUID
    public let startedAt: Date
    public var endedAt: Date?
    public var transcript: RecordingFile
    public var audioDirectory: RecordingFile?
    public var modelID: String?
    public var participants: [String]
    public var status: Status

    public var title: String { transcript.url.deletingPathExtension().lastPathComponent }
    public var transcriptURL: URL { transcript.url }
    public var isAvailable: Bool { FileManager.default.fileExists(atPath: transcriptURL.path) }
}

/// A local index shared by the app and CLI. Transcript/audio files remain in their
/// chosen folders. Lock + atomic replacement prevents concurrent processes losing entries.
public actor RecordingLibrary {
    public static let shared = RecordingLibrary()
    public static var defaultDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["LIVEKEET_DATA_DIRECTORY"], !path.isEmpty {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Livekeet", isDirectory: true)
    }
    public let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("recordings.json") }

    private struct Index: Codable {
        var version = 2
        var recordings: [Recording] = []
        var projects: [RecordingProject] = []

        init() {}
        private enum CodingKeys: String, CodingKey { case version, recordings, projects }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            recordings = try values.decode([Recording].self, forKey: .recordings)
            projects = try values.decodeIfPresent([RecordingProject].self, forKey: .projects) ?? []
        }
    }

    public init(directory: URL = RecordingLibrary.defaultDirectory) { self.directory = directory }

    public func recordings() throws -> [Recording] {
        try locked { try read().recordings.sorted { $0.startedAt > $1.startedAt } }
    }

    @discardableResult
    public func begin(transcript: URL, audioDirectory: URL?, modelID: String, participants: [String], date: Date = Date()) throws -> Recording {
        try locked {
            var index = try read()
            let existing = index.recordings.firstIndex { $0.transcriptURL.path == transcript.standardizedFileURL.resolvingSymlinksInPath().path }
            let recording = Recording(id: existing.map { index.recordings[$0].id } ?? UUID(), startedAt: date, transcript: RecordingFile(url: transcript),
                                      audioDirectory: audioDirectory.map(RecordingFile.init), modelID: modelID,
                                      participants: participants, status: .unfinished)
            if let existing { index.recordings[existing] = recording } else { index.recordings.append(recording) }
            try save(index)
            return recording
        }
    }

    public func finish(id: UUID, date: Date = Date()) throws {
        try locked {
            var index = try read()
            guard let i = index.recordings.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingEntry }
            index.recordings[i].endedAt = date
            index.recordings[i].status = .saved
            // Refresh bookmarks after the writer's final atomic rewrite.
            index.recordings[i].transcript = RecordingFile(url: index.recordings[i].transcriptURL)
            if let audio = index.recordings[i].audioDirectory { index.recordings[i].audioDirectory = RecordingFile(url: audio.url) }
            try save(index)
        }
    }

    @discardableResult
    public func importTranscript(_ url: URL) throws -> Recording {
        let date = try Self.transcriptDate(url)
        return try locked {
            var index = try read()
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            if let existing = index.recordings.first(where: { $0.transcriptURL.standardizedFileURL.path == path }) { return existing }
            let audio = url.deletingPathExtension().appendingPathExtension("audio")
            let recording = Recording(id: UUID(), startedAt: date, transcript: RecordingFile(url: url),
                                      audioDirectory: FileManager.default.fileExists(atPath: audio.path) ? RecordingFile(url: audio) : nil,
                                      participants: [], status: .imported)
            index.recordings.append(recording)
            try save(index)
            return recording
        }
    }

    /// Scan only the selected output folder, non-recursively, and recognize Livekeet's header.
    public func discover(in folder: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        for file in files where file.pathExtension.lowercased() == "md" {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  (try? Self.transcriptDate(file)) != nil else { continue }
            _ = try importTranscript(file)
        }
    }

    public func locate(id: UUID, transcript: URL) throws {
        _ = try Self.transcriptDate(transcript)
        try locked {
            var index = try read()
            guard let i = index.recordings.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingEntry }
            let path = transcript.standardizedFileURL.resolvingSymlinksInPath().path
            if index.recordings.contains(where: { $0.id != id && $0.transcriptURL.path == path }) { throw LibraryError.duplicateFile }
            index.recordings[i].transcript = RecordingFile(url: transcript)
            let audio = transcript.deletingPathExtension().appendingPathExtension("audio")
            if FileManager.default.fileExists(atPath: audio.path) { index.recordings[i].audioDirectory = RecordingFile(url: audio) }
            try save(index)
        }
    }

    public func projects() throws -> [RecordingProject] {
        try locked { try read().projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    }

    public func project(named nameOrID: String) throws -> RecordingProject {
        guard let project = try projects().first(where: {
            $0.id.uuidString.caseInsensitiveCompare(nameOrID) == .orderedSame || $0.name.caseInsensitiveCompare(nameOrID) == .orderedSame
        }) else { throw LibraryError.missingProject }
        return project
    }

    @discardableResult
    public func createProject(name: String, folder: URL) throws -> RecordingProject {
        try locked {
            var index = try read()
            let name = try Self.validProjectName(name, excluding: nil, in: index)
            let path = folder.standardizedFileURL.resolvingSymlinksInPath().path
            guard !index.projects.contains(where: { $0.folderURL.path == path }) else { throw LibraryError.duplicateProjectFolder }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let project = RecordingProject(id: UUID(), name: name, folder: RecordingFile(url: folder), createdAt: Date())
            index.projects.append(project)
            try save(index)
            return project
        }
    }

    public func renameProject(id: UUID, name: String) throws {
        try locked {
            var index = try read()
            guard let i = index.projects.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingProject }
            index.projects[i].name = try Self.validProjectName(name, excluding: id, in: index)
            try save(index)
        }
    }

    /// Removes the grouping only. All files and recording entries stay intact.
    public func removeProject(id: UUID) throws {
        try locked {
            var index = try read()
            index.projects.removeAll { $0.id == id }
            try save(index)
        }
    }

    /// Moves the transcript and its audio together, avoiding collisions and rolling back on failure.
    public func moveRecording(id: UUID, toProject projectID: UUID) throws {
        try locked {
            var index = try read()
            guard let i = index.recordings.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingEntry }
            guard let project = index.projects.first(where: { $0.id == projectID }) else { throw LibraryError.missingProject }
            guard project.isAvailable else { throw LibraryError.projectFolderUnavailable }
            let recording = index.recordings[i]
            guard recording.status != .unfinished else { throw LibraryError.recordingInProgress }
            guard recording.isAvailable else { throw CocoaError(.fileNoSuchFile) }
            if project.contains(recording) { return }
            let source = recording.transcriptURL
            let audioSource = recording.audioDirectory?.url
            if let audioSource, !FileManager.default.fileExists(atPath: audioSource.path) {
                throw LibraryError.audioUnavailable
            }
            var target = project.folderURL.appendingPathComponent(source.lastPathComponent)
            var suffix = 2
            while FileManager.default.fileExists(atPath: target.path) ||
                  FileManager.default.fileExists(atPath: target.deletingPathExtension().appendingPathExtension("audio").path) {
                target = project.folderURL.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(suffix).\(source.pathExtension)")
                suffix += 1
            }
            let audioTarget = target.deletingPathExtension().appendingPathExtension("audio")
            var moved: [(URL, URL)] = []
            do {
                if let audioSource {
                    try FileManager.default.moveItem(at: audioSource, to: audioTarget)
                    moved.append((audioSource, audioTarget))
                }
                try FileManager.default.moveItem(at: source, to: target)
                moved.append((source, target))
                index.recordings[i].transcript = RecordingFile(url: target)
                index.recordings[i].audioDirectory = audioSource == nil ? nil : RecordingFile(url: audioTarget)
                try save(index)
            } catch {
                let originalError = error
                var recoveryErrors: [String] = []
                for (original, destination) in moved.reversed() {
                    do { try FileManager.default.moveItem(at: destination, to: original) }
                    catch { recoveryErrors.append("\(destination.path): \(error.localizedDescription)") }
                }
                if !recoveryErrors.isEmpty { throw LibraryError.moveRecoveryFailed(recoveryErrors.joined(separator: "\n")) }
                throw originalError
            }
        }
    }

    private static func validProjectName(_ name: String, excluding id: UUID?, in index: Index) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("\n"), !name.contains("\r") else { throw LibraryError.invalidProjectName }
        guard !index.projects.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw LibraryError.duplicateProjectName
        }
        return name
    }

    private static func transcriptDate(_ url: URL) throws -> Date {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 256) ?? Data()
        let firstLine = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines).first ?? ""
        guard firstLine.hasPrefix("# Transcription - ") else { throw LibraryError.notTranscript }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: String(firstLine.dropFirst("# Transcription - ".count)))
            ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }

    private func read() throws -> Index {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return Index() }
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
        guard (1...2).contains(index.version) else { throw LibraryError.unsupportedVersion }
        return index
    }

    private func save(_ index: Index) throws {
        var index = index
        index.version = 2
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appendingPathComponent("recordings.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }

    public enum LibraryError: LocalizedError {
        case missingEntry, notTranscript, duplicateFile, unsupportedVersion
        case missingProject, invalidProjectName, duplicateProjectName, duplicateProjectFolder
        case projectFolderUnavailable, outputOutsideProject, recordingInProgress, audioUnavailable
        case moveRecoveryFailed(String)
        public var errorDescription: String? {
            switch self {
            case .missingProject: "Project not found. Refresh the list or run livekeet projects list."
            case .invalidProjectName: "Enter a project name without line breaks."
            case .duplicateProjectName: "A project with that name already exists."
            case .duplicateProjectFolder: "That folder already belongs to a project."
            case .projectFolderUnavailable: "The project folder is unavailable. Reconnect its drive before recording or moving files."
            case .outputOutsideProject: "Project recordings must save directly in the project folder. Use a filename or omit the output argument."
            case .recordingInProgress: "Finish the recording before moving it to a project."
            case .audioUnavailable: "The recording’s audio folder is unavailable. Reconnect it before moving the recording."
            case .moveRecoveryFailed(let details): "The move could not finish or be fully undone. Some files remain at these locations: \(details)"
            case .missingEntry: "This recording is no longer in the library. Refresh and try again."
            case .notTranscript: "Choose a Livekeet Markdown transcript with a Transcription header."
            case .duplicateFile: "That transcript is already in the recordings list."
            case .unsupportedVersion: "The recording library was written by a newer Livekeet version. Update the app to read it."
            }
        }
    }
}
