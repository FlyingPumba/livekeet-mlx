import Foundation

public enum DiarizationHelperSetup {
    public static func managedPython(for engine: DiarizationEngine) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/livekeet/diarization/\(engine.rawValue)/bin/python")
    }

    public static func executable(for engine: DiarizationEngine, fallback: String) -> String {
        let managed = managedPython(for: engine).path
        return FileManager.default.isExecutableFile(atPath: managed) ? managed : fallback
    }

    public static func isInstalled(_ engine: DiarizationEngine) -> Bool {
        FileManager.default.isExecutableFile(atPath: managedPython(for: engine).path)
    }

    public static func install(_ engine: DiarizationEngine) async throws {
        guard engine.needsPython else { return }
        try await Task.detached(priority: .utility) {
            let appResource = Bundle.main.resourceURL?.appendingPathComponent("livekeet-mlx_LivekeetCore.bundle/Python/setup_diarization.py")
            let script = appResource.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                ?? Bundle.module.url(forResource: "setup_diarization", withExtension: "py", subdirectory: "Python")
            guard let script else { throw SetupError.failed("Local speaker installer is missing from this installation.") }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [script.path, engine.rawValue]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw SetupError.failed("Could not install speaker support. " + String(decoding: output.suffix(3000), as: UTF8.self))
            }
        }.value
    }

    enum SetupError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case .failed(let message) = self { return message }; return nil }
    }
}
