import XCTest
@testable import LivekeetCore

final class CLICompatibilityTests: XCTestCase {
    func testPythonConfigurationLoadsAllControls() throws {
        let config = try LivekeetConfig.parse("""
        [output]
        filename = "{datetime}-{names}.md"
        [speaker]
        name = "Ivan"
        [defaults]
        diarize = true
        engine = "pyannote"
        device = "USB"
        [cleanup]
        enabled = true
        model = "custom-model"
        timeout_s = 6
        system_prompt = "Keep names intact"
        [cleanup.corrections]
        "chat gbt" = "ChatGPT"
        [python]
        executable = "/tmp/venv/bin/python"
        [pyannote]
        token = "test-token"
        """)
        XCTAssertFalse(config.disableDiarization)
        XCTAssertEqual(config.diarizationEngine, .pyannote)
        XCTAssertEqual(config.inputDevice, "USB")
        XCTAssertTrue(config.enableCorrection)
        XCTAssertEqual(config.correctionTimeout, 6)
        XCTAssertEqual(config.correctionModel, "custom-model")
        XCTAssertTrue(config.correctionSystemPrompt.contains("Keep names intact"))
        XCTAssertEqual(config.corrections, ["chat gbt": "ChatGPT"])
        XCTAssertEqual(config.pythonExecutable, "/tmp/venv/bin/python")
        XCTAssertEqual(config.pyannoteToken, "test-token")
    }

    func testInvalidConfigurationFailsClearly() {
        XCTAssertThrowsError(try LivekeetConfig.parse("[defaults]\nengine = 'unknown'"))
        XCTAssertThrowsError(try LivekeetConfig.parse("[cleanup]\ntimeout_s = -1"))
        XCTAssertThrowsError(try LivekeetConfig.parse("[cleanup]\ntimeout_s = nan"))
    }

    func testDefaultConfigRoundTripsAndKeepsCleanupOptIn() throws {
        let config = try LivekeetConfig.parse(LivekeetConfig.defaultConfigContent)
        XCTAssertFalse(config.enableCorrection)
        XCTAssertTrue(config.disableDiarization)
        XCTAssertEqual(config.diarizationEngine, .sortformer)
    }

    func testSpeakerSwapDoesNotChangeQuotesOrMetadata() throws {
        let original = "# **Alice**\n[12:00:01] **Alice**: Ask **Bob**.\n[12:00:02] **Bob**: Hi 👋\n---\n"
        let doc = TranscriptDocument(content: original)
        XCTAssertEqual(doc.speakers, ["Alice", "Bob"])
        XCTAssertEqual(doc.quotes(for: "Alice"), ["Ask **Bob**."])
        XCTAssertEqual(try doc.renaming(["Alice": "Bob", "Bob": "Alice"]),
                       "# **Alice**\n[12:00:01] **Bob**: Ask **Bob**.\n[12:00:02] **Alice**: Hi 👋\n---\n")
        XCTAssertThrowsError(try doc.renaming(["Alice": "bad\nname"]))
    }

    func testFilenameNamesAreSafeAndEmptyNamesDoNotLeaveDashes() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(expandPattern("meeting-{names}.md", date: date, names: ["A/B", "C\\D"]), "meeting-A_B-C_D.md")
        XCTAssertEqual(expandPattern("meeting-{names}.md", date: date), "meeting.md")
        let config = LivekeetConfig(filenamePattern: "{names}.md", otherNames: ["Alice"])
        XCTAssertTrue(resolveOutputPath(arg: "/tmp/new-livekeet-folder/", config: config).path.hasSuffix("new-livekeet-folder/Alice.md"))
    }

    func testCorrectionsUseLiteralReplacementsAndWordBoundaries() {
        XCTAssertEqual(DeterministicCorrections.apply("CHAT GBT vs chat and chatter", replacements: ["chat gbt": "ChatGPT", "chat": "$1"]), "ChatGPT vs $1 and chatter")
    }
}
