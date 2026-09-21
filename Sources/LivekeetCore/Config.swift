import Foundation
import TOMLKit

public enum DiarizationEngine: String, CaseIterable, Sendable {
    case sortformer, wespeaker, pyannote
}

// MARK: - LivekeetConfig

public struct LivekeetConfig: Sendable {
    public var outputDirectory: String
    public var filenamePattern: String
    public var speakerName: String
    public var defaultModel: String
    public var speechLanguage: String?
    public var otherNames: [String]
    public var micOnly: Bool
    public var systemOnly: Bool
    public var showStatus: Bool
    public var dumpAudio: Bool
    public var disableDiarization: Bool
    public var enableCorrection: Bool
    public var correctionPrompt: String
    public var correctionModel: String
    public var correctionSystemPrompt: String
    public var correctionTimeout: Double
    public var corrections: [String: String]
    public var inputDevice: String?
    public var diarizationEngine: DiarizationEngine
    public var pythonExecutable: String
    public var speechPythonExecutable: String?
    public var pyannoteToken: String?

    public init(
        outputDirectory: String = "",
        filenamePattern: String = "{datetime}.md",
        speakerName: String = "Me",
        defaultModel: String = ModelCatalog.parakeetV3.id,
        speechLanguage: String? = nil,
        otherNames: [String] = [],
        micOnly: Bool = false,
        systemOnly: Bool = false,
        showStatus: Bool = false,
        dumpAudio: Bool = false,
        disableDiarization: Bool = false,
        enableCorrection: Bool = false,
        correctionPrompt: String = CorrectionPromptBuilder.defaultBasePrompt,
        correctionModel: String = CorrectionPromptBuilder.defaultModel,
        correctionSystemPrompt: String = CorrectionPromptBuilder.defaultSystemPrompt,
        correctionTimeout: Double = 120,
        corrections: [String: String] = [:],
        inputDevice: String? = nil,
        diarizationEngine: DiarizationEngine = .sortformer,
        pythonExecutable: String = "python3",
        speechPythonExecutable: String? = nil,
        pyannoteToken: String? = nil
    ) {
        self.outputDirectory = outputDirectory
        self.filenamePattern = filenamePattern
        self.speakerName = speakerName
        self.defaultModel = defaultModel
        self.speechLanguage = speechLanguage
        self.otherNames = otherNames
        self.micOnly = micOnly
        self.systemOnly = systemOnly
        self.showStatus = showStatus
        self.dumpAudio = dumpAudio
        self.disableDiarization = disableDiarization
        self.enableCorrection = enableCorrection
        self.correctionPrompt = correctionPrompt
        self.correctionModel = correctionModel
        self.correctionSystemPrompt = correctionSystemPrompt
        self.correctionTimeout = correctionTimeout
        self.corrections = corrections
        self.inputDevice = inputDevice
        self.diarizationEngine = diarizationEngine
        self.speechPythonExecutable = speechPythonExecutable
        self.pythonExecutable = pythonExecutable
        self.pyannoteToken = pyannoteToken
    }

    // MARK: - Computed Properties

    /// The selected model, with legacy checkpoint IDs normalized.
    public var modelName: String {
        return ModelCatalog.canonicalID(for: defaultModel)
    }

    /// The primary other speaker name (first in the list, or "Other").
    public var otherName: String {
        otherNames.first ?? "Other"
    }

    // MARK: - Paths

    public static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/livekeet")
    public static let configFile = configDir.appendingPathComponent("config.toml")

    // MARK: - Load

    public static func load(from url: URL = configFile) throws -> LivekeetConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LivekeetConfig(disableDiarization: true)
        }
        return try parse(String(contentsOf: url, encoding: .utf8))
    }

    public static func parse(_ content: String) throws -> LivekeetConfig {
        var config = LivekeetConfig(disableDiarization: true)
        let toml = try TOMLTable(string: content)
        if let output = toml["output"]?.table {
            config.outputDirectory = output["directory"]?.string ?? config.outputDirectory
            config.filenamePattern = output["filename"]?.string ?? config.filenamePattern
        }
        if let speaker = toml["speaker"]?.table {
            config.speakerName = speaker["name"]?.string ?? config.speakerName
        }
        if let defaults = toml["defaults"]?.table {
            config.defaultModel = defaults["model"]?.string ?? config.defaultModel
            config.speechLanguage = defaults["language"]?.string
            config.disableDiarization = !(defaults["diarize"]?.bool ?? false)
            config.inputDevice = defaults["device"]?.string
            if let engine = defaults["engine"]?.string {
                guard let parsed = DiarizationEngine(rawValue: engine) else {
                    throw ConfigError.invalidEngine(engine)
                }
                config.diarizationEngine = parsed
                if parsed == .pyannote { config.disableDiarization = false }
            }
        }
        if let cleanup = toml["cleanup"]?.table {
            config.enableCorrection = cleanup["enabled"]?.bool ?? false
            config.correctionModel = cleanup["model"]?.string ?? config.correctionModel
            if let prompt = cleanup["system_prompt"]?.string, !prompt.isEmpty {
                // Keep the batch JSON response contract while honoring user cleanup instructions.
                config.correctionSystemPrompt = prompt + "\n" + CorrectionPromptBuilder.defaultSystemPrompt
            }
            config.correctionPrompt = cleanup["prompt"]?.string ?? config.correctionPrompt
            if let timeout = cleanup["timeout_s"]?.double {
                config.correctionTimeout = timeout
            } else if let timeout = cleanup["timeout_s"]?.int {
                config.correctionTimeout = Double(timeout)
            }
            if let replacements = cleanup["corrections"]?.table {
                for (key, value) in replacements {
                    if let value = value.string { config.corrections[key] = value }
                }
            }
        }
        if let helper = toml["python"]?.table {
            config.pythonExecutable = helper["executable"]?.string ?? config.pythonExecutable
            config.speechPythonExecutable = helper["speech_executable"]?.string
        }
        if let pyannote = toml["pyannote"]?.table {
            config.pyannoteToken = pyannote["token"]?.string
        }
        guard config.correctionTimeout.isFinite, config.correctionTimeout > 0 else {
            throw ConfigError.invalidTimeout
        }
        return config
    }

    public enum ConfigError: LocalizedError {
        case invalidEngine(String), invalidTimeout
        public var errorDescription: String? {
            switch self {
            case .invalidEngine(let value): return "Unknown diarization engine '\(value)'; choose sortformer, wespeaker, or pyannote."
            case .invalidTimeout: return "cleanup.timeout_s must be a positive finite number."
            }
        }
    }

    // MARK: - Create Default

    public static func createDefault() throws {
        let dir = configDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let configPath = configFile
        if FileManager.default.fileExists(atPath: configPath.path) {
            print("Config already exists: \(configPath.path)")
        } else {
            try defaultConfigContent.write(to: configPath, atomically: true, encoding: .utf8)
            print("Created: \(configPath.path)")
        }

        print("""

        Settings:
          speaker.name     Your name in transcripts
          output.directory Where to save files (default: current dir)
          output.filename  Pattern: {date}, {time}, {datetime}, {names}
          defaults.model   Speech recognition model

        Run livekeet models to compare all supported models.
        Models (downloaded on first use):
          parakeet-tdt-0.6b-v2  English
          parakeet-tdt-0.6b-v3  Multilingual, 25 languages (default)
        """)
    }

    public static let defaultConfigContent = """
    # livekeet configuration

    [output]
    # Directory for transcripts (empty = current directory)
    directory = ""
    # Filename pattern: {date}, {time}, {datetime}, {names}, or any static name
    # Examples: "{datetime}.md", "{date}-meeting.md", "transcript.md"
    filename = "{datetime}.md"

    [speaker]
    # Your name in transcripts (when using system audio for calls)
    name = "Me"

    [defaults]
    # Available models (downloaded automatically on first use):
    #   mlx-community/parakeet-tdt-0.6b-v2 - English
    #   mlx-community/parakeet-tdt-0.6b-v3  - Multilingual, 25 languages (default)
    model = "mlx-community/parakeet-tdt-0.6b-v3"
    # Required for Cohere and Canary; ISO code, e.g. es or en.
    # language = "es"
    diarize = false
    engine = "sortformer" # sortformer (native), wespeaker, or pyannote
    # device = "MacBook Pro Microphone" # name, UID, or --devices index

    [cleanup]
    enabled = false
    model = "claude-haiku-4-5-20251001"
    timeout_s = 120.0
    # system_prompt = "Additional cleanup instructions"
    # prompt = "Custom batch correction prompt"

    [cleanup.corrections]
    # "chat gbt" = "ChatGPT" # applied even with --no-cleanup

    [python]
    executable = "python3" # or an absolute path to a virtualenv's python
    # speech_executable = "/path/to/python" # optional separate speech environment

    [pyannote]
    # token = "hf_..." # alternatively set HF_TOKEN in the environment
    """
}
