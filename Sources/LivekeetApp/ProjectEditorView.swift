import AppKit
import LivekeetCore
import SwiftUI

struct ProjectEditorView: View {
    let project: RecordingProject?
    let onSaved: (UUID) -> Void
    @Environment(RecordingHistoryModel.self) private var history
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var chosenFolder: URL?
    @State private var errorMessage: String?
    @State private var saving = false

    init(project: RecordingProject?, onSaved: @escaping (UUID) -> Void) {
        self.project = project
        self.onSaved = onSaved
        _name = State(initialValue: project?.name ?? "")
        _chosenFolder = State(initialValue: project?.folderURL)
    }

    private var folder: URL {
        chosenFolder ?? RecordingProject.suggestedFolder(name: name, base: URL(fileURLWithPath: settings.resolvedOutputDirectory))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(project == nil ? "New project" : "Rename project").font(.title2.weight(.semibold))
            TextField("Project name", text: $name).textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 8) {
                Label("Recordings folder", systemImage: "folder").font(.headline)
                Text(folder.path).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    .lineLimit(3).truncationMode(.middle)
                if project == nil {
                    HStack {
                        Button("Choose folder…") { chooseFolder() }
                        if chosenFolder != nil { Button("Use suggested folder") { chosenFolder = nil } }
                    }
                    Text("All recordings in this folder belong to the project. Existing Livekeet transcripts will appear automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Renaming the project keeps its recordings in this folder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(project == nil ? "Create project" : "Save") {
                    saving = true
                    Task {
                        do {
                            let id = try await history.saveProject(project, name: name, folder: folder)
                            onSaved(id)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                        saving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }
        }.padding(24).frame(width: 450).disabled(saving)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose the project’s recordings folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder.deletingLastPathComponent()
        if panel.runModal() == .OK { chosenFolder = panel.url }
    }
}
