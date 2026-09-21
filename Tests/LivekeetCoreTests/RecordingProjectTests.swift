import XCTest
@testable import LivekeetCore

final class RecordingProjectTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }
    private func transcript(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Transcription - 2026-09-21 10:00:00\n\n[10:00:01] **Iván**: Hola.\n".write(to: url, atomically: true, encoding: .utf8)
    }

    func testLegacyLibraryMigratesWithoutLosingRecordings() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(directory: root.appendingPathComponent("Library"))
        let file = root.appendingPathComponent("Existing/Meeting.md")
        try transcript(file)
        let recording = try await library.importTranscript(file)
        let indexURL = root.appendingPathComponent("Library/recordings.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any])
        json["version"] = 1
        json.removeValue(forKey: "projects")
        try JSONSerialization.data(withJSONObject: json).write(to: indexURL)
        let projects = try await library.projects()
        XCTAssertTrue(projects.isEmpty)
        let project = try await library.createProject(name: "Existing", folder: file.deletingLastPathComponent())
        let recordings = try await library.recordings()
        XCTAssertEqual(recordings.map(\.id), [recording.id])
        XCTAssertTrue(project.contains(recordings[0]))
        let updated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any])
        XCTAssertEqual(updated["version"] as? Int, 2)
    }

    func testProjectFolderDefinesMembershipAndSurvivesFolderMove() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(directory: root.appendingPathComponent("Library"))
        let folder = root.appendingPathComponent("Team")
        let project = try await library.createProject(name: "Team", folder: folder)
        try transcript(folder.appendingPathComponent("Meeting.md"))
        try transcript(folder.appendingPathComponent("Nested/Other.md"))
        try await library.discover(in: folder)
        let recordings = try await library.recordings()
        XCTAssertEqual(recordings.filter(project.contains).count, 1)
        let moved = root.appendingPathComponent("Relocated Team")
        try FileManager.default.moveItem(at: folder, to: moved)
        let reloaded = try await library.project(named: "team")
        XCTAssertEqual(reloaded.folderURL.path, moved.path)
        XCTAssertTrue(reloaded.contains(recordings[0]))
        try await library.renameProject(id: project.id, name: "Research")
        let renamed = try await library.project(named: project.id.uuidString)
        XCTAssertEqual(renamed.name, "Research")
        XCTAssertEqual(renamed.folderURL.path, moved.path)
        try await library.removeProject(id: project.id)
        let afterRemoval = try await library.recordings()
        XCTAssertEqual(afterRemoval.count, 1)
        XCTAssertTrue(afterRemoval[0].isAvailable)
    }

    func testDuplicateProjectsAreRejectedWithoutChangingExistingEntries() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(directory: root.appendingPathComponent("Library"))
        let folder = root.appendingPathComponent("Team")
        _ = try await library.createProject(name: "Team", folder: folder)
        for (name, url) in [(" team ", root.appendingPathComponent("Other")), ("Other", folder), ("  ", folder)] {
            do { _ = try await library.createProject(name: name, folder: url); XCTFail("Expected validation failure") }
            catch { }
        }
        let projects = try await library.projects()
        XCTAssertEqual(projects.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Other").path))
    }

    func testMovePreservesIdentityAndAudioWithoutOverwritingCollisions() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(directory: root.appendingPathComponent("Library"))
        let source = root.appendingPathComponent("Old/Meeting.md")
        try transcript(source)
        let audio = root.appendingPathComponent("Old/Meeting.audio")
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        let bytes = Data([1, 2, 3, 4])
        try bytes.write(to: audio.appendingPathComponent("microphone.wav"))
        let recording = try await library.importTranscript(source)
        let project = try await library.createProject(name: "Team", folder: root.appendingPathComponent("Team"))
        let existing = project.folderURL.appendingPathComponent("Meeting.md")
        try transcript(existing)
        let original = try Data(contentsOf: existing)
        try FileManager.default.createDirectory(at: project.folderURL.appendingPathComponent("Meeting-2.audio"), withIntermediateDirectories: true)
        try await library.moveRecording(id: recording.id, toProject: project.id)
        let entries = try await library.recordings()
        let moved = try XCTUnwrap(entries.first { $0.id == recording.id })
        XCTAssertEqual(moved.transcriptURL.lastPathComponent, "Meeting-3.md")
        XCTAssertTrue(project.contains(moved))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: existing), original)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(moved.audioDirectory).url.appendingPathComponent("microphone.wav")), bytes)
        try await library.discover(in: project.folderURL)
        let discovered = try await library.recordings()
        XCTAssertEqual(discovered.filter { $0.id == recording.id }.count, 1)
    }

    func testMoveRollsBackFilesWhenIndexCannotBeSaved() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Library")
        let library = RecordingLibrary(directory: directory)
        let source = root.appendingPathComponent("Old/Meeting.md")
        try transcript(source)
        let recording = try await library.importTranscript(source)
        let project = try await library.createProject(name: "Team", folder: root.appendingPathComponent("Team"))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        do { try await library.moveRecording(id: recording.id, toProject: project.id); XCTFail("Expected write failure") }
        catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.folderURL.appendingPathComponent("Meeting.md").path))
        let recordings = try await library.recordings()
        XCTAssertEqual(recordings[0].transcriptURL.path, source.path)
    }

    func testProjectOutputIsConfinedToItsFolderAndMissingFoldersAreNotRecreated() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(directory: root.appendingPathComponent("Library"))
        let project = try await library.createProject(name: "Team", folder: root.appendingPathComponent("Team"))
        let config = LivekeetConfig(outputDirectory: root.path, filenamePattern: "Default.md")
        XCTAssertEqual(try project.outputPath(argument: nil, config: config).path, project.folderURL.appendingPathComponent("Default.md").path)
        XCTAssertEqual(try project.outputPath(argument: "Weekly", config: config).lastPathComponent, "Weekly.md")
        XCTAssertThrowsError(try project.outputPath(argument: root.appendingPathComponent("Outside.md").path, config: config))
        XCTAssertThrowsError(try project.outputPath(argument: "../Outside.md", config: config))
        try FileManager.default.removeItem(at: project.folderURL)
        XCTAssertThrowsError(try project.outputPath(argument: nil, config: config))
        XCTAssertFalse(project.isAvailable)
    }
}
