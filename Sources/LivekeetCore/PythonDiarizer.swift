import Darwin
import Foundation

/// One serialized, persistent helper per session, keeping model loads off the audio loop.
actor PythonDiarizer {
    struct Turn: Decodable, Sendable { let start: Float; let end: Float; let speaker: Int }
    struct Reply: Decodable { let ok: Bool?; let speaker: Int?; let channels: [String: [Turn]]?; let error: String? }
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private var buffer = Data()
    private var failed = false

    init(config: LivekeetConfig, scriptURL: URL? = nil) throws {
        let appResource = Bundle.main.resourceURL?
            .appendingPathComponent("livekeet-mlx_LivekeetCore.bundle/Python/diarize.py")
        let bundledScript = appResource.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        guard let script = scriptURL ?? bundledScript ?? Bundle.module.url(forResource: "diarize", withExtension: "py", subdirectory: "Python") else {
            throw HelperError.failed("Python helper resources are missing from this installation.")
        }
        process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [NSString(string: config.pythonExecutable).expandingTildeInPath, "-u", script.path, config.diarizationEngine.rawValue]
        var env = ProcessInfo.processInfo.environment
        env["PYANNOTE_METRICS_ENABLED"] = "0"
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        if let token = config.pyannoteToken, !token.isEmpty { env["HF_TOKEN"] = token }
        process.environment = env
        let stdinPipe = Pipe(), stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.standardError
        input = stdinPipe.fileHandleForWriting
        output = stdoutPipe.fileHandleForReading
        // A helper can exit between isRunning and write; surface EPIPE instead of crashing the app.
        _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
        try process.run()
    }

    func prepare() throws {
        guard try receive(timeout: 300).ok == true else { throw HelperError.failed("Invalid speaker-helper startup response.") }
    }

    func identify(samples: [Float], channel: String) throws -> Int {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("livekeet-speaker-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: path) }
        try WAVWriter.write(samples: samples, to: path)
        return try request(["op": "identify", "path": path.path, "channel": channel]).speaker ?? 0
    }

    func diarize(channels: [String: (path: URL, count: Int)]) throws -> [String: [Turn]] {
        let sources = channels.mapValues { ["path": $0.path.path, "count": $0.count] as [String: Any] }
        return try request(["op": "diarize", "channels": sources]).channels ?? [:]
    }

    private func request(_ payload: [String: Any]) throws -> Reply {
        guard !failed, process.isRunning else { throw HelperError.failed("Speaker helper is unavailable.") }
        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(10)
        try input.write(contentsOf: data)
        return try receive(timeout: 300)
    }

    private func receive(timeout: TimeInterval) throws -> Reply {
        let child = process
        let watchdog = DispatchWorkItem { if child.isRunning { kill(child.processIdentifier, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer { watchdog.cancel() }
        while true {
            if let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                let reply = try JSONDecoder().decode(Reply.self, from: line)
                if let error = reply.error { throw HelperError.failed(error) }
                return reply
            }
            let data = output.availableData
            guard !data.isEmpty else {
                failed = true
                throw HelperError.failed("Speaker helper exited or timed out. Check the Python executable and optional dependencies.")
            }
            buffer.append(data)
        }
    }

    func stop() {
        try? input.close()
        if process.isRunning { process.terminate() }
    }

    deinit {
        try? input.close()
        if process.isRunning { process.terminate() }
    }

    enum HelperError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case .failed(let message) = self { return message }; return nil }
    }
}
