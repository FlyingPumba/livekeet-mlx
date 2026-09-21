import LivekeetCore
import Sparkle
import SwiftUI

@main
struct LivekeetApp: App {
    @State private var settings = AppSettings()
    @State private var history = RecordingHistoryModel()
    @State private var transcript = TranscriptViewModel()
    private let updaterController: SPUStandardUpdaterController

    init() {
        // A UI smoke launch must not download models or contact the update feed.
        let smokeTest = CommandLine.arguments.contains("--smoke-test") || ProcessInfo.processInfo.environment["LIVEKEET_SMOKE_TEST"] == "1"
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !smokeTest,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Prewarm STT + diarization in the background so the first "Start Recording"
        // click is instant (or very close to it). Reads current settings via a fresh
        // AppSettings — UserDefaults-backed — and captures only the resulting values.
        if smokeTest { return }
        let bootstrap = AppSettings()
        let modelName = bootstrap.defaultModel
        let diarEnabled = !bootstrap.disableDiarization && bootstrap.diarizationEngine == "sortformer-v1"
        Task.detached(priority: .utility) {
            await ModelPrewarmer.shared.startPrewarm(
                sttModelName: modelName,
                diarization: diarEnabled
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(history)
                .environment(transcript)
        }
        .defaultSize(width: 1050, height: 650)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }

        Settings {
            SettingsView(updater: updaterController.updater)
                .environment(settings)
        }
    }
}

struct CheckForUpdatesView: View {
    @StateObject private var viewModel: CheckForUpdatesViewModel

    let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self._viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
