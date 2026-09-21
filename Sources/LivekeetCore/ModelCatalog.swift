import Foundation

public struct SpeechLanguage: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
}

public struct SpeechModelDescriptor: Sendable, Identifiable, Hashable {
    public enum Backend: String, Sendable, Hashable {
        case parakeet, qwen3ASR, voxtralRealtime, cohere, granite, canary, whisper
        case moonshinePython, voxtralPython

        public var needsPython: Bool { self == .moonshinePython || self == .voxtralPython }
    }

    public let id: String
    public let displayName: String
    public let subtitle: String
    public let sizeDescription: String
    public let backend: Backend
    public let release: String
    public let strengths: String
    public let tradeoffs: String
    public let benchmark: String
    public let source: URL
    public var languageCodes: [String] = []
    public var requiresLanguage = false

    public var languages: [SpeechLanguage] {
        languageCodes.map { SpeechLanguage(id: $0, name: Locale(identifier: "en").localizedString(forLanguageCode: $0) ?? $0) }
            .sorted { $0.name < $1.name }
    }
}

public enum ModelCatalog {
    public static let benchmarkExplanation = "WER is word error rate; lower is better. Scores shown are published results for the original models, not measurements of these local builds. Different languages, datasets and test settings are not directly comparable."
    private static let cohereLanguages = ["en", "es", "fr", "de", "it", "pt", "el", "nl", "pl", "zh", "ja", "ko", "vi", "ar"]
    private static let europeanLanguages = ["bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk"]

    public static let parakeetV2 = SpeechModelDescriptor(
        id: "mlx-community/parakeet-tdt-0.6b-v2", displayName: "Parakeet TDT 0.6B v2",
        subtitle: "English", sizeDescription: "0.6B parameters", backend: .parakeet,
        release: "1 May 2025",
        strengths: "Fast English transcription with punctuation and word timestamps. A compact choice for English meetings.",
        tradeoffs: "English only. Choose v3 or another multilingual model for Spanish.",
        benchmark: "6.05% WER · English Open ASR leaderboard average (NVIDIA).",
        source: URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2")!)

    public static let parakeetV3 = SpeechModelDescriptor(
        id: "mlx-community/parakeet-tdt-0.6b-v3", displayName: "Parakeet TDT 0.6B v3",
        subtitle: "25 languages, including Spanish", sizeDescription: "0.6B parameters", backend: .parakeet,
        release: "14 August 2025",
        strengths: "Compact multilingual transcription with punctuation and timestamps. A useful starting point for Spanish and European languages.",
        tradeoffs: "Language support does not guarantee accurate switching between languages within a sentence.",
        benchmark: "3.45% WER · Spanish FLEURS; 6.34% · English Open ASR average (NVIDIA).",
        source: URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3")!)

    public static let qwen3ASR = qwen(size: "1.7", bits: 4)
    public static let qwen3ASR8bit = qwen(size: "1.7", bits: 8)
    public static let qwen3Small = qwen(size: "0.6", bits: 4)

    private static func qwen(size: String, bits: Int) -> SpeechModelDescriptor {
        SpeechModelDescriptor(
            id: "mlx-community/Qwen3-ASR-\(size)B-\(bits)bit", displayName: "Qwen3-ASR \(size)B (\(bits)-bit)",
            subtitle: "30 languages, including Spanish", sizeDescription: "\(size)B · \(bits)-bit weights", backend: .qwen3ASR,
            release: "January 2026",
            strengths: size == "1.7" ? "An accuracy-focused multilingual alternative with automatic language identification and robust speech recognition." : "A smaller multilingual alternative when memory use matters more than maximum recognition accuracy.",
            tradeoffs: "\(bits == 4 ? "Lower-memory quantization can affect accuracy." : "Uses more memory than the 4-bit version.") Whisper still wins on some language sets; test your accents and mixed-language speech.",
            benchmark: "\(size == "1.7" ? "4.90" : "7.57")% WER · 12-language FLEURS average (Qwen); not a Spanish-only score.",
            source: URL(string: "https://huggingface.co/Qwen/Qwen3-ASR-\(size)B")!)
    }

    public static let voxtral = SpeechModelDescriptor(
        id: "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit", displayName: "Voxtral Realtime 4B (4-bit)",
        subtitle: "13 languages, including Spanish", sizeDescription: "4B · 4-bit weights", backend: .voxtralRealtime,
        release: "4 February 2026",
        strengths: "Designed for low-latency transcription. Interesting for multilingual captions and spoken conversations.",
        tradeoffs: "Larger than Parakeet. Livekeet currently transcribes completed speech segments; the published streaming delay is not the app's latency.",
        benchmark: "3.31% WER · Spanish FLEURS at 480 ms model delay; 2.71% at 2.4 s (Mistral).",
        source: URL(string: "https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602")!)

    public static let cohere = SpeechModelDescriptor(
        id: "beshkenadze/cohere-transcribe-03-2026-mlx-fp16", displayName: "Cohere Transcribe 2B",
        subtitle: "14 languages; choose a language", sizeDescription: "2B · FP16 weights", backend: .cohere,
        release: "26 March 2026",
        strengths: "Strong recognition for meetings in a known language, including Spanish. A dedicated transcription model with a small decoder.",
        tradeoffs: "Requires an explicit language. Mixed-language speech can be inconsistent. No built-in word timestamps or speaker identification.",
        benchmark: "5.42% WER · English Open ASR average, 26 March 2026 (Cohere); not a Spanish score.",
        source: URL(string: "https://huggingface.co/CohereLabs/cohere-transcribe-03-2026")!,
        languageCodes: cohereLanguages, requiresLanguage: true)

    public static let granite = SpeechModelDescriptor(
        id: "mlx-community/granite-4.0-1b-speech-5bit", displayName: "Granite Speech 4.0 1B (5-bit)",
        subtitle: "6 input languages, including Spanish", sizeDescription: "1B · 5-bit weights", backend: .granite,
        release: "6 March 2026",
        strengths: "Compact multilingual speech recognition. The model also supports keyword hints and translation, making it interesting for names and technical vocabulary.",
        tradeoffs: "Livekeet uses transcription mode; keyword hints and translation are not exposed. English benchmarks do not establish Spanish superiority.",
        benchmark: "5.52% WER · English Open ASR leaderboard average (IBM).",
        source: URL(string: "https://huggingface.co/ibm-granite/granite-4.0-1b-speech")!)

    public static let canary = SpeechModelDescriptor(
        id: "Mediform/canary-1b-v2-mlx-q8", displayName: "Canary 1B v2 (8-bit)",
        subtitle: "25 languages; choose a language", sizeDescription: "1B · 8-bit weights", backend: .canary,
        release: "14 August 2025",
        strengths: "Multilingual transcription with a compact encoder-decoder design. An alternative for Spanish and other European languages.",
        tradeoffs: "Requires an explicit language. The model also supports translation, but Livekeet preserves the spoken language.",
        benchmark: "8.40% WER · 25-language FLEURS average (NVIDIA); not a Spanish-only score.",
        source: URL(string: "https://huggingface.co/nvidia/canary-1b-v2")!,
        languageCodes: europeanLanguages, requiresLanguage: true)

    public static let moonshine = SpeechModelDescriptor(
        id: "moonshine-ai/moonshine-streaming-small-es", displayName: "Moonshine Streaming Small — Spanish",
        subtitle: "Spanish only · Python helper", sizeDescription: "113M parameters", backend: .moonshinePython,
        release: "24 August 2026 checkpoint",
        strengths: "Very small Spanish model designed for on-device streaming. Interesting when memory use and responsiveness matter.",
        tradeoffs: "Uses the optional Python speech helper and completed speech segments. Limited conversational and dialect evaluation; short/noisy clips may repeat text.",
        benchmark: "4.89% WER · Spanish FLEURS sampled evaluation of the converted checkpoint (Moonshine); not the full test set.",
        source: URL(string: "https://huggingface.co/moonshine-ai/moonshine-streaming-small-es")!)

    public static let whisper = SpeechModelDescriptor(
        id: "mlx-community/whisper-large-v3-fp16", displayName: "Whisper large-v3",
        subtitle: "Broad multilingual coverage", sizeDescription: "1.55B · FP16 weights", backend: .whisper,
        release: "November 2023",
        strengths: "Established multilingual recognition with automatic language detection. A useful baseline for Spanish and less widely supported languages.",
        tradeoffs: "Heavier than Turbo and can invent text during silence. Livekeet segments audio before transcription.",
        benchmark: "7.44% WER · English Open ASR average in Cohere's March 2026 comparison.",
        source: URL(string: "https://huggingface.co/CohereLabs/cohere-transcribe-03-2026#results")!)

    public static let whisperTurbo = SpeechModelDescriptor(
        id: "mlx-community/whisper-large-v3-turbo", displayName: "Whisper large-v3 Turbo",
        subtitle: "Broad multilingual coverage", sizeDescription: "809M · FP16 weights", backend: .whisper,
        release: "September 2024",
        strengths: "A reduced decoder makes Whisper faster and lighter, with broad language coverage including Spanish.",
        tradeoffs: "Some accuracy loss versus large-v3 varies by language. Intended for transcription, not speech translation.",
        benchmark: "WER: no single comparable score published in the model card. Accuracy varies by language.",
        source: URL(string: "https://huggingface.co/openai/whisper-large-v3-turbo")!)

    public static let voxtralLegacy = SpeechModelDescriptor(
        id: "mistralai/Voxtral-Mini-3B-2507", displayName: "Voxtral Mini 3B (2025)",
        subtitle: "Multilingual · Python helper", sizeDescription: "3B decoder plus audio encoder", backend: .voxtralPython,
        release: "15 July 2025",
        strengths: "The original Voxtral audio model supports Spanish and automatic language detection. Retained for comparison with the newer Realtime model.",
        tradeoffs: "Requires the optional Python speech helper and substantially more memory than the quantized Realtime choice. Livekeet uses transcription only.",
        benchmark: "7.05% WER · English Open ASR leaderboard result linked from the Mistral model card.",
        source: URL(string: "https://huggingface.co/mistralai/Voxtral-Mini-3B-2507")!)

    public static let availableModels: [SpeechModelDescriptor] = [
        parakeetV2, parakeetV3, qwen3Small, qwen3ASR, qwen3ASR8bit, voxtral,
        cohere, granite, canary, moonshine, whisper, whisperTurbo, voxtralLegacy,
    ]

    public static func canonicalID(for id: String) -> String {
        switch id {
        case "mlx-community/whisper-large-v3-mlx": whisper.id
        case "mlx-community/Qwen3-ASR-Flash-MLX-4bit": qwen3ASR.id
        case "mlx-community/Voxtral-Mini-3B-2507-4bit": voxtralLegacy.id
        default: id
        }
    }

    public static func descriptor(for modelId: String) -> SpeechModelDescriptor? {
        availableModels.first { $0.id == canonicalID(for: modelId) }
    }

    public static func backend(for modelId: String) throws -> SpeechModelDescriptor.Backend {
        if let known = descriptor(for: modelId) { return known.backend }
        let name = modelId.lowercased()
        if name.contains("parakeet") { return .parakeet }
        if name.contains("qwen3-asr") { return .qwen3ASR }
        if name.contains("voxtral") && name.contains("realtime") { return .voxtralRealtime }
        if name.contains("voxtral-mini-3b") { return .voxtralPython }
        if name.contains("cohere-transcribe") { return .cohere }
        if name.contains("granite") && name.contains("speech") { return .granite }
        if name.contains("canary") { return .canary }
        if name.contains("whisper") { return .whisper }
        if name.contains("moonshine-streaming") { return .moonshinePython }
        throw ModelError.unsupported(modelId)
    }

    public static func validateLanguage(_ language: String?, modelID: String) throws {
        let backend = try backend(for: modelID)
        guard backend == .cohere || backend == .canary else { return }
        let options = backend == .cohere ? cohereLanguages : europeanLanguages
        guard let language, options.contains(language) else { throw ModelError.languageRequired }
    }

    public enum ModelError: LocalizedError {
        case unsupported(String), languageRequired, pythonRequired
        public var errorDescription: String? {
            switch self {
            case .unsupported(let id): "Unsupported speech model: \(id). Choose a model from Settings or livekeet models."
            case .languageRequired: "Choose the transcription language for Cohere or Canary in Settings, or pass --language (for example es or en)."
            case .pythonRequired: "This speech model requires the optional Python speech helper. Run scripts/setup-python.sh speech, then select its Python executable in Advanced settings."
            }
        }
    }
}
