import LivekeetCore
import Sparkle
import SwiftUI

private enum ModelSelection: Hashable {
    case preset(String)
    case custom
}

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    let updater: SPUUpdater
    @State private var microphones = AudioCapture.listDevices()
    @State private var importError: String?
    @State private var customModelSelected = false
    @State private var installingSpeechSupport = false
    @State private var speechSetupMessage: String?

    var body: some View {
        @Bindable var settings = settings

        TabView {
            generalTab(settings: $settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            modelsTab(settings: $settings)
                .tabItem { Label("Models", systemImage: "waveform") }

            advancedTab(settings: $settings)
                .tabItem {
                    Label("Advanced", systemImage: "wrench")
                }

            updatesTab
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .frame(width: 540, height: 660)
        .alert("Could not import settings", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func generalTab(settings: Bindable<AppSettings>) -> some View {
        Form {
            Section("Microphone") {
                Picker("Input", selection: settings.inputDevice) {
                    Text("System default").tag("")
                    ForEach(microphones) { device in
                        Text(device.name).tag(device.id)
                    }
                    if !self.settings.inputDevice.isEmpty && !microphones.contains(where: { $0.id == self.settings.inputDevice }) {
                        Text(self.settings.inputDevice + " (saved selection)").tag(self.settings.inputDevice)
                    }
                }
                Button("Refresh microphones") { microphones = AudioCapture.listDevices() }
            }
            Section("Your identity") {
                TextField("Your name", text: settings.speakerName)
                    .textFieldStyle(.roundedBorder)
                Text("How you appear in the transcript.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Output") {
                HStack {
                    TextField("Output directory", text: settings.outputDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose...") {
                        chooseOutputDirectory()
                    }
                }
                Text("Transcripts save to: \(self.settings.resolvedOutputDirectory)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Filename pattern", text: settings.filenamePattern)
                    .textFieldStyle(.roundedBorder)
                Text("Placeholders: {date}, {time}, {datetime}, {names}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("CLI Settings") {
                Button("Import settings from CLI config") {
                    do { try self.settings.importCLISettings() }
                    catch { importError = error.localizedDescription }
                }
                Text("Copies preferences from ~/.config/livekeet/config.toml. Speaker credentials and word corrections are read from that file for each recording.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func modelsTab(settings: Bindable<AppSettings>) -> some View {
        Form {
            Section("Speech recognition") { modelPicker(settings: settings) }
            Section("Apple SpeechAnalyzer · unavailable") {
                Text("Introduced June 2025 · macOS 26 and later")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Apple’s on-device model is designed for live captions, long recordings and speech captured at a distance. macOS manages its language downloads and model updates.")
                    .font(.callout)
                Text("Unavailable in this build. Requires macOS 26; this Mac runs \(ProcessInfo.processInfo.operatingSystemVersionString). Apple does not publish a comparable WER in its introduction.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Apple’s model introduction ↗", destination: URL(string: "https://developer.apple.com/videos/play/wwdc2025/277/")!)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private func modelPicker(settings: Bindable<AppSettings>) -> some View {
        let matched = ModelCatalog.descriptor(for: self.settings.defaultModel)
        let selection: ModelSelection = customModelSelected ? .custom : matched.map { .preset($0.id) } ?? .custom

        return VStack(alignment: .leading, spacing: 6) {
            Picker("Transcription model", selection: Binding<ModelSelection>(
                get: { selection },
                set: { newValue in
                    customModelSelected = newValue == .custom
                    if case .preset(let id) = newValue {
                        self.settings.selectModel(id)
                    }
                }
            )) {
                ForEach(ModelCatalog.availableModels) { model in
                    Text(model.displayName).tag(ModelSelection.preset(model.id))
                }
                Text("Apple SpeechAnalyzer — unavailable (macOS 26+)")
                    .tag(ModelSelection.preset("apple/speech-analyzer"))
                    .disabled(true)
                Text("Custom…").tag(ModelSelection.custom)
            }

            if let matched, !customModelSelected {
                VStack(alignment: .leading, spacing: 10) {
                    Text(matched.subtitle).font(.subheadline.weight(.medium))
                    Text("Released \(matched.release) · \(matched.sizeDescription)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(matched.strengths).font(.callout)
                    Text(matched.tradeoffs).font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text(matched.benchmark).font(.callout)
                    DisclosureGroup("What does WER mean?") {
                        Text(ModelCatalog.benchmarkExplanation)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Link("Model details and published results ↗", destination: matched.source)
                        .font(.caption)
                    if matched.requiresLanguage {
                        Picker("Transcription language", selection: settings.speechLanguage) {
                            Text("Choose a language…").tag("")
                            ForEach(matched.languages) { language in
                                Text(language.name).tag(language.id)
                            }
                        }
                        Text("Required for this model. Speech is transcribed in the chosen language.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if matched.backend.needsPython {
                        Divider()
                        Text("Optional local speech support is required for this model.")
                            .font(.caption)
                        Button(installingSpeechSupport ? "Installing local support…" : "Set up local speech support") {
                            installingSpeechSupport = true
                            speechSetupMessage = nil
                            Task {
                                do {
                                    self.settings.pythonExecutable = try await SpeechHelperSetup.install()
                                    speechSetupMessage = "Local speech support is ready. Model weights download on first recording."
                                } catch { speechSetupMessage = error.localizedDescription }
                                installingSpeechSupport = false
                            }
                        }
                        .disabled(installingSpeechSupport)
                        if let speechSetupMessage {
                            Text(speechSetupMessage).font(.caption).textSelection(.enabled)
                        }
                    }
                }
                .padding(.vertical, 8)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Custom model id")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Hugging Face model id", text: Binding(
                    get: { self.settings.defaultModel },
                    set: { self.settings.selectModel($0) }
                ))
                .textFieldStyle(.roundedBorder)
                Text("Use a checkpoint compatible with one of the listed architectures.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text("Recognition runs on your Mac. Model weights download on first use. Published scores were checked in September 2026.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func advancedTab(settings: Bindable<AppSettings>) -> some View {
        Form {
            Section("Speaker Identification") {
                Toggle("Identify individual speakers", isOn: Binding(
                    get: { !self.settings.disableDiarization },
                    set: { self.settings.disableDiarization = !$0 }
                ))
                Picker("Engine", selection: settings.diarizationEngine) {
                    Text("Sortformer (native)").tag("sortformer")
                    Text("WeSpeaker (Python)").tag("wespeaker")
                    Text("pyannote (Python)").tag("pyannote")
                }
                .disabled(self.settings.disableDiarization)
                if self.settings.diarizationEngine != "sortformer" {
                    Text("Requires the optional Python helper. pyannote also needs a Hugging Face token in the CLI config.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Python Helper") {
                TextField("Python executable", text: settings.pythonExecutable)
                    .textFieldStyle(.roundedBorder)
                Text("Choose the Python environment with the optional speech models, speaker engines or Claude cleanup installed. An absolute path works when launching from Finder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Audio") {
                Toggle("Dump audio to disk", isOn: settings.dumpAudio)
                Text("Save raw audio chunks alongside the transcript for debugging.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI Correction") {
                Toggle("Enable correction (uses Claude Haiku)", isOn: settings.enableCorrection)
                Text("Sends recent transcript segments to the Anthropic API via the claude-runner sidecar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Timeout (seconds)", value: settings.correctionTimeout, format: .number)
                    .disabled(!self.settings.enableCorrection)
                TextField("Model", text: settings.correctionModel)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!self.settings.enableCorrection)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Correction prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: settings.correctionPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .border(Color.secondary.opacity(0.3))
                        .disabled(!self.settings.enableCorrection)
                    HStack {
                        Spacer()
                        Button("Reset to default") {
                            self.settings.correctionPrompt = CorrectionPromptBuilder.defaultBasePrompt
                        }
                        .disabled(!self.settings.enableCorrection)
                    }
                }
            }

            Section("Diagnostics") {
                Toggle("Debug mode", isOn: settings.debugMode)
                Text("Show pipeline stats panel while recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var updatesTab: some View {
        Form {
            Section("Software Update") {
                CheckForUpdatesView(updater: updater)
                    .buttonStyle(.borderedProminent)

                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
            }
        }
        .formStyle(.grouped)
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to save transcripts"
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputDirectory = url.path
        }
    }
}
