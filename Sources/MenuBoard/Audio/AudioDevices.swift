import CoreAudio
import Foundation

struct AudioProcess {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let isRunningOutput: Bool
}

enum AudioProcesses {
    static func all() -> [AudioProcess] {
        let ids: [AudioObjectID] = (try? AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList)) ?? []
        return ids.compactMap { id in
            guard let pid: pid_t = try? id.read(kAudioProcessPropertyPID, initial: 0) else { return nil }
            let bundleID = try? id.readString(kAudioProcessPropertyBundleID)
            let running: UInt32 = (try? id.read(kAudioProcessPropertyIsRunningOutput, initial: 0)) ?? 0
            return AudioProcess(
                objectID: id,
                pid: pid,
                bundleID: bundleID.flatMap { $0.isEmpty ? nil : $0 },
                isRunningOutput: running != 0
            )
        }
    }
}

enum OutputDevice {
    private static let output = kAudioObjectPropertyScopeOutput

    static func defaultDevice() -> AudioObjectID {
        (try? AudioObjectID.system.read(kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID.unknown)) ?? .unknown
    }

    static func uid(of device: AudioObjectID) -> String? {
        try? device.readString(kAudioDevicePropertyDeviceUID)
    }

    static func name(of device: AudioObjectID) -> String {
        (try? device.readString(kAudioObjectPropertyName)) ?? "Output"
    }

    static func volume(of device: AudioObjectID) -> Float? {
        if device.hasProperty(kAudioDevicePropertyVolumeScalar, scope: output),
           let main: Float32 = try? device.read(kAudioDevicePropertyVolumeScalar, scope: output, initial: 0) {
            return main
        }
        let channels = [1, 2].compactMap { channel -> Float32? in
            try? device.read(kAudioDevicePropertyVolumeScalar, scope: output, element: AudioObjectPropertyElement(channel), initial: 0)
        }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Float(channels.count)
    }

    static func setVolume(_ volume: Float, of device: AudioObjectID) {
        let clamped = Float32(min(max(volume, 0), 1))
        if device.isSettable(kAudioDevicePropertyVolumeScalar, scope: output) {
            try? device.write(kAudioDevicePropertyVolumeScalar, scope: output, value: clamped)
            return
        }
        for channel in 1...2 {
            try? device.write(kAudioDevicePropertyVolumeScalar, scope: output, element: AudioObjectPropertyElement(channel), value: clamped)
        }
    }

    static func isMuted(_ device: AudioObjectID) -> Bool {
        let muted: UInt32 = (try? device.read(kAudioDevicePropertyMute, scope: output, initial: 0)) ?? 0
        return muted != 0
    }

    static func setMuted(_ muted: Bool, of device: AudioObjectID) {
        let value: UInt32 = muted ? 1 : 0
        if device.isSettable(kAudioDevicePropertyMute, scope: output) {
            try? device.write(kAudioDevicePropertyMute, scope: output, value: value)
            return
        }
        for channel in 1...2 {
            try? device.write(kAudioDevicePropertyMute, scope: output, element: AudioObjectPropertyElement(channel), value: value)
        }
    }
}
