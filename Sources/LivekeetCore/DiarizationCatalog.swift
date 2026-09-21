import Foundation

public enum DiarizationEngine: String, CaseIterable, Sendable, Identifiable {
    // Keep the existing CLI spelling; it now selects the current default checkpoint.
    case sortformer
    case community1 = "community-1"
    case lsEEND = "ls-eend"
    case diarizen
    case suplime
    case suplimeLarge = "suplime-large"
    case sortformerV1 = "sortformer-v1"
    case pyannote
    case wespeaker

    public var id: String { rawValue }
    public var isNativeStreaming: Bool { self == .sortformer || self == .lsEEND }
    public var needsPython: Bool { !isNativeStreaming && self != .sortformerV1 }
    public var isBatch: Bool { needsPython && self != .wespeaker }
    public var descriptor: DiarizationDescriptor { DiarizationCatalog.descriptor(for: self) }
}

public struct DiarizationDescriptor: Sendable, Identifiable {
    public let engine: DiarizationEngine
    public var id: String { engine.rawValue }
    public let displayName: String
    public let release: String
    public let subtitle: String
    public let strengths: String
    public let tradeoffs: String
    public let benchmark: String
    public let requirements: String
    public let source: URL
}

public enum DiarizationCatalog {
    public static let benchmarkExplanation = "DER is diarization error rate: missed speech, false speech detections and time assigned to the wrong speaker. Lower is better. These are published results, not measurements of Livekeet. Compare scores only with the same dataset, speaker counts, overlap rules and boundary tolerance (collar). DER measures speaker labels; WER measures transcription words."
    public static let models: [DiarizationDescriptor] = DiarizationEngine.allCases.map(descriptor)

    public static func descriptor(for engine: DiarizationEngine) -> DiarizationDescriptor {
        func model(_ name: String, _ release: String, _ subtitle: String, _ strengths: String,
                   _ tradeoffs: String, _ benchmark: String, _ requirements: String, _ url: String) -> DiarizationDescriptor {
            DiarizationDescriptor(engine: engine, displayName: name, release: release, subtitle: subtitle,
                strengths: strengths, tradeoffs: tradeoffs, benchmark: benchmark, requirements: requirements,
                source: URL(string: url)!)
        }
        switch engine {
        case .sortformer:
            return model("Streaming Sortformer v2.1 · Default", "October 2025 checkpoint",
                "Live · Native Core ML · Up to 4 speakers per channel",
                "Recommended for live meetings on this Mac. Maintains speaker identities as audio arrives and handles overlapping voices. Runs on Apple Silicon without Python.",
                "Limited to four speakers on each microphone/system channel. Primarily English training; Spanish and mixed-language quality varies. The 1.04 s input buffer excludes computation and transcription delay.",
                "20.57% DER · AMI-SDM, 1.04 s input buffer, overlap included, 0 s collar (NVIDIA). Streaming v2 scored 31.34% under the same conditions. NVIDIA uses its own reference annotations.",
                "Downloads a Core ML conversion on first use. NVIDIA Open Model License.",
                "https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2.1")
        case .community1:
            return model("pyannote Community-1", "September 2025",
                "Batch · Python · Flexible speaker count",
                "Updated speaker counting and whole-meeting clustering. Useful for larger meetings and for comparing final labels with the live engines. Exclusive speaker output helps align labels with transcript timestamps.",
                "Labels refresh periodically and after recording. Local CPU processing may take time; it does not consistently beat Sortformer on every language or recording.",
                "19.9% DER · AMI-SDM; 20.2% · DIHARD 3 full. Overlap included, 0 s collar (pyannote). Legacy 3.1 scored 22.7% and 21.4% respectively.",
                "Optional Python support and Hugging Face model access/token required. Runs locally after download. CC BY 4.0.",
                "https://huggingface.co/pyannote/speaker-diarization-community-1")
        case .lsEEND:
            return model("LS-EEND · DIHARD III", "October 2024 paper · later Core ML conversion",
                "Live · Native Core ML · Up to 10 speaker slots",
                "A lightweight streaming alternative for larger groups and overlapping conversations. Uses the broad DIHARD III variant, with ten speaker slots in the Core ML conversion.",
                "More prone to false speech detections and identity instability than Sortformer in some conditions. Internally uses 8 kHz audio; long-form research evaluated recordings up to about one hour.",
                "19.61% DER · DIHARD III, published LS-EEND result. This is the original research system’s score, not a measurement of the Core ML conversion.",
                "Downloads a Core ML model on first use; no Python required.",
                "https://arxiv.org/abs/2410.06670")
        case .diarizen:
            return model("DiariZen Large-s80-v2", "December 2025 checkpoint",
                "Batch · Python · Up to 20 speakers in this pipeline",
                "Accuracy-focused whole-recording analysis, especially for distant microphones and difficult conversations. A pruned WavLM encoder reduces the cost of the original large model.",
                "Uses an isolated Python environment and local CPU inference. Can be slow for long meetings. Supports up to four overlapping voices, which differs from the total speaker count.",
                "13.9% DER · AMI-SDM; 14.5% · DIHARD 3 full, 0 s collar (DiariZen). The authors’ pyannote 3.1 baseline scored 22.4% and 21.7%.",
                "Optional Python support. Model weights are CC BY-NC 4.0 (noncommercial).",
                "https://huggingface.co/BUT-FIT/diarizen-wavlm-large-s80-md-v2")
        case .suplime, .suplimeLarge:
            let large = engine == .suplimeLarge
            return model(large ? "SUPlime-L" : "SUPlime", "September 2026 checkpoint",
                "Batch · Python · Flexible speaker count",
                large ? "Larger WavLM backbone aimed at accuracy on meetings and conversations. Interesting when final speaker labels matter more than processing speed."
                      : "Smaller WavLM pipeline with strong published results, including distant microphones and informal group conversations. Cheaper than SUPlime-L.",
                large ? "349M-parameter segmentation backbone; substantially more CPU work than the base model. The larger variant does not win on every recording type."
                      : "114M-parameter segmentation backbone. A recent model with limited independent validation; local CPU processing can be slow.",
                large ? "15.86% macro-average DER · 8 corpora; 21.02% · 12 corpora. Overlap included, 0 s collar, automatic speaker counts (SUPlime authors)."
                      : "16.21% macro-average DER · 8 corpora; 20.94% · 12 corpora. Overlap included, 0 s collar, automatic speaker counts (SUPlime authors).",
                "Optional Python support; no gated model token required. Model weights are CC BY-NC 4.0 (noncommercial).",
                large ? "https://huggingface.co/rewayai/suplime-large" : "https://huggingface.co/rewayai/suplime")
        case .sortformerV1:
            return model("Sortformer v1 · Legacy", "December 2024 checkpoint",
                "Native MLX · Up to 4 speakers per channel",
                "The original Livekeet speaker model, retained for comparison and existing workflows.",
                "Originally trained for offline audio; Livekeet feeds it in chunks. Streaming v2.1 is the recommended live option. Primarily English training and a four-speaker limit.",
                "16.28% DER · DIHARD 3 subset with at most 4 speakers, 0 s collar (NVIDIA). This is not comparable to full DIHARD results that include larger groups.",
                "Downloads MLX weights on first use. Model weights are CC BY-NC 4.0 (noncommercial).",
                "https://huggingface.co/nvidia/diar_sortformer_4spk-v1")
        case .pyannote:
            return model("pyannote 3.1 · Legacy", "November 2023",
                "Batch · Python · Flexible speaker count",
                "Established segmentation, voice embeddings and clustering pipeline. Retained as a baseline for older recordings and comparisons.",
                "Community-1 improves most published benchmarks. This helper uses local CPU processing and refreshes labels periodically and after recording.",
                "22.7% DER · AMI-SDM; 21.4% · DIHARD 3 full. Fully automatic, overlap included, 0 s collar (pyannote).",
                "Optional Python support; accept speaker-diarization-3.1 and segmentation-3.0 access conditions and provide a Hugging Face token.",
                "https://huggingface.co/pyannote/speaker-diarization-community-1#benchmark")
        case .wespeaker:
            return model("WeSpeaker ResNet34 · Legacy", "2023 toolkit · January 2026 MLX conversion",
                "Live chunk matching · Python/MLX · Up to 5 speakers per channel",
                "A compact voice-embedding model with simple online speaker matching. Useful as a lightweight baseline for clear, separate turns.",
                "Livekeet assigns one voice to each speech chunk. Interruptions, similar voices and overlapping speakers can confuse the matcher; it does not re-cluster the whole meeting.",
                "DER: no published score for Livekeet’s embedding-and-matching pipeline. Speaker-verification error rates measure a different task and cannot substitute for DER.",
                "Optional Python/MLX support; weights download on first use.",
                "https://huggingface.co/mlx-community/wespeaker-voxceleb-resnet34-LM")
        }
    }
}
