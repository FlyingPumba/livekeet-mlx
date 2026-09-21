import AppKit
import LivekeetCore
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class RecordingHistoryModel {
    var recordings: [Recording] = []
    var projects: [RecordingProject] = []
    var movingRecordingID: UUID?
    var errorMessage: String?
    private let library = RecordingLibrary.shared

    func refresh(discovering folder: String? = nil) async {
        do {
            projects = try await library.projects()
            var folders = projects.filter(\.isAvailable).map(\.folderURL)
            if let folder {
                let url = URL(fileURLWithPath: NSString(string: folder).expandingTildeInPath)
                if FileManager.default.fileExists(atPath: url.path) { folders.append(url) }
            }
            var errors: [String] = []
            for url in Set(folders) {
                do { try await library.discover(in: url) }
                catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            recordings = try await library.recordings()
            errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
        } catch { errorMessage = "Could not read recording history: \(error.localizedDescription)" }
    }

    func recordings(in projectID: UUID?) -> [Recording] {
        guard let projectID else { return recordings }
        guard let project = projects.first(where: { $0.id == projectID }) else { return [] }
        return recordings.filter(project.contains)
    }

    func saveProject(_ project: RecordingProject?, name: String, folder: URL) async throws -> UUID {
        let id: UUID
        if let project {
            try await library.renameProject(id: project.id, name: name)
            id = project.id
        } else {
            id = try await library.createProject(name: name, folder: folder).id
        }
        await refresh()
        return id
    }

    func removeProject(_ project: RecordingProject) async -> Bool {
        do {
            try await library.removeProject(id: project.id)
            await refresh()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func move(_ recording: Recording, to project: RecordingProject) async {
        guard movingRecordingID == nil else { return }
        movingRecordingID = recording.id
        defer { movingRecordingID = nil }
        do {
            try await library.moveRecording(id: recording.id, toProject: project.id)
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func importTranscripts() async -> UUID? {
        let panel = NSOpenPanel()
        panel.title = "Add Livekeet transcripts to your recordings"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return nil }
        var lastID: UUID?
        var errors: [String] = []
        for url in panel.urls {
            do { lastID = try await library.importTranscript(url).id }
            catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        await refresh()
        if !errors.isEmpty { errorMessage = errors.joined(separator: "\n") }
        return lastID
    }

    func locate(_ recording: Recording) async {
        let panel = NSOpenPanel()
        panel.title = "Locate \(recording.transcriptURL.lastPathComponent)"
        panel.message = "Choose this recording’s transcript at its new location."
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try await library.locate(id: recording.id, transcript: url)
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }
}
