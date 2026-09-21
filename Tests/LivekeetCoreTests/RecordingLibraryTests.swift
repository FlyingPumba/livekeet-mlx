import AVFoundation
import XCTest
@testable import LivekeetCore

final class RecordingLibraryTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    private func transcript(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Transcription - 2026-09-21 10:00:00\n\n[10:00:01] **Iván**: Hola, equipo.\n\n---\n*Ended: 2026-09-21 10:01:00*\n"
            .write(to: url, atomically: true, encoding: .utf8)
    }

    func testRecordingsInDifferentFoldersSurviveReloadAndCompletion() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let libraryURL = root.appendingPathComponent("Library")
        let first = root.appendingPathComponent("Team A/Meeting.md")
        let second = root.appendingPathComponent("Team B/Meeting.md")
        try transcript(first); try transcript(second)
        let library = RecordingLibrary(directory: libraryURL)
        let a = try await library.begin(transcript: first, audioDirectory: nil, modelID: "model-a", participants: ["Iván"])
        let b = try await library.begin(transcript: second, audioDirectory: nil, modelID: "model-b", participants: [])
        try await library.finish(id: a.id)
        let reloaded = try await RecordingLibrary(directory: libraryURL).recordings()
        XCTAssertEqual(Set(reloaded.map(\.id)), [a.id, b.id])
        XCTAssertEqual(reloaded.first { $0.id == a.id }?.status, .saved)
        XCTAssertEqual(reloaded.first { $0.id == b.id }?.status, .unfinished)
        XCTAssertEqual(Set(reloaded.map { $0.transcriptURL.path }), [first.path, second.path])
    }

    func testDiscoveryIsSelectiveAndDoesNotDuplicateAnActiveRecording() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let meeting = root.appendingPathComponent("Meeting.md")
        try transcript(meeting)
        try "# Unrelated notes".write(to: root.appendingPathComponent("Notes.md"), atomically: true, encoding: .utf8)
        let library = RecordingLibrary(directory: root.appendingPathComponent("Library"))
        try await library.discover(in: root)
        let imported = try await library.importTranscript(meeting)
        let active = try await library.begin(transcript: meeting, audioDirectory: nil, modelID: "model", participants: [])
        try await library.discover(in: root)
        let recordings = try await library.recordings()
        XCTAssertEqual(imported.id, active.id)
        XCTAssertEqual(recordings.count, 1)
        XCTAssertEqual(recordings.first?.status, .unfinished)
    }

    func testBookmarkFollowsMoveAndMissingFileRemainsInLibrary() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.md")
        let moved = root.appendingPathComponent("moved.md")
        try transcript(original)
        let library = RecordingLibrary(directory: root.appendingPathComponent("Library"))
        let entry = try await library.importTranscript(original)
        try FileManager.default.moveItem(at: original, to: moved)
        XCTAssertEqual(entry.transcriptURL.path, moved.path)
        try FileManager.default.removeItem(at: moved)
        let missing = try await library.recordings()
        XCTAssertEqual(missing.count, 1)
        XCTAssertFalse(missing[0].isAvailable)
        let replacement = root.appendingPathComponent("Relocated/transcript.md")
        try transcript(replacement)
        try await library.locate(id: entry.id, transcript: replacement)
        let restored = try await library.recordings()
        XCTAssertEqual(restored[0].id, entry.id)
        XCTAssertEqual(restored[0].transcriptURL.path, replacement.path)
        XCTAssertTrue(restored[0].isAvailable)
    }

    func testConcurrentLibraryInstancesMergeTheirWrites() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Library")
        let writers = [RecordingLibrary(directory: directory), RecordingLibrary(directory: directory)]
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                let url = root.appendingPathComponent("Meeting-\(i).md")
                try transcript(url)
                let writer = writers[i % 2]
                group.addTask { _ = try await writer.begin(transcript: url, audioDirectory: nil, modelID: "model", participants: []) }
            }
            try await group.waitForAll()
        }
        let recordings = try await RecordingLibrary(directory: directory).recordings()
        XCTAssertEqual(recordings.count, 20)
        XCTAssertEqual(Set(recordings.map(\.id)).count, 20)
    }

    func testCorruptIndexIsNotSilentlyOverwritten() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let index = root.appendingPathComponent("recordings.json")
        let original = Data("broken index".utf8)
        try original.write(to: index)
        let library = RecordingLibrary(directory: root)
        do {
            _ = try await library.begin(transcript: root.appendingPathComponent("Meeting.md"), audioDirectory: nil, modelID: "model", participants: [])
            XCTFail("Expected an index error")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: index), original)
    }

    func testFullAudioWritesPlayableSeparateChannels() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let audio = try RecordingAudio(directory: root, microphone: true, system: true)
        for _ in 0..<2 { try audio.append(microphone: [Float](repeating: 0.5, count: 16000), system: [Float](repeating: -0.25, count: 16000)) }
        audio.finish()
        for (name, expected): (String, Float) in [("microphone", 0.5), ("system", -0.25)] {
            let file = try AVAudioFile(forReading: root.appendingPathComponent(name + ".wav"))
            XCTAssertEqual(file.length, 32000)
            XCTAssertEqual(file.processingFormat.sampleRate, 16000)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 32000))
            try file.read(into: buffer)
            XCTAssertEqual(try XCTUnwrap(buffer.floatChannelData)[0][0], expected, accuracy: 0.001)
        }
        XCTAssertFalse(LivekeetConfig().saveAudio)
        XCTAssertTrue(try LivekeetConfig.parse("[output]\nsave_audio = true").saveAudio)
    }

    func testSavedTranscriptLinesPreserveUnicodeAndTimestamps() {
        let lines = TranscriptDocument(content: "# Header\n[10:00:01] **Iván**: Hola 👋\n").lines
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].timestamp, "10:00:01")
        XCTAssertEqual(lines[0].speaker, "Iván")
        XCTAssertEqual(lines[0].text, "Hola 👋")
    }
}
