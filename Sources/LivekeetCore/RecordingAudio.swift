import AVFoundation
import Foundation

/// Streams full captured channels to WAV files without retaining a meeting in memory.
final class RecordingAudio {
    private var microphone: AVAudioFile?
    private var system: AVAudioFile?
    private let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!

    init(directory: URL, microphone: Bool, system: Bool) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        if microphone {
            self.microphone = try AVAudioFile(forWriting: directory.appendingPathComponent("microphone.wav"), settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        }
        if system {
            self.system = try AVAudioFile(forWriting: directory.appendingPathComponent("system.wav"), settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        }
    }

    func append(microphone: [Float], system: [Float]) throws {
        try append(microphone, to: self.microphone)
        try append(system, to: self.system)
    }

    private func append(_ samples: [Float], to file: AVAudioFile?) throws {
        guard let file, !samples.isEmpty else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let data = buffer.floatChannelData?[0] else { throw CocoaError(.fileWriteUnknown) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { data.update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
    }

    func finish() { microphone = nil; system = nil }
}
