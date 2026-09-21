import XCTest
import MLX
import MLXAudioCore
import MLXAudioSTT
@testable import LivekeetCore

final class SpeechModelTests: XCTestCase {
    func testLegacyModelIDsResolveToTheCorrectArchitecture() throws {
        XCTAssertEqual(ModelCatalog.canonicalID(for: "mlx-community/Qwen3-ASR-Flash-MLX-4bit"), ModelCatalog.qwen3ASR.id)
        XCTAssertEqual(try ModelCatalog.backend(for: "mlx-community/Voxtral-Mini-3B-2507-4bit"), .voxtralPython)
        XCTAssertEqual(try ModelCatalog.backend(for: ModelCatalog.voxtral.id), .voxtralRealtime)
        XCTAssertEqual(LivekeetConfig(defaultModel: "mlx-community/Qwen3-ASR-Flash-MLX-4bit").modelName, ModelCatalog.qwen3ASR.id)
    }

    func testUnknownModelsNeverFallBackToParakeet() {
        XCTAssertThrowsError(try ModelCatalog.backend(for: "acme/unknown-model"))
        XCTAssertThrowsError(try ModelCatalog.validateLanguage(nil, modelID: "acme/unknown-model"))
    }

    func testExplicitLanguageRequiredOnlyForConditionedModels() throws {
        for descriptor in [ModelCatalog.cohere, ModelCatalog.canary] {
            XCTAssertThrowsError(try ModelCatalog.validateLanguage(nil, modelID: descriptor.id))
            XCTAssertThrowsError(try ModelCatalog.validateLanguage("xx", modelID: descriptor.id))
            XCTAssertNoThrow(try ModelCatalog.validateLanguage("es", modelID: descriptor.id))
        }
        for descriptor in ModelCatalog.availableModels where !descriptor.requiresLanguage {
            XCTAssertNoThrow(try ModelCatalog.validateLanguage(nil, modelID: descriptor.id))
        }
        let config = try LivekeetConfig.parse("[defaults]\nmodel = 'Mediform/canary-1b-v2-mlx-q8'\nlanguage = 'es'")
        XCTAssertEqual(config.speechLanguage, "es")
    }

    func testInputLanguageDoesNotAccidentallyRequestGraniteTranslation() {
        let model = FakeSpeechModel()
        for descriptor in [ModelCatalog.cohere, ModelCatalog.canary] {
            let parameters = SpeechModelLoader.parameters(for: model, modelID: descriptor.id, language: "es")
            XCTAssertEqual(parameters.language, "es")
            XCTAssertEqual(parameters.maxTokens, 200)
        }
        XCTAssertNil(SpeechModelLoader.parameters(for: model, modelID: ModelCatalog.granite.id, language: "es").language)
    }

    /// Explicit opt-in: downloads the chosen checkpoint and exercises real local inference.
    func testSelectedModelSmoke() async throws {
        guard let id = ProcessInfo.processInfo.environment["LIVEKEET_SMOKE_MODEL"] else {
            throw XCTSkip("Set LIVEKEET_SMOKE_MODEL to exercise a real checkpoint.")
        }
        let samples: [Float]
        if let path = ProcessInfo.processInfo.environment["LIVEKEET_SMOKE_WAV"] {
            let (_, audio) = try loadAudioArray(from: URL(fileURLWithPath: path), sampleRate: 16000)
            samples = audio.asArray(Float.self)
        } else { samples = [Float](repeating: 0, count: 16000) }
        let text: String
        if try ModelCatalog.backend(for: id).needsPython {
            let helper = try PythonSpeechRecognizer(modelID: id, python: ProcessInfo.processInfo.environment["LIVEKEET_SMOKE_PYTHON"] ?? "python3")
            do {
                try await helper.prepare()
                text = try await helper.transcribe(samples: samples)
                await helper.stop()
            } catch { await helper.stop(); throw error }
        } else {
            let model = try await SpeechModelLoader.load(name: id)
            let parameters = SpeechModelLoader.parameters(for: model, modelID: id, language: "es")
            text = model.generate(audio: MLXArray(samples), generationParameters: parameters).text
        }
        print("MODEL_SMOKE \(id): \(text)")
        if ProcessInfo.processInfo.environment["LIVEKEET_SMOKE_WAV"] != nil {
            XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private final class FakeSpeechModel: STTGenerationModel {
    var defaultGenerationParameters: STTGenerateParameters { STTGenerateParameters(maxTokens: 200) }
    func generate(audio: MLXArray, generationParameters: STTGenerateParameters) -> STTOutput { STTOutput(text: "") }
    func generateStream(audio: MLXArray, generationParameters: STTGenerateParameters) -> AsyncThrowingStream<STTGeneration, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
