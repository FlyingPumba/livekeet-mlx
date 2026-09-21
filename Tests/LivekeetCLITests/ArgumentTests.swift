import ArgumentParser
import XCTest
import LivekeetCore
@testable import livekeet

final class ArgumentTests: XCTestCase {
    func record(_ args: [String]) throws -> Record {
        let parsed = try Livekeet.parseAsRoot(args)
        return try XCTUnwrap(parsed as? Record)
    }

    func testPythonShortOptionsAndSpeakerNames() throws {
        let command = try record(["meeting.md", "-m", "-d", "USB", "-w", "Alice,Bob"])
        XCTAssertEqual(command.output, "meeting.md")
        XCTAssertTrue(command.micOnly)
        XCTAssertEqual(command.device, "USB")
        XCTAssertEqual(command.with, "Alice,Bob")
        XCTAssertEqual(command.resolvedConfig(LivekeetConfig()).otherNames, [])
    }

    func testCleanupAndDiarizationOverridesWin() throws {
        let command = try record(["--cleanup", "--no-cleanup", "--diarize", "--no-diarize", "--engine", "pyannote"])
        let config = command.resolvedConfig(LivekeetConfig(enableCorrection: true))
        XCTAssertFalse(config.enableCorrection)
        XCTAssertTrue(config.disableDiarization)
        XCTAssertEqual(config.diarizationEngine, .pyannote)
    }

    func testAutomaticDiarizationAndConfigPreservation() throws {
        let command = try record(["--with", " Alice, ,Bob ", "--multilingual"])
        let config = command.resolvedConfig(LivekeetConfig(defaultModel: "custom", disableDiarization: true, enableCorrection: true))
        XCTAssertEqual(config.otherNames, ["Alice", "Bob"])
        XCTAssertFalse(config.disableDiarization)
        XCTAssertTrue(config.enableCorrection)
        XCTAssertEqual(config.modelName, ModelCatalog.parakeetV3.id)
    }

    func testAllEngineChoicesEnableDiarization() throws {
        for engine in DiarizationEngine.allCases {
            let command = try record(["--engine", engine.rawValue])
            XCTAssertEqual(command.resolvedConfig(LivekeetConfig(disableDiarization: true)).diarizationEngine, engine)
            XCTAssertFalse(command.resolvedConfig(LivekeetConfig(disableDiarization: true)).disableDiarization)
        }
    }

    func testInvalidCombinationsFailBeforeRecording() {
        for args in [["--mic-only", "--system-only"], ["--system-only", "--device", "USB"], ["--engine", "missing"]] {
            XCTAssertThrowsError(try record(args))
        }
    }

    func testUtilityAliasesAndCommands() throws {
        XCTAssertTrue(try record(["--init"]).initialize)
        XCTAssertTrue(try record(["--devices"]).showDevices)
        XCTAssertTrue(try record(["--config"]).showConfig)
        XCTAssertTrue(try Livekeet.parseAsRoot(["init"]) is livekeet.Init)
        XCTAssertTrue(try Livekeet.parseAsRoot(["config"]) is Config)
        XCTAssertTrue(try Livekeet.parseAsRoot(["devices"]) is Devices)
        XCTAssertTrue(try Livekeet.parseAsRoot(["models"]) is Models)
        XCTAssertTrue(try Livekeet.parseAsRoot(["update", "--check"]) is Update)
        let relabel = try XCTUnwrap(try Livekeet.parseAsRoot(["relabel", "x.md", "--rename", "A=B", "--rename", "B=A"]) as? Relabel)
        XCTAssertEqual(relabel.renames, ["A=B", "B=A"])
    }
}
