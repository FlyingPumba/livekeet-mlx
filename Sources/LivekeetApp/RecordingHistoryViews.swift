import AppKit
import LivekeetCore
import SwiftUI

struct RecordingHistorySidebar: View {
    @Environment(RecordingHistoryModel.self) private var history
    @Bindable var viewModel: TranscriptViewModel
    @Binding var selection: UUID?
    let newRecording: () -> Void

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
                ForEach(history.recordings) { recording in
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
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([recording.transcriptURL]) }
                            .disabled(!recording.isAvailable)
                        Button("Locate transcript…") { Task { await history.locate(recording) } }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if history.recordings.isEmpty {
                    Text("Your saved recordings will appear here, wherever you save them.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(20)
                }
            }
            Divider()
            HStack {
                Button("Import transcripts…") {
                    Task { if let id = await history.importTranscripts() { selection = id } }
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
                    Button("Open transcript") { NSWorkspace.shared.open(recording.transcriptURL) }
                        .disabled(!recording.isAvailable)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([recording.transcriptURL]) }
                        .disabled(!recording.isAvailable)
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
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        let lines = TranscriptDocument(content: content).lines
                        if lines.isEmpty {
                            Text(content).font(.body).textSelection(.enabled)
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
        .task(id: recording.transcriptURL) {
            loading = true
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
