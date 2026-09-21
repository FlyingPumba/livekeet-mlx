import XCTest
@testable import LivekeetCore

final class DiarizationTests: XCTestCase {
    func testDefaultAndLegacyEngineSelectionRemainDistinct() throws {
        XCTAssertEqual(LivekeetConfig().diarizationEngine, .sortformer)
        XCTAssertTrue(LivekeetConfig().diarizationEngine.isNativeStreaming)
        let legacy = try LivekeetConfig.parse("[defaults]\nengine = 'sortformer-v1'\ndiarize = true")
        XCTAssertEqual(legacy.diarizationEngine, .sortformerV1)
        XCTAssertFalse(legacy.diarizationEngine.isNativeStreaming)
        for engine in DiarizationEngine.allCases {
            let config = try LivekeetConfig.parse("[defaults]\nengine = '\(engine.rawValue)'\ndiarize = true")
            XCTAssertEqual(config.diarizationEngine, engine)
            XCTAssertFalse(config.disableDiarization)
        }
    }

    func testBatchAndLiveRouting() {
        XCTAssertTrue(DiarizationEngine.lsEEND.isNativeStreaming)
        XCTAssertFalse(DiarizationEngine.lsEEND.needsPython)
        for engine: DiarizationEngine in [.community1, .pyannote, .diarizen, .suplime, .suplimeLarge] {
            XCTAssertTrue(engine.needsPython)
            XCTAssertTrue(engine.isBatch)
        }
        XCTAssertFalse(DiarizationEngine.wespeaker.isBatch)
        XCTAssertFalse(DiarizationEngine.sortformerV1.needsPython)
    }

    /// Opt-in integration check: real model download and chunked inference on supplied speech.
    func testNativeStreamingSmoke() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let value = env["LIVEKEET_SMOKE_DIARIZER"], let engine = DiarizationEngine(rawValue: value),
              let path = env["LIVEKEET_DIARIZATION_PCM"] else {
            throw XCTSkip("Set LIVEKEET_SMOKE_DIARIZER and LIVEKEET_DIARIZATION_PCM for real local inference.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let diarizer = try await NativeStreamingDiarizer(engine: engine, microphone: true, system: true)
        for offset in stride(from: 0, to: samples.count, by: 8000) {
            try await diarizer.feed(Array(samples[offset..<min(offset + 8000, samples.count)]), channel: "mic")
        }
        try await diarizer.finish()
        let turns = await diarizer.turns(channel: "mic")
        let untouchedChannel = await diarizer.turns(channel: "system")
        XCTAssertFalse(turns.isEmpty, "Speech fixture must produce speaker turns")
        XCTAssertTrue(untouchedChannel.isEmpty, "Microphone audio must not contaminate system speaker state")
        for turn in turns {
            XCTAssertGreaterThanOrEqual(turn.start, 0)
            XCTAssertGreaterThan(turn.end, turn.start)
            XCTAssertLessThanOrEqual(turn.end, Float(samples.count) / 16000)
            XCTAssertTrue((0..<(engine == .lsEEND ? 10 : 4)).contains(turn.speaker))
        }
        try await diarizer.finish() // Repeated finalization must not duplicate the tail.
        let finished = await diarizer.turns(channel: "mic")
        XCTAssertEqual(finished.count, turns.count)
        print("DIARIZER_SMOKE \(engine.rawValue): \(turns.count) turns, \(Set(turns.map(\.speaker)).count) speakers")
    }
}
