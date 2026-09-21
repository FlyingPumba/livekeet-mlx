import Darwin
import Foundation

/// Keeps the optional Python speech model loaded across audio segments.
actor PythonSpeechRecognizer {
    struct Reply: Decodable { let ok: Bool?; let text: String?; let error: String? }
    private let process = Process()
    private let input: FileHandle
    private let output: FileHandle
    private var buffer = Data()

    init(modelID: String, python: String, scriptURL: URL? = nil) throws {
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("livekeet-mlx_LivekeetCore.bundle/Python/transcribe.py")
        let appScript = packaged.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        guard let script = scriptURL ?? appScript ?? Bundle.module.url(forResource: "transcribe", withExtension: "py", subdirectory: "Python") else {
            throw HelperError.failed("Python speech resources are missing from this installation.")
        }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [NSString(string: python).expandingTildeInPath, "-u", script.path, modelID]
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
        process.environment = environment
        let stdinPipe = Pipe(), stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.standardError
        input = stdinPipe.fileHandleForWriting
        output = stdoutPipe.fileHandleForReading
        _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
        try process.run()
    }

    func prepare() throws {
        guard try receive(timeout: 1800).ok == true else { throw HelperError.failed("Invalid speech-helper startup response.") }
    }

    func transcribe(samples: [Float]) throws -> String {
        guard process.isRunning else { throw HelperError.failed("The speech helper exited. Check the Python executable and speech dependencies.") }
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("livekeet-asr-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        try WAVWriter.write(samples: samples, to: wav)
        var request = try JSONSerialization.data(withJSONObject: ["op": "transcribe", "path": wav.path])
        request.append(10)
        try input.write(contentsOf: request)
        guard let text = try receive(timeout: 300).text else { throw HelperError.failed("Speech helper returned no transcript.") }
        return text
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
                throw HelperError.failed("Speech helper exited or timed out. Run scripts/setup-python.sh speech and select its Python executable in Advanced settings.")
            }
            guard buffer.count + data.count < 1_048_576 else { throw HelperError.failed("Invalid oversized speech-helper response.") }
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
