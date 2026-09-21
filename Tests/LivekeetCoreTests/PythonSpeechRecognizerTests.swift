import XCTest
@testable import LivekeetCore

final class PythonSpeechRecognizerTests: XCTestCase {
    func testPersistentSpeechProtocolAndTemporaryAudioCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("speech.py")
        try """
        import json, sys, wave
        print(json.dumps({"ok": True}), flush=True)
        for line in sys.stdin:
            request = json.loads(line)
            assert request['op'] == 'transcribe'
            with wave.open(request['path']) as audio:
                assert audio.getframerate() == 16000 and audio.getnframes() == 16000
            print(json.dumps({'text': request['path']}), flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        let helper = try PythonSpeechRecognizer(modelID: ModelCatalog.moonshine.id, python: "/usr/bin/python3", scriptURL: script)
        try await helper.prepare()
        for _ in 0..<2 {
            let path = try await helper.transcribe(samples: [Float](repeating: 0, count: 16000))
            XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        }
        await helper.stop()
    }

    func testHelperStartupDiagnosticIsPreserved() async throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".py")
        defer { try? FileManager.default.removeItem(at: script) }
        try "print('{\"error\": \"Install speech dependencies\"}', flush=True)".write(to: script, atomically: true, encoding: .utf8)
        let helper = try PythonSpeechRecognizer(modelID: "test", python: "/usr/bin/python3", scriptURL: script)
        do {
            try await helper.prepare()
            XCTFail("Expected a setup error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Install speech dependencies")) }
        await helper.stop()
    }
}
