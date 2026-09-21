import AudioToolbox
import CoreAudio
import Foundation

public struct AudioInputDevice: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let isDefault: Bool
    let objectID: AudioDeviceID

    public init(id: String, name: String, isDefault: Bool, objectID: AudioDeviceID = 0) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.objectID = objectID
    }

    public static func available() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        address.mSelector = kAudioHardwarePropertyDefaultInputDevice
        var defaultID: AudioDeviceID = 0
        size = UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultID)
        return ids.compactMap { id in
            var input = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                  mScope: kAudioDevicePropertyScopeInput,
                                                  mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &input, 0, nil, &bytes) == noErr, bytes > 0,
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, on: id),
                  let name = stringProperty(kAudioObjectPropertyName, on: id) else { return nil }
            return AudioInputDevice(id: uid, name: name, isDefault: id == defaultID, objectID: id)
        }
    }

    public static func resolve(_ selection: String, in devices: [AudioInputDevice]) throws -> AudioInputDevice {
        let query = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exactID = devices.first(where: { $0.id == query }) { return exactID }
        if let index = Int(query) {
            guard devices.indices.contains(index) else { throw SelectionError.notFound(query) }
            return devices[index]
        }
        let exact = devices.filter { $0.name.caseInsensitiveCompare(query) == .orderedSame }
        let matches = exact.isEmpty ? devices.filter { $0.name.localizedCaseInsensitiveContains(query) } : exact
        guard !query.isEmpty, !matches.isEmpty else { throw SelectionError.notFound(query) }
        guard matches.count == 1 else { throw SelectionError.ambiguous(query, matches.map(\.name)) }
        return matches[0]
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, on id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        var result: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &result) == noErr else { return nil }
        return result as String
    }

    public enum SelectionError: LocalizedError {
        case notFound(String), ambiguous(String, [String]), unavailable(OSStatus)
        public var errorDescription: String? {
            switch self {
            case .notFound(let query): return "No microphone matches '\(query)'. Run livekeet --devices."
            case .ambiguous(let query, let names): return "Multiple microphones match '\(query)': \(names.joined(separator: ", ")). Use a device index or UID."
            case .unavailable(let status): return "Could not select microphone (Core Audio error \(status))."
            }
        }
    }
}
