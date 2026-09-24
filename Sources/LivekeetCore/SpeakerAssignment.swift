import MLXAudioVAD

/// Matches transcript timestamps to speaker turns without treating missing
/// diarization evidence as evidence for speaker zero.
enum SpeakerAssignment {
    static func resolve(offsetSeconds: Float, turns: [DiarizationSegment], fallback: Int) -> Int {
        let containing = turns.filter { offsetSeconds >= $0.start && offsetSeconds < $0.end }
        if let turn = containing.first(where: { $0.speaker == fallback }) ?? containing.first {
            return turn.speaker
        }

        // Sentence starts can fall just outside a detected speech turn. Measure
        // from its nearest edge; a long turn's midpoint may be many seconds away.
        var bestDistance: Float = 2
        var bestSpeaker: Int?
        for turn in turns where turn.end > turn.start {
            let distance = max(turn.start - offsetSeconds, offsetSeconds - turn.end, 0)
            if distance < bestDistance {
                bestDistance = distance
                bestSpeaker = turn.speaker
            } else if distance == bestDistance, bestSpeaker != nil, turn.speaker == fallback {
                bestSpeaker = fallback
            }
        }
        // Periodic/final passes can have gaps or no turns for a channel. Preserve
        // its earlier assignment instead of rewriting it as "Me" / "Other".
        return bestSpeaker ?? fallback
    }
}
