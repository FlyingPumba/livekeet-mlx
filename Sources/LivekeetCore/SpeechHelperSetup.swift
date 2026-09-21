import Foundation

/// Installs optional, local speech dependencies only when explicitly requested.
public enum SpeechHelperSetup {
    private static let packages = ["torch>=2.5", "transformers>=5.8,<6", "numpy<2.5", "soundfile", "librosa", "sentencepiece", "protobuf", "mistral-common[audio]>=1.8.1"]

    public static func install() async throws -> String {
        try await Task.detached(priority: .utility) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let candidates = ["/opt/homebrew/bin/uv", "/usr/local/bin/uv", home.appendingPathComponent(".local/bin/uv").path]
            guard let uv = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                throw SetupError.failed("Install uv from https://docs.astral.sh/uv/ and try again, or run scripts/setup-python.sh speech from the project.")
            }
            let environment = home.appendingPathComponent(".local/share/livekeet/python")
            let python = environment.appendingPathComponent("bin/python").path
            if !FileManager.default.isExecutableFile(atPath: python) {
                try run(uv, ["venv", "--python", "3.12", environment.path])
            }
            try run(uv, ["pip", "install", "--python", python] + packages)
            return python
        }.value
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // Drain while the installer runs so a full pipe cannot block the child.
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let details = String(decoding: output.suffix(3000), as: UTF8.self)
            throw SetupError.failed("Could not install local speech support. \(details)")
        }
    }

    enum SetupError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case .failed(let message) = self { return message }; return nil }
    }
}
