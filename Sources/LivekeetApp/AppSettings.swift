import Foundation
import LivekeetCore
import Observation

@Observable
final class AppSettings {
    private static let defaults = UserDefaults.standard

    var speakerName: String {
        get {
            access(keyPath: \.speakerName)
            return Self.defaults.string(forKey: "speakerName") ?? "Me"
        }
        set {
            withMutation(keyPath: \.speakerName) {
                Self.defaults.set(newValue, forKey: "speakerName")
            }
        }
    }

    var micOnly: Bool {
        get {
            access(keyPath: \.micOnly)
            return Self.defaults.bool(forKey: "micOnly")
        }
        set {
            withMutation(keyPath: \.micOnly) {
                Self.defaults.set(newValue, forKey: "micOnly")
            }
            if newValue {
                systemOnly = false
            }
        }
    }

    var systemOnly: Bool {
        get {
            access(keyPath: \.systemOnly)
            return Self.defaults.bool(forKey: "systemOnly")
        }
        set {
            withMutation(keyPath: \.systemOnly) {
                Self.defaults.set(newValue, forKey: "systemOnly")
            }
            if newValue {
                micOnly = false
            }
        }
    }

    var outputDirectory: String {
        get {
            access(keyPath: \.outputDirectory)
            return Self.defaults.string(forKey: "outputDirectory") ?? ""
        }
        set {
            withMutation(keyPath: \.outputDirectory) {
                Self.defaults.set(newValue, forKey: "outputDirectory")
            }
        }
    }

    var filenamePattern: String {
        get {
            access(keyPath: \.filenamePattern)
            return Self.defaults.string(forKey: "filenamePattern") ?? "{datetime}.md"
        }
        set {
            withMutation(keyPath: \.filenamePattern) {
                Self.defaults.set(newValue, forKey: "filenamePattern")
            }
        }
    }

    var defaultModel: String {
        get {
            access(keyPath: \.defaultModel)
            return ModelCatalog.canonicalID(for: Self.defaults.string(forKey: "defaultModel") ?? ModelCatalog.parakeetV3.id)
        }
        set {
            withMutation(keyPath: \.defaultModel) {
                Self.defaults.set(newValue, forKey: "defaultModel")
            }
        }
    }

    var dumpAudio: Bool {
        get {
            access(keyPath: \.dumpAudio)
            return Self.defaults.bool(forKey: "dumpAudio")
        }
        set {
            withMutation(keyPath: \.dumpAudio) {
                Self.defaults.set(newValue, forKey: "dumpAudio")
            }
        }
    }

    var disableDiarization: Bool {
        get {
            access(keyPath: \.disableDiarization)
            return Self.defaults.bool(forKey: "disableDiarization")
        }
        set {
            withMutation(keyPath: \.disableDiarization) {
                Self.defaults.set(newValue, forKey: "disableDiarization")
            }
        }
    }

    var enableCorrection: Bool {
        get {
            access(keyPath: \.enableCorrection)
            return Self.defaults.bool(forKey: "enableCorrection")
        }
        set {
            withMutation(keyPath: \.enableCorrection) {
                Self.defaults.set(newValue, forKey: "enableCorrection")
            }
        }
    }

    var debugMode: Bool {
        get {
            access(keyPath: \.debugMode)
            return Self.defaults.bool(forKey: "debugMode")
        }
        set {
            withMutation(keyPath: \.debugMode) {
                Self.defaults.set(newValue, forKey: "debugMode")
            }
        }
    }

    var correctionPrompt: String {
        get {
            access(keyPath: \.correctionPrompt)
            return Self.defaults.string(forKey: "correctionPrompt") ?? CorrectionPromptBuilder.defaultBasePrompt
        }
        set {
            withMutation(keyPath: \.correctionPrompt) {
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    Self.defaults.removeObject(forKey: "correctionPrompt")
                } else {
                    Self.defaults.set(newValue, forKey: "correctionPrompt")
                }
            }
        }
    }

    var correctionModel: String {
        get {
            access(keyPath: \.correctionModel)
            return Self.defaults.string(forKey: "correctionModel") ?? CorrectionPromptBuilder.defaultModel
        }
        set {
            withMutation(keyPath: \.correctionModel) {
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    Self.defaults.removeObject(forKey: "correctionModel")
                } else {
                    Self.defaults.set(newValue, forKey: "correctionModel")
                }
            }
        }
    }

    var inputDevice: String {
        get {
            access(keyPath: \.inputDevice)
            return Self.defaults.string(forKey: "inputDevice") ?? ""
        }
        set {
            withMutation(keyPath: \.inputDevice) { Self.defaults.set(newValue, forKey: "inputDevice") }
        }
    }

    var diarizationEngine: String {
        get {
            access(keyPath: \.diarizationEngine)
            return Self.defaults.string(forKey: "diarizationEngine") ?? "sortformer"
        }
        set {
            withMutation(keyPath: \.diarizationEngine) { Self.defaults.set(newValue, forKey: "diarizationEngine") }
        }
    }

    var pythonExecutable: String {
        get {
            access(keyPath: \.pythonExecutable)
            return Self.defaults.string(forKey: "pythonExecutable") ?? "python3"
        }
        set {
            withMutation(keyPath: \.pythonExecutable) { Self.defaults.set(newValue, forKey: "pythonExecutable") }
        }
    }

    var correctionSystemPrompt: String {
        get {
            access(keyPath: \.correctionSystemPrompt)
            return Self.defaults.string(forKey: "correctionSystemPrompt") ?? CorrectionPromptBuilder.defaultSystemPrompt
        }
        set {
            withMutation(keyPath: \.correctionSystemPrompt) { Self.defaults.set(newValue, forKey: "correctionSystemPrompt") }
        }
    }

    var correctionTimeout: Double {
        get {
            access(keyPath: \.correctionTimeout)
            return (Self.defaults.object(forKey: "correctionTimeout") as? Double) ?? 120
        }
        set {
            withMutation(keyPath: \.correctionTimeout) { Self.defaults.set(newValue, forKey: "correctionTimeout") }
        }
    }

    var speechPythonExecutable: String {
        get {
            access(keyPath: \.speechPythonExecutable)
            return Self.defaults.string(forKey: "speechPythonExecutable") ?? ""
        }
        set {
            withMutation(keyPath: \.speechPythonExecutable) { Self.defaults.set(newValue, forKey: "speechPythonExecutable") }
        }
    }

    var speechLanguage: String {
        get {
            access(keyPath: \.speechLanguage)
            return Self.defaults.string(forKey: "speechLanguage") ?? ""
        }
        set {
            withMutation(keyPath: \.speechLanguage) { Self.defaults.set(newValue, forKey: "speechLanguage") }
        }
    }

    func selectModel(_ id: String) {
        defaultModel = ModelCatalog.canonicalID(for: id)
        if let model = ModelCatalog.descriptor(for: defaultModel), model.requiresLanguage,
           !model.languageCodes.contains(speechLanguage) {
            speechLanguage = ""
        }
    }

    func importCLISettings() throws {
        let config = try LivekeetConfig.load()
        speakerName = config.speakerName
        outputDirectory = config.outputDirectory
        filenamePattern = config.filenamePattern
        selectModel(config.defaultModel)
        speechLanguage = config.speechLanguage ?? ""
        inputDevice = config.inputDevice ?? ""
        disableDiarization = config.disableDiarization
        diarizationEngine = config.diarizationEngine.rawValue
        enableCorrection = config.enableCorrection
        correctionModel = config.correctionModel
        correctionPrompt = config.correctionPrompt
        correctionSystemPrompt = config.correctionSystemPrompt
        correctionTimeout = config.correctionTimeout
        pythonExecutable = config.pythonExecutable
        speechPythonExecutable = config.speechPythonExecutable ?? ""
    }

    // MARK: - Computed Helpers

    var resolvedOutputDirectory: String {
        let directory = outputDirectory.isEmpty ? "~/recordings" : outputDirectory
        return NSString(string: directory).expandingTildeInPath
    }

    func buildConfig(otherNames: [String]) -> LivekeetConfig {
        var config = LivekeetConfig(
            outputDirectory: resolvedOutputDirectory,
            filenamePattern: filenamePattern,
            speakerName: speakerName.isEmpty ? "Me" : speakerName,
            defaultModel: defaultModel,
            speechLanguage: speechLanguage.isEmpty ? nil : speechLanguage,
            otherNames: otherNames,
            micOnly: micOnly,
            systemOnly: systemOnly,
            showStatus: debugMode,
            dumpAudio: dumpAudio,
            disableDiarization: disableDiarization,
            enableCorrection: enableCorrection,
            correctionPrompt: correctionPrompt,
            correctionModel: correctionModel,
            correctionSystemPrompt: correctionSystemPrompt,
            correctionTimeout: correctionTimeout,
            inputDevice: inputDevice.isEmpty || systemOnly ? nil : inputDevice,
            diarizationEngine: DiarizationEngine(rawValue: diarizationEngine) ?? .sortformer,
            pythonExecutable: pythonExecutable,
            speechPythonExecutable: speechPythonExecutable.isEmpty ? nil : speechPythonExecutable
        )
        // Secrets and replacement dictionaries stay in the user's existing TOML file.
        if let shared = try? LivekeetConfig.load() {
            config.pyannoteToken = shared.pyannoteToken
            config.corrections = shared.corrections
        }
        return config
    }
}
