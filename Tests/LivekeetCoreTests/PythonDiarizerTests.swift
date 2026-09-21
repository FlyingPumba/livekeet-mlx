import XCTest
@testable import LivekeetCore

final class PythonDiarizerTests: XCTestCase {
    func testPersistentHelperProtocolAndWAVHandoff() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("fake.py")
        try """
        import json, sys, wave
        print(json.dumps({"ok": True}), flush=True)
        for line in sys.stdin:
            request = json.loads(line)
            if request["op"] == "identify":
                with wave.open(request["path"]) as audio:
                    assert audio.getframerate() == 16000 and audio.getnframes() == 16000
                print(json.dumps({"speaker": 2}), flush=True)
            else:
                assert request["channels"]["mic"]["count"] == 123
                print(json.dumps({"channels": {"mic": [{"start": 0, "end": 2, "speaker": 1}]}}), flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        let helper = try PythonDiarizer(config: LivekeetConfig(pythonExecutable: "/usr/bin/python3"), scriptURL: script)
        try await helper.prepare()
        let speaker = try await helper.identify(samples: [Float](repeating: 0, count: 16000), channel: "mic")
        XCTAssertEqual(speaker, 2)
        let turns = try await helper.diarize(channels: ["mic": (script, 123)])
        XCTAssertEqual(turns["mic"]?.first?.speaker, 1)
        await helper.stop()
    }

    func testStartupFailurePreservesHelperDiagnostic() async throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".py")
        defer { try? FileManager.default.removeItem(at: script) }
        try "print('{\"error\": \"Install helper dependencies\"}', flush=True)".write(to: script, atomically: true, encoding: .utf8)
        let helper = try PythonDiarizer(config: LivekeetConfig(pythonExecutable: "/usr/bin/python3"), scriptURL: script)
        do {
            try await helper.prepare()
            XCTFail("Expected an actionable startup error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Install helper dependencies"))
        }
        await helper.stop()
    }
}
