import Foundation
import FluidAudio
import MLXAudioVAD

/// Keeps model state independent for microphone and system audio. All inference is
/// serialized on this actor; SwiftUI and the real-time audio callbacks never run it.
actor NativeStreamingDiarizer {
    private var channels: [String: any Diarizer] = [:]
    private var finalized = false
    private var sampleCounts: [String: Int] = [:]

    init(engine: DiarizationEngine, microphone: Bool, system: Bool) async throws {
        let names = (microphone ? ["mic"] : []) + (system ? ["system"] : [])
        switch engine {
        case .sortformer:
            let models = try await SortformerModels.loadFromHuggingFace(config: .balancedV2_1)
            for name in names {
                let diarizer = SortformerDiarizer(config: .balancedV2_1)
                diarizer.initialize(models: models)
                channels[name] = diarizer
            }
        case .lsEEND:
            let model = try await LSEENDModel.loadFromHuggingFace(variant: .dihard3)
            for name in names { channels[name] = try LSEENDDiarizer(model: model) }
        default:
            throw NativeError.unsupported
        }
    }

    func feed(_ samples: [Float], channel: String) throws {
        guard !finalized, !samples.isEmpty, let diarizer = channels[channel] else { return }
        _ = try diarizer.process(samples: samples, sourceSampleRate: 16_000)
        sampleCounts[channel, default: 0] += samples.count
    }

    func finish() throws {
        guard !finalized else { return }
        for diarizer in channels.values { try diarizer.finalizeSession() }
        finalized = true
    }

    func turns(channel: String) -> [MLXAudioVAD.DiarizationSegment] {
        guard let diarizer = channels[channel] else { return [] }
        let duration = Float(sampleCounts[channel, default: 0]) / 16_000
        var result: [MLXAudioVAD.DiarizationSegment] = []
        for speaker in diarizer.timeline.speakers.values {
            let segments = speaker.finalizedSegments + speaker.tentativeSegments
            for segment in segments {
                let start = max(0, segment.startTime)
                let end = min(duration, segment.endTime)
                if end > start {
                    result.append(MLXAudioVAD.DiarizationSegment(start: start, end: end, speaker: segment.speakerIndex))
                }
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.start == rhs.start { return lhs.speaker < rhs.speaker }
            return lhs.start < rhs.start
        }
    }

    enum NativeError: Error { case unsupported }
}
