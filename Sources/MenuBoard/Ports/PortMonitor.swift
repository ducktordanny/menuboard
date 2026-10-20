import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

struct ListeningPort: Identifiable, Hashable {
    let port: UInt16
    let pid: pid_t
    let processName: String
    let appName: String?
    let icon: NSImage
    let hasIPv4: Bool
    let hasIPv6: Bool
    let loopbackOnly: Bool

    var id: String { "\(pid):\(port)" }
    var url: URL { URL(string: "http://localhost:\(port)")! }

    var detail: String {
        var parts = ["pid \(pid)", loopbackOnly ? "localhost only" : "all interfaces"]
        parts.append([hasIPv4 ? "IPv4" : nil, hasIPv6 ? "IPv6" : nil].compactMap { $0 }.joined(separator: " + "))
        return parts.joined(separator: " · ")
    }
}

/// Listening TCP sockets of the current user's processes, read through libproc (no lsof, ~3 ms).
final class PortMonitor: ObservableObject {
    @Published private(set) var ports: [ListeningPort] = []
    @Published private(set) var lastRefresh: Date?

    private var timer: Timer?
    private let queue = DispatchQueue(label: "menuboard.ports", qos: .utility)
    private var iconCache: [pid_t: NSImage] = [:]
    private lazy var genericIcon = NSWorkspace.shared.icon(for: .unixExecutable)

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        queue.async { [weak self] in
            let sockets = Self.listeningSockets()
            DispatchQueue.main.async { self?.publish(sockets) }
        }
    }

    func terminate(_ entry: ListeningPort, force: Bool) {
        kill(entry.pid, force ? SIGKILL : SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refresh() }
    }

    // MARK: Enumeration

    private struct RawSocket {
        let pid: pid_t
        let port: UInt16
        let isIPv6: Bool
        let isLoopback: Bool
    }

    private func publish(_ sockets: [RawSocket]) {
        var grouped: [String: (pid: pid_t, port: UInt16, v4: Bool, v6: Bool, loopback: Bool)] = [:]
        for socket in sockets {
            let key = "\(socket.pid):\(socket.port)"
            var entry = grouped[key] ?? (socket.pid, socket.port, false, false, true)
            if socket.isIPv6 { entry.v6 = true } else { entry.v4 = true }
            entry.loopback = entry.loopback && socket.isLoopback
            grouped[key] = entry
        }

        var livePIDs = Set<pid_t>()
        let result = grouped.values.map { entry -> ListeningPort in
            livePIDs.insert(entry.pid)
            let owner = ResponsiblePID.of(entry.pid)
            let app = NSRunningApplication(processIdentifier: owner)
            let processName = ProcessNames.name(of: entry.pid) ?? "pid \(entry.pid)"
            let appName = app?.localizedName.flatMap { $0 == processName ? nil : $0 }
            let icon = iconCache[entry.pid] ?? app?.icon ?? genericIcon
            iconCache[entry.pid] = icon
            return ListeningPort(
                port: entry.port, pid: entry.pid, processName: processName, appName: appName, icon: icon,
                hasIPv4: entry.v4, hasIPv6: entry.v6, loopbackOnly: entry.loopback
            )
        }
        iconCache = iconCache.filter { livePIDs.contains($0.key) }
        ports = result.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
        lastRefresh = Date()
    }

    private static func listeningSockets() -> [RawSocket] {
        var result: [RawSocket] = []
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))

        let fdStride = MemoryLayout<proc_fdinfo>.stride
        let socketSize = Int32(MemoryLayout<socket_fdinfo>.size)
        for pid in pids.prefix(Int(max(filled, 0))) where pid > 0 {
            let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard size > 0 else { continue }
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / fdStride)
            let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, size)
            for fd in fds.prefix(Int(max(got, 0)) / fdStride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
                var info = socket_fdinfo()
                guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, socketSize) == socketSize,
                      info.psi.soi_kind == SOCKINFO_TCP else { continue }
                let tcp = info.psi.soi_proto.pri_tcp
                guard tcp.tcpsi_state == TSI_S_LISTEN else { continue }

                let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport))
                let isIPv6 = (tcp.tcpsi_ini.insi_vflag & UInt8(INI_IPV6)) != 0
                let isLoopback: Bool
                if isIPv6 {
                    var address = tcp.tcpsi_ini.insi_laddr.ina_6
                    let bytes = withUnsafeBytes(of: &address) { Array($0) }
                    isLoopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
                } else {
                    isLoopback = tcp.tcpsi_ini.insi_laddr.ina_46.i46a_addr4.s_addr == 0x0100_007f
                }
                result.append(RawSocket(pid: pid, port: port, isIPv6: isIPv6, isLoopback: isLoopback))
            }
        }
        return result
    }
}
