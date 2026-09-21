import ArgumentParser
import Darwin
import Foundation
import LivekeetCore
import os

extension DiarizationEngine: ExpressibleByArgument {}

enum CLIVersion {
    static let current = "0.3.0"
}

@main
struct Livekeet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "livekeet",
        abstract: "Live microphone and system-audio transcription to Markdown.",
        discussion: "Run livekeet record --help for recording controls. Utility commands never load speech models.",
        version: CLIVersion.current,
        subcommands: [Record.self, Init.self, Config.self, Devices.self, Models.self, Relabel.self, Update.self],
        defaultSubcommand: Record.self
    )
}

struct Record: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Record and transcribe audio (the default command).",
        discussion: """
        Examples:
          livekeet meeting.md --with "Alice,Bob" --diarize
          livekeet --mic-only --device "USB" --cleanup
          livekeet --system-only --engine pyannote
        """
    )

    @Argument(help: "Output file or directory; defaults to ~/recordings and the config filename pattern, unless configured otherwise.")
    var output: String?
    @Option(name: [.short, .customLong("with")], help: "Comma-separated remote speaker names; multiple names enable diarization.")
    var with: String?
    @Flag(name: [.customShort("m"), .long], help: "Capture microphone only.")
    var micOnly = false
    @Flag(help: "Capture system audio only.")
    var systemOnly = false
    @Option(name: [.short, .long], help: "Microphone index, name, or UID from --devices.")
    var device: String?
    @Option(help: "Hugging Face speech model ID; see livekeet models.")
    var model: String?
    @Option(help: "Transcription language for Cohere/Canary (ISO code, e.g. es or en).")
    var language: String?
    @Flag(help: "Identify individual speakers on each channel.")
    var diarize = false
    @Flag(help: "Disable speaker identification, overriding config and automatic enabling.")
    var noDiarize = false
    @Option(help: "Speaker engine: sortformer (native), wespeaker, or pyannote (Python helper).")
    var engine: DiarizationEngine?
    @Flag(help: "Enable optional Claude transcript correction.")
    var cleanup = false
    @Flag(help: "Disable Claude correction, overriding --cleanup and config.")
    var noCleanup = false
    @Flag(help: "Show periodic recording status.")
    var status = false
    @Flag(help: "Save full captured microphone/system audio as WAV files beside the transcript.")
    var saveAudio = false
    @Flag(help: "Save speech segments as WAVs alongside the transcript.")
    var dumpAudio = false
    @Flag(help: "Skip interactive speaker renaming after recording.")
    var noRelabel = false
    @Flag(name: .customLong("init"), help: "Create the default config and exit (alias for init).")
    var initialize = false
    @Flag(name: .customLong("config"), help: "Show the config location and exit.")
    var showConfig = false
    @Flag(name: .customLong("devices"), help: "List microphones and exit.")
    var showDevices = false

    mutating func validate() throws {
        guard !initialize && !showConfig && !showDevices else { return }
        if micOnly && systemOnly { throw ValidationError("--mic-only and --system-only cannot be combined.") }
        if device != nil && systemOnly { throw ValidationError("--device selects a microphone and cannot be used with --system-only.") }
    }

    func resolvedConfig(_ base: LivekeetConfig) -> LivekeetConfig {
        var config = base
        config.micOnly = micOnly
        config.systemOnly = systemOnly
        config.showStatus = status
        config.dumpAudio = dumpAudio
        if saveAudio { config.saveAudio = true }
        if let model { config.defaultModel = model }
        if let language { config.speechLanguage = language }
        if let device { config.inputDevice = device }
        if let with {
            config.otherNames = with.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if micOnly { config.otherNames = [] }
        if let engine { config.diarizationEngine = engine }
        if diarize || engine != nil || config.otherNames.count > 1 { config.disableDiarization = false }
        if noDiarize { config.disableDiarization = true }
        if cleanup { config.enableCorrection = true }
        if noCleanup { config.enableCorrection = false }
        if systemOnly { config.inputDevice = nil }
        return config
    }

    func run() async throws {
        if initialize { try LivekeetConfig.createDefault(); return }
        if showConfig { Config.show(); return }
        if showDevices { Devices.show(); return }
        Log.consoleEnabled = true
        defer { Log.consoleEnabled = false }
        let config = resolvedConfig(try LivekeetConfig.load())
        if micOnly && with != nil { Self.warn("--with is ignored in --mic-only mode") }
        if let selection = config.inputDevice {
            let chosen = try AudioInputDevice.resolve(selection, in: AudioCapture.listDevices())
            print("Microphone: \(chosen.name)")
        }
        print("Speech model: \(config.modelName)")
        print("Speaker identification: \(config.disableDiarization ? "off" : config.diarizationEngine.rawValue)")
        if config.enableCorrection { print("AI cleanup enabled: transcript text will be sent to Claude.") }
        let transcriber = try await Transcriber(config: config, outputArg: output)
        let interrupts = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        let previousINT = signal(SIGINT, SIG_IGN)
        let previousTERM = signal(SIGTERM, SIG_IGN)
        let terminated = OSAllocatedUnfairLock(initialState: false)
        interrupts.setEventHandler {
            print("\nStopping; finishing queued transcription...")
            Task { await transcriber.stop() }
        }
        termination.setEventHandler {
            terminated.withLock { $0 = true }
            Task { await transcriber.stop() }
        }
        interrupts.resume()
        termination.resume()
        defer {
            interrupts.cancel()
            termination.cancel()
            signal(SIGINT, previousINT)
            signal(SIGTERM, previousTERM)
        }
        try await transcriber.run()
        interrupts.cancel()
        termination.cancel()
        signal(SIGINT, previousINT)
        signal(SIGTERM, previousTERM)
        let path = await transcriber.savedOutputPath
        print("Saved: \(path.path)")
        if !noRelabel && !micOnly && !terminated.withLock({ $0 }) && isatty(STDIN_FILENO) != 0 {
            try Relabel.interactive(path)
        }
    }

    static func warn(_ message: String) {
        FileHandle.standardError.write(Data("Warning: \(message)\n".utf8))
    }
}

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create ~/.config/livekeet/config.toml without overwriting an existing file.")
    func run() throws { try LivekeetConfig.createDefault() }
}

struct Config: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show the configuration file location.")
    static func show() {
        print("Config file: \(LivekeetConfig.configFile.path)")
        print(FileManager.default.fileExists(atPath: LivekeetConfig.configFile.path) ? "(exists)" : "(not created yet; run livekeet init)")
    }
    func run() { Self.show() }
}

struct Devices: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List microphones and their selection indices and UIDs.")
    static func show() {
        let devices = AudioCapture.listDevices()
        if devices.isEmpty { print("No microphones found."); return }
        for (index, device) in devices.enumerated() {
            print("\(index): \(device.name)\(device.isDefault ? " (default)" : "")\n   UID: \(device.id)")
        }
        print("Select with --device <index, name, or UID>. Indices may change when devices reconnect.")
    }
    func run() { Self.show() }
}

struct Models: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the curated speech models.")
    func run() {
        for model in ModelCatalog.availableModels {
            print("\(model.id)\n  \(model.displayName) — \(model.subtitle)")
            print("  Released: \(model.release). \(model.strengths)")
            print("  \(model.benchmark)\n  \(model.tradeoffs)\n  Source: \(model.source.absoluteString)\n")
        }
    }
}
