import AppKit
import LivekeetCore
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class RecordingHistoryModel {
    var recordings: [Recording] = []
    var errorMessage: String?
    private let library = RecordingLibrary.shared

    func refresh(discovering folder: String? = nil) async {
        do {
            if let folder {
                let url = URL(fileURLWithPath: NSString(string: folder).expandingTildeInPath)
                if FileManager.default.fileExists(atPath: url.path) { try await library.discover(in: url) }
            }
            recordings = try await library.recordings()
            errorMessage = nil
        } catch { errorMessage = "Could not read recording history: \(error.localizedDescription)" }
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
