import LivekeetCore
import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TranscriptViewModel.self) private var viewModel
    @Environment(RecordingHistoryModel.self) private var history
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedRecordingID: UUID?
    @State private var selectedProjectID: UUID?
    @State private var draftProjectID: UUID?

    private var draftProject: RecordingProject? { history.projects.first { $0.id == draftProjectID } }
    private var recordingOutputDirectory: String { draftProject?.folderURL.path ?? recordingFolder ?? settings.resolvedOutputDirectory }
    @State private var recordingName = ""
    @State private var recordingFolder: String?
    @State private var saveAudio = false

    var body: some View {
        NavigationSplitView {
            RecordingHistorySidebar(viewModel: viewModel, selection: $selectedRecordingID,
                                    projectSelection: $selectedProjectID, projectSelected: selectProject) {
                prepareNewRecording()
            }
        } detail: {
            if let id = selectedRecordingID,
               id != viewModel.recordingID || (!viewModel.isRecording && viewModel.savedFilePath != nil),
               let recording = history.recordings.first(where: { $0.id == id }) {
                SavedRecordingView(recording: recording)
                    .id(recording.id)
            } else {
                recordingPane
            }
        }
        .frame(minWidth: 960, minHeight: 500)
        .task { await history.refresh(discovering: settings.resolvedOutputDirectory) }
        .onChange(of: history.movingRecordingID) { previous, current in
            if current == nil, previous == viewModel.recordingID, !viewModel.isRecording {
                viewModel.recordingID = nil
                viewModel.savedFilePath = nil
            }
        }
        .onChange(of: draftProjectID) { _, _ in recordingFolder = nil }
        .onChange(of: viewModel.recordingID) { _, id in
            selectedRecordingID = id
            Task { await history.refresh() }
        }
        .onChange(of: viewModel.savedFilePath) { _, path in
            if path != nil { Task { await history.refresh() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await history.refresh(discovering: settings.resolvedOutputDirectory) } }
        }
        .onChange(of: settings.outputDirectory) { _, _ in
            Task { await history.refresh(discovering: settings.resolvedOutputDirectory) }
        }
    }

    @ViewBuilder
    private var recordingPane: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            // Settings here apply to this recording, without changing the default folder.
            VStack(spacing: 10) {
                HStack {
                    TextField("Recording name (optional)", text: $recordingName)
                        .textFieldStyle(.plain).font(.title3.weight(.medium))
                        .disabled(viewModel.isRecording)
                    Spacer()
                    Picker("Project", selection: $draftProjectID) {
                        Text("No project").tag(nil as UUID?)
                        ForEach(history.projects) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                    .frame(maxWidth: 260).disabled(viewModel.isRecording)
                }
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(recordingOutputDirectory)
                        .font(.caption).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary).help(recordingOutputDirectory)
                    if draftProjectID == nil {
                        Button("Choose folder…") { chooseRecordingFolder() }
                            .disabled(viewModel.isRecording)
                        if recordingFolder != nil {
                            Button("Use default") { recordingFolder = nil }.disabled(viewModel.isRecording)
                        }
                    } else if draftProject?.isAvailable != true {
                        Label("Folder unavailable", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.red)
                    }
                    Spacer()
                    Toggle("Save full audio", isOn: $saveAudio)
                        .font(.caption).toggleStyle(.checkbox).disabled(viewModel.isRecording)
                        .help("Save microphone and system WAV files beside the transcript. Applies to this recording.")
                }
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        TextField("Other speakers for this recording", text: $viewModel.otherNames)
                            .textFieldStyle(.plain)
                            .help("Optional comma-separated names, for example Alice, Bob. Cleared after the recording is saved.")
                            .disabled(viewModel.isRecording)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

                    Spacer()
                    SettingsLink { Image(systemName: "gear") }
                        .buttonStyle(.plain)
                    recordButton
                }

            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Transcript
            ZStack {
                Color(nsColor: .textBackgroundColor)

                if viewModel.segments.isEmpty && !viewModel.isLoading && viewModel.errorMessage == nil {
                    VStack(spacing: 8) {
                        Image(systemName: viewModel.isRecording ? "waveform" : "mic.badge.plus")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundStyle(.tertiary)
                        Text(viewModel.isRecording ? "Waiting for speech..." : "Press Record to start")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    TranscriptView(segments: viewModel.segments) { channel, speakerIndex, currentName in
                        viewModel.beginRename(channel: channel, speakerIndex: speakerIndex, currentName: currentName)
                    }
                }
            }

            // Debug stats panel
            if let stats = viewModel.debugStats, settings.debugMode {
                Divider()
                DebugStatsPanel(stats: stats)
            }

            // Status bar
            if viewModel.isLoading || viewModel.isStopping || viewModel.errorMessage != nil || viewModel.savedFilePath != nil {
                Divider()
                HStack(spacing: 8) {
                    if viewModel.isStopping {
                        ProgressView().controlSize(.small)
                        Text("Finishing transcription and speaker analysis…")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading models...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let error = viewModel.errorMessage {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                    if let path = viewModel.savedFilePath {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .alert("Rename Speaker", isPresented: $viewModel.isShowingRename) {
            TextField("Name", text: $viewModel.renameText)
            Button("Rename") { viewModel.confirmRename() }
            Button("Cancel", role: .cancel) { }
        }
        .onChange(of: viewModel.isRecording) { _, isRecording in
            if isRecording && settings.debugMode {
                viewModel.startDebugPolling()
            } else if !isRecording {
                viewModel.stopDebugPolling()
            }
        }
        .onChange(of: settings.debugMode) { _, debugMode in
            if debugMode && viewModel.isRecording {
                viewModel.startDebugPolling()
            } else if !debugMode {
                viewModel.stopDebugPolling()
            }
        }
        .frame(minWidth: 680, minHeight: 350)
    }

    private func selectProject(_ id: UUID?) {
        selectedProjectID = id
        if !viewModel.isRecording { prepareNewRecording() }
        else { selectedRecordingID = history.recordings(in: id).first?.id }
    }

    private func prepareNewRecording() {
        selectedRecordingID = nil
        draftProjectID = selectedProjectID
        recordingName = ""
        recordingFolder = nil
        saveAudio = false
        viewModel.recordingID = nil
        viewModel.savedFilePath = nil
        viewModel.segments = []
        viewModel.errorMessage = nil
        viewModel.otherNames = ""
    }

    private func chooseRecordingFolder() {
        let panel = NSOpenPanel()
        panel.title = "Save this recording in…"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: recordingFolder ?? settings.resolvedOutputDirectory)
        if panel.runModal() == .OK { recordingFolder = panel.url?.path }
    }

    private var recordButton: some View {
        Button(action: {
            if viewModel.isRecording {
                viewModel.stopRecording()
            } else {
                var config = settings.buildConfig(otherNames: viewModel.otherNamesList)
                config.outputDirectory = recordingOutputDirectory
                let name = recordingName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    let safeName = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_").replacingOccurrences(of: ":", with: "-")
                    config.filenamePattern = safeName.hasSuffix(".md") ? safeName : safeName + ".md"
                }
                config.saveAudio = saveAudio
                if let draftProjectID {
                    guard let project = history.projects.first(where: { $0.id == draftProjectID }), project.isAvailable else {
                        viewModel.errorMessage = "The project folder is unavailable. Reconnect its drive before recording."
                        return
                    }
                    do { _ = try project.outputPath(argument: nil, config: config) }
                    catch { viewModel.errorMessage = error.localizedDescription; return }
                }
                viewModel.startRecording(config: config)
            }
        }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isRecording ? Color.red : Color.red.opacity(0.6))
                    .frame(width: 10, height: 10)
                    .overlay {
                        if viewModel.isRecording {
                            Circle()
                                .fill(.red.opacity(0.4))
                                .frame(width: 16, height: 16)
                        }
                    }
                Text(viewModel.isRecording ? "Stop" : "Record")
                    .font(.callout.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                viewModel.isRecording
                    ? AnyShapeStyle(Color.red.opacity(0.1))
                    : AnyShapeStyle(.quaternary.opacity(0.5)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isStopping)
        .keyboardShortcut("r", modifiers: .command)
    }
}

// MARK: - Debug Stats Panel

struct DebugStatsPanel: View {
    let stats: DebugStats

    var body: some View {
        HStack(spacing: 12) {
            statItem(stats.pipelineState, icon: pipelineIcon, color: pipelineColor)
            divider
            if let age = stats.secondsSinceLastAudio {
                statItem(formatAge(age), icon: "waveform", color: age > 5 ? .red : .secondary)
            } else {
                statItem("No audio", icon: "waveform", color: .red)
            }
            divider
            statItem("\(stats.pendingTranscriptions) pending", icon: "text.bubble", color: stats.pendingTranscriptions > 3 ? .orange : .secondary)
            divider
            if let dur = stats.lastInferenceAudioDuration, let ratio = stats.lastInferenceRatio {
                statItem(String(format: "%.1fs @ %.1fx", dur, ratio), icon: "brain", color: ratio < 1.0 ? .red : .secondary)
            } else {
                statItem("-- STT", icon: "brain", color: .secondary)
            }
            divider
            statItem("\(stats.mlxActiveMemoryMB)/\(stats.mlxCacheMemoryMB) MB", icon: "memorychip", color: .secondary)
            divider
            let ovf = stats.micOverflowCount + stats.systemOverflowCount
            statItem("\(ovf) ovf", icon: "exclamationmark.triangle", color: ovf > 0 ? .orange : .secondary)
            divider
            statItem("\(stats.totalSegments) seg", icon: "doc.text", color: .secondary)
            Spacer()
        }
        .font(.system(.caption2, design: .monospaced))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var divider: some View {
        Divider().frame(height: 12)
    }

    private func statItem(_ label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).foregroundStyle(color)
            Text(label).foregroundStyle(color)
        }
    }

    private var pipelineIcon: String {
        switch stats.pipelineState {
        case "Recording": "record.circle"
        case "Processing": "gearshape.2"
        case "Stuck?": "exclamationmark.triangle.fill"
        case "Waiting for audio": "ear"
        default: "pause.circle"
        }
    }

    private var pipelineColor: Color {
        switch stats.pipelineState {
        case "Recording": .green
        case "Processing": .blue
        case "Stuck?": .red
        case "Waiting for audio": .orange
        default: .secondary
        }
    }

    private func formatAge(_ seconds: Double) -> String {
        if seconds < 1 { return "<1s ago" }
        if seconds < 60 { return "\(Int(seconds))s ago" }
        return "\(Int(seconds / 60))m ago"
    }
}
