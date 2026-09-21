import Foundation
import MLXAudioSTT

/// Explicit architecture routing; unknown models never silently fall back to Parakeet.
enum SpeechModelLoader {
    static func load(name: String) async throws -> any STTGenerationModel {
        let id = ModelCatalog.canonicalID(for: name)
        switch try ModelCatalog.backend(for: id) {
        case .parakeet: return try await ParakeetModel.fromPretrained(id)
        case .qwen3ASR: return try await Qwen3ASRModel.fromPretrained(id)
        case .voxtralRealtime: return try await VoxtralRealtimeModel.fromPretrained(id)
        case .cohere: return try await CohereTranscribeModel.fromPretrained(id)
        case .granite: return try await GraniteSpeechModel.fromPretrained(id)
        case .canary: return try await CanaryModel.fromPretrained(id)
        case .whisper: return try await WhisperModel.fromPretrained(id)
        case .moonshinePython, .voxtralPython: throw ModelCatalog.ModelError.pythonRequired
        }
    }

    static func parameters(for model: any STTGenerationModel, modelID: String, language: String?) -> STTGenerateParameters {
        let defaults = model.defaultGenerationParameters
        let backend = try? ModelCatalog.backend(for: modelID)
        // Granite's language argument requests translation, so never pass an input-language hint to it.
        guard backend == .cohere || backend == .canary else { return defaults }
        return STTGenerateParameters(
            maxTokens: defaults.maxTokens, temperature: defaults.temperature,
            topP: defaults.topP, topK: defaults.topK, verbose: defaults.verbose,
            language: language, chunkDuration: defaults.chunkDuration,
            minChunkDuration: defaults.minChunkDuration
        )
    }
}
