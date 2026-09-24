import AppKit
import LivekeetCore
import SwiftUI

struct RecordingHistorySidebar: View {
    @Environment(RecordingHistoryModel.self) private var history
    @Bindable var viewModel: TranscriptViewModel
    @Binding var selection: UUID?
    @Binding var projectSelection: UUID?
    let projectSelected: (UUID?) -> Void
    let newRecording: () -> Void
    @State private var editingProject: RecordingProject?
    @State private var showingProjectEditor = false
    @State private var removingProject: RecordingProject?

    private var visibleRecordings: [Recording] { history.recordings(in: projectSelection) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recordings").font(.headline)
                Spacer()
                Button(action: newRecording) { Image(systemName: "plus") }
                    .help("New recording")
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(viewModel.isRecording)
            }
            .padding(14)
            HStack {
                Text("Projects").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    editingProject = nil
                    showingProjectEditor = true
                } label: { Image(systemName: "folder.badge.plus") }
                .buttonStyle(.borderless).help("New project")
            }.padding(.horizontal, 14).padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 2) {
                    projectRow(name: "All recordings", symbol: "tray.full", id: nil, count: history.recordings.count)
                    ForEach(history.projects) { project in
                        projectRow(name: project.name, symbol: project.isAvailable ? "folder" : "questionmark.folder",
                                   id: project.id, count: history.recordings(in: project.id).count)
                            .help(project.folderURL.path)
                            .contextMenu {
                                Button("Rename project…") {
                                    editingProject = project
                                    showingProjectEditor = true
                                }
                                Button("Show folder") { NSWorkspace.shared.open(project.folderURL) }
                                    .disabled(!project.isAvailable)
                                Button("Remove project…") { removingProject = project }
                                    .disabled(viewModel.isRecording)
                            }
                    }
                }.padding(.horizontal, 8)
            }
            .frame(height: min(CGFloat(history.projects.count + 1) * 32, 180))
            Divider().padding(.top, 8)
            if let project = history.projects.first(where: { $0.id == projectSelection }) {
                Text(project.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 10)
            }
            if viewModel.isRecording {
                Button {
                    selection = viewModel.recordingID
                } label: {
                    Label(viewModel.isLoading ? "Loading current recording…" : "Current recording", systemImage: "record.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
            List(selection: $selection) {
                ForEach(visibleRecordings) { recording in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recording.title).font(.callout.weight(.medium)).lineLimit(2)
                        Text(recording.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        if viewModel.isRecording && recording.id == viewModel.recordingID {
                            Label("Recording", systemImage: "record.circle.fill").foregroundStyle(.red).font(.caption2)
                        } else if !recording.isAvailable {
                            Label("File unavailable", systemImage: "questionmark.folder").foregroundStyle(.secondary).font(.caption2)
                        } else if recording.status == .unfinished {
                            Text("Unfinished").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(recording.id)
                    .contextMenu {
                        CopyTextButton("Copy full path", text: recording.transcriptURL.path)
                        Button("Locate transcript…") { Task { await history.locate(recording) } }
                            .disabled(recording.status == .unfinished)
                        if !history.projects.isEmpty {
                            Menu("Move to project") {
                                ForEach(history.projects) { project in
                                    Button(project.name) { Task { await history.move(recording, to: project) } }
                                        .disabled(project.contains(recording) || !project.isAvailable)
                                }
                            }
                            .disabled(recording.status == .unfinished || !recording.isAvailable || history.movingRecordingID != nil ||
                                      (viewModel.isRecording && recording.id == viewModel.recordingID))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if visibleRecordings.isEmpty {
                    Text(projectSelection == nil ? "Your saved recordings will appear here, wherever you save them." : "No recordings yet. New recordings in this project will save to its folder.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(20)
                }
            }
            Divider()
            HStack {
                Button("Import transcripts…") {
                    Task {
                        if let id = await history.importTranscripts() {
                            projectSelection = nil
                            selection = id
                        }
                    }
                }
                .buttonStyle(.borderless)
                Spacer()
                Button { Task { await history.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh recordings")
            }
            .padding(12)
            if let error = history.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled).padding(12)
            }
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 350)
        .sheet(isPresented: $showingProjectEditor) {
            ProjectEditorView(project: editingProject) { id in projectSelected(id) }
                .environment(history)
        }
        .confirmationDialog("Remove project?", isPresented: Binding(
            get: { removingProject != nil }, set: { if !$0 { removingProject = nil } }
        ), titleVisibility: .visible) {
            if let project = removingProject {
                Button("Remove \(project.name)") {
                    Task {
                        if await history.removeProject(project), projectSelection == project.id { projectSelected(nil) }
                        removingProject = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { removingProject = nil }
        } message: {
            Text("Recordings and folders stay on disk and remain in All recordings.")
        }
    }

    private func projectRow(name: String, symbol: String, id: UUID?, count: Int) -> some View {
        Button { projectSelected(id) } label: {
            HStack {
                Label(name, systemImage: symbol).lineLimit(1)
                Spacer()
                Text(count.formatted()).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).frame(height: 30)
            .background(projectSelection == id ? Color.accentColor.opacity(0.15) : .clear,
                        in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityLabel("\(name), \(count) recordings")
        .accessibilityAddTraits(projectSelection == id ? .isSelected : [])
    }
}

struct SavedRecordingView: View {
    let recording: Recording
    @Environment(RecordingHistoryModel.self) private var history
    @State private var content = ""
    @State private var readError: String?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(recording.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                HStack {
                    Text(recording.startedAt.formatted(date: .long, time: .shortened))
                    if let end = recording.endedAt {
                        Text("· \(duration(end.timeIntervalSince(recording.startedAt)))")
                    }
                }.font(.caption).foregroundStyle(.secondary)
                if let modelID = recording.modelID {
                    Text(ModelCatalog.descriptor(for: modelID)?.displayName ?? modelID)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(recording.transcriptURL.path).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                HStack {
                    CopyTextButton("Copy transcript", text: content)
                        .disabled(loading || readError != nil)
                        .help("Copy the entire Markdown transcript, including speakers and timestamps.")
                    CopyTextButton("Copy full path", text: recording.transcriptURL.path)
                        .help("Copy the full path to the Markdown file.")
                    if let audio = recording.audioDirectory, FileManager.default.fileExists(atPath: audio.url.path) {
                        Button("Open audio folder") { NSWorkspace.shared.open(audio.url) }
                    }
                    if !recording.isAvailable {
                        Button("Locate transcript…") { Task { await history.locate(recording) } }
                    }
                }
            }.padding(20)
            Divider()
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let readError {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.folder").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Transcript unavailable").font(.headline)
                    Text(readError).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Locate transcript…") { Task { await history.locate(recording) } }
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if TranscriptDocument(content: content).bodyText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No speech transcribed").font(.headline)
                    Text("This meeting has no transcript text.")
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        let document = TranscriptDocument(content: content)
                        let lines = document.lines
                        if lines.isEmpty {
                            Text(document.bodyText).font(.body).textSelection(.enabled)
                        } else {
                            ForEach(lines) { line in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(line.speaker).fontWeight(.semibold)
                                        Text(line.timestamp).foregroundStyle(.secondary)
                                    }.font(.caption)
                                    Text(line.text).textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: recording) {
            loading = true
            content = ""
            readError = nil
            let url = recording.transcriptURL
            do {
                let text = try await Task.detached(priority: .userInitiated) { try String(contentsOf: url, encoding: .utf8) }.value
                try Task.checkCancellation()
                content = text
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                readError = "The file may have moved, or its drive may be disconnected. The recording remains in your library."
            }
            loading = false
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds)) / 60
        return minutes > 0 ? "\(minutes) min" : "\(max(0, Int(seconds))) sec"
    }
}

/// The confirmation reflects a successful pasteboard write and resets between meetings.
private struct CopyTextButton: View {
    let title: String
    let text: String
    @State private var copied = false

    init(_ title: String, text: String) {
        self.title = title
        self.text = text
    }

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            copied = NSPasteboard.general.setString(text, forType: .string)
        } label: {
            Label(copied ? "Copied" : title, systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .onChange(of: text) { _, _ in copied = false }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            copied = false
        }
    }
}
