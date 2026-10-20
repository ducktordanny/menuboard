import AppKit
import SwiftUI

struct PortsView: View {
    @ObservedObject var monitor: PortMonitor

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(monitor.ports.count) listening · your processes")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    monitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if monitor.ports.isEmpty {
                EmptyState(
                    systemImage: "network",
                    title: monitor.lastRefresh == nil ? "Scanning…" : "Nothing is listening",
                    detail: "TCP ports opened by your processes show up here. Root-owned servers are not visible."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(monitor.ports) { entry in
                            PortRow(entry: entry, monitor: monitor)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }
}

private struct PortRow: View {
    let entry: ListeningPort
    let monitor: PortMonitor
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(":\(String(entry.port))")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(width: 64, alignment: .leading)
            Image(nsImage: entry.icon)
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entry.processName).font(.callout).lineLimit(1)
                    if let app = entry.appName {
                        Text("· \(app)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Text(entry.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                NSWorkspace.shared.open(entry.url)
            } label: {
                Image(systemName: "safari").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open http://localhost:\(String(entry.port))")
            Button {
                monitor.terminate(entry, force: false)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Quit \(entry.processName)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Open in Browser") { NSWorkspace.shared.open(entry.url) }
            Button("Copy URL") { copy(entry.url.absoluteString) }
            Button("Copy Port") { copy(String(entry.port)) }
            Button("Copy PID") { copy(String(entry.pid)) }
            Divider()
            Button("Quit \(entry.processName)") { monitor.terminate(entry, force: false) }
            Button("Force Kill \(entry.processName)") { monitor.terminate(entry, force: true) }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
