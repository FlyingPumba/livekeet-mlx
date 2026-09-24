import MLXAudioVAD
import XCTest
@testable import LivekeetCore

final class SpeakerAssignmentTests: XCTestCase {
    func testMissingFinalTurnsPreserveEarlierSpeakerInsteadOfDefaultingToMe() {
        XCTAssertEqual(SpeakerAssignment.resolve(offsetSeconds: 25, turns: [], fallback: 2), 2)
        let unrelated = [DiarizationSegment(start: 0, end: 5, speaker: 0)]
        XCTAssertEqual(SpeakerAssignment.resolve(offsetSeconds: 25, turns: unrelated, fallback: 2), 2)
        XCTAssertEqual(SpeakerAssignment.resolve(offsetSeconds: 25, turns: unrelated, fallback: 6), 6)
    }

    func testMatchingTurnCanStillCorrectAnEarlierLabel() {
        let turns = [DiarizationSegment(start: 5, end: 10, speaker: 1)]
        XCTAssertEqual(SpeakerAssignment.resolve(offsetSeconds: 7, turns: turns, fallback: 0), 1)
    }

    func testNearEdgeOfLongTurnUsesTheTurnRatherThanItsDistantMidpoint() {
        let turns = [DiarizationSegment(start: 5, end: 25, speaker: 2)]
        XCTAssertEqual(SpeakerAssignment.resolve(offsetSeconds: 4.5, turns: turns, fallback: 0), 2)
        XCTAssertEqual(SpeakerAssignment.resolve(offsetSeconds: 25.5, turns: turns, fallback: 0), 2)
        XCTAssertEqual(SpeakerAssignment.resolve(offsetSeconds: 28, turns: turns, fallback: 3), 3)
    }

    func testExactHandoffUsesTheIncomingSpeaker() {
        let turns = [DiarizationSegment(start: 0, end: 10, speaker: 0),
                     DiarizationSegment(start: 10, end: 20, speaker: 1)]
        XCTAssertEqual(SpeakerAssignment.resolve(offsetSeconds: 10, turns: turns, fallback: 0), 1)
    }

    func testOverlappingVoicesKeepTheExistingSpeakerWhenBothArePlausible() {
        let turns = [DiarizationSegment(start: 0, end: 10, speaker: 0),
                     DiarizationSegment(start: 5, end: 15, speaker: 2)]
        XCTAssertEqual(SpeakerAssignment.resolve(offsetSeconds: 7, turns: turns, fallback: 2), 2)
    }

    func testEqualDistanceToTwoTurnsKeepsTheExistingSpeaker() {
        let turns = [DiarizationSegment(start: 0, end: 10, speaker: 0),
                     DiarizationSegment(start: 12, end: 15, speaker: 2)]
        XCTAssertEqual(SpeakerAssignment.resolve(offsetSeconds: 11, turns: turns, fallback: 2), 2)
        XCTAssertEqual(SpeakerAssignment.resolve(offsetSeconds: 11, turns: turns.reversed(), fallback: 2), 2)
    }
}
