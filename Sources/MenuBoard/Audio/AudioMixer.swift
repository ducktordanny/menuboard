import AppKit
import CoreAudio
import Foundation
import UniformTypeIdentifiers

struct AudioApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let pid: pid_t
    var processObjectIDs: [AudioObjectID]
    var isPlaying: Bool
    var volume: Float
    var isMuted: Bool
}

final class AudioMixer: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var masterVolume: Float = 1
    @Published private(set) var masterMuted = false
    @Published private(set) var masterAvailable = false
    @Published private(set) var outputDeviceName = "Output"
    @Published private(set) var errorMessage: String?

    private enum Permission { case unknown, requesting, granted, denied }

    private static let volumesKey = "audio.volumes"
    private static let recentWindow: TimeInterval = 300

    private var taps: [String: AppAudioTap] = [:]
    private var savedVolumes: [String: Float]
    private var mutedIDs: Set<String> = []
    private var lastPlayed: [String: Date] = [:]
    private var permission = Permission.unknown
    private var timer: Timer?
    private var outputDevice = AudioObjectID.unknown
    private var outputDeviceUID: String?
    private lazy var genericIcon = NSWorkspace.shared.icon(for: .unixExecutable)

    init() {
        savedVolumes = (UserDefaults.standard.dictionary(forKey: Self.volumesKey) as? [String: Float]) ?? [:]
        outputDeviceChanged()

        AudioObjectID.system.addListener(kAudioHardwarePropertyProcessObjectList) { [weak self] _, _ in self?.refresh() }
        AudioObjectID.system.addListener(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] _, _ in self?.outputDeviceChanged() }
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func teardown() {
        taps.values.forEach { $0.tearDown() }
        taps.removeAll()
    }

    // MARK: Per-app controls

    func setVolume(_ volume: Float, for id: String) {
        let clamped = min(max(volume, 0), 1)
        if clamped >= 0.999 {
            savedVolumes[id] = nil
        } else {
            savedVolumes[id] = clamped
        }
        UserDefaults.standard.set(savedVolumes, forKey: Self.volumesKey)
        update(id) { $0.volume = clamped }
        reconcileTaps()
    }

    func setMuted(_ muted: Bool, for id: String) {
        if muted { mutedIDs.insert(id) } else { mutedIDs.remove(id) }
        update(id) { $0.isMuted = muted }
        reconcileTaps()
    }

    private func update(_ id: String, _ change: (inout AudioApp) -> Void) {
        guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
        change(&apps[index])
    }

    // MARK: Master controls

    func setMasterVolume(_ volume: Float) {
        masterVolume = volume
        OutputDevice.setVolume(volume, of: outputDevice)
    }

    func setMasterMuted(_ muted: Bool) {
        masterMuted = muted
        OutputDevice.setMuted(muted, of: outputDevice)
    }

    private func readMaster() {
        if let volume = OutputDevice.volume(of: outputDevice) {
            masterAvailable = true
            if abs(volume - masterVolume) > 0.005 { masterVolume = volume }
        } else {
            masterAvailable = false
        }
        let muted = OutputDevice.isMuted(outputDevice)
        if muted != masterMuted { masterMuted = muted }
    }

    private func outputDeviceChanged() {
        outputDevice = OutputDevice.defaultDevice()
        outputDeviceUID = OutputDevice.uid(of: outputDevice)
        outputDeviceName = OutputDevice.name(of: outputDevice)
        teardown()
        refresh()
    }

    // MARK: Refresh

    private func refresh() {
        readMaster()

        let selfPID = getpid()
        var groups: [pid_t: [AudioProcess]] = [:]
        for process in AudioProcesses.all() where process.pid != selfPID {
            let owner = ResponsiblePID.of(process.pid)
            guard owner != selfPID else { continue }
            groups[owner, default: []].append(process)
        }

        let now = Date()
        var byID: [String: AudioApp] = [:]
        for (owner, members) in groups {
            let running = NSRunningApplication(processIdentifier: owner)
            let id = running?.bundleIdentifier ?? members.first?.bundleID ?? "pid:\(owner)"
            let isPlaying = members.contains { $0.isRunningOutput }
            if isPlaying { lastPlayed[id] = now }

            let recentlyPlayed = lastPlayed[id].map { now.timeIntervalSince($0) < Self.recentWindow } ?? false
            let volume = savedVolumes[id] ?? 1
            let isMuted = mutedIDs.contains(id)
            guard isPlaying || recentlyPlayed || volume < 1 || isMuted else { continue }

            let objectIDs = members.map(\.objectID)
            if var existing = byID[id] {
                existing.processObjectIDs.append(contentsOf: objectIDs)
                existing.isPlaying = existing.isPlaying || isPlaying
                byID[id] = existing
            } else {
                byID[id] = AudioApp(
                    id: id,
                    name: running?.localizedName ?? ProcessNames.name(of: owner) ?? id,
                    icon: running?.icon ?? genericIcon,
                    pid: owner,
                    processObjectIDs: objectIDs,
                    isPlaying: isPlaying,
                    volume: volume,
                    isMuted: isMuted
                )
            }
        }

        apps = byID.values.sorted {
            ($0.isPlaying ? 0 : 1, $0.name.lowercased()) < ($1.isPlaying ? 0 : 1, $1.name.lowercased())
        }
        reconcileTaps()
    }

    // MARK: Taps

    private func reconcileTaps() {
        guard let outputDeviceUID else { return }
        let wanted = apps.filter { $0.isMuted || $0.volume < 0.999 }

        if !wanted.isEmpty, permission == .unknown {
            permission = .requesting
            AudioCapturePermission.request { [weak self] granted in
                guard let self else { return }
                self.permission = granted ? .granted : .denied
                self.reconcileTaps()
            }
        }
        guard permission != .requesting else { return }

        var keep = Set<String>()
        for app in wanted {
            keep.insert(app.id)
            // Squared slider position tracks perceived loudness better than linear gain.
            let gain = app.isMuted ? 0 : app.volume * app.volume
            if let tap = taps[app.id], tap.processObjectIDs == Set(app.processObjectIDs) {
                tap.gain = gain
                continue
            }
            taps[app.id]?.tearDown()
            do {
                taps[app.id] = try AppAudioTap(processObjectIDs: app.processObjectIDs, outputDeviceUID: outputDeviceUID, gain: gain)
                errorMessage = nil
            } catch {
                taps[app.id] = nil
                errorMessage = "\(app.name): \(error)"
            }
        }
        for (id, tap) in taps where !keep.contains(id) {
            tap.tearDown()
            taps[id] = nil
        }
        if permission == .denied {
            errorMessage = "System Audio Recording permission is required for per-app volume."
        }
    }
}
