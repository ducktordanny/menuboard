import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

struct AppMemory: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage
    let footprint: UInt64
    let processCount: Int
    let isApplication: Bool
}

/// Per-app physical memory footprint (same metric Activity Monitor's "Memory" column uses),
/// grouped by the responsible app. Only processes owned by the current user are readable.
final class ProcessMemoryMonitor: ObservableObject {
    @Published private(set) var apps: [AppMemory] = []
    @Published private(set) var totalFootprint: UInt64 = 0

    private var timer: Timer?
    private var iconCache: [pid_t: NSImage] = [:]
    private lazy var genericIcon = NSWorkspace.shared.icon(for: .unixExecutable)

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        var footprints: [pid_t: (bytes: UInt64, count: Int)] = [:]
        for pid in Self.allPIDs() {
            guard let footprint = Self.footprint(of: pid) else { continue }
            let owner = ResponsiblePID.of(pid)
            footprints[owner, default: (0, 0)].bytes += footprint
            footprints[owner, default: (0, 0)].count += 1
        }

        var livePIDs = Set<pid_t>()
        var result: [AppMemory] = []
        for (pid, entry) in footprints where entry.bytes > 0 {
            livePIDs.insert(pid)
            let running = NSRunningApplication(processIdentifier: pid)
            let name = running?.localizedName ?? ProcessNames.name(of: pid) ?? "PID \(pid)"
            let icon = iconCache[pid] ?? running?.icon ?? genericIcon
            iconCache[pid] = icon
            result.append(AppMemory(
                id: pid,
                name: name,
                icon: icon,
                footprint: entry.bytes,
                processCount: entry.count,
                isApplication: running != nil
            ))
        }

        iconCache = iconCache.filter { livePIDs.contains($0.key) }
        apps = result.sorted { $0.footprint > $1.footprint }
        totalFootprint = result.reduce(0) { $0 + $1.footprint }
    }

    private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        return pids.prefix(Int(max(filled, 0))).filter { $0 > 0 }
    }

    private static func footprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        // libproc declares the buffer as `rusage_info_t *` (a `void **`) but actually fills the struct.
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        return info.ri_phys_footprint
    }
}
