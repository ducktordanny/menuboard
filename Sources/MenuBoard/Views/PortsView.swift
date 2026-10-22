import AppKit
import SwiftUI

struct PortsView: View {
    @ObservedObject var monitor: PortMonitor
    @AppStorage("ports.filter") private var filterSpec = ""
    @AppStorage("ports.filterEnabled") private var filterEnabled = true

    private var filter: PortFilter { PortFilter(filterSpec) }
    private var isFiltering: Bool { filterEnabled && !filter.isEmpty }

    private var visible: [ListeningPort] {
        guard isFiltering else { return monitor.ports }
        let filter = filter
        return monitor.ports.filter { filter.matches($0.port) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    filterEnabled.toggle()
                } label: {
                    Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .foregroundStyle(isFiltering ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(filterEnabled ? "Show all ports" : "Apply filter")
                TextField("Filter ports, e.g. 3000-3999, 5173, 8080", text: $filterSpec)
                    .textFieldStyle(.plain)
                    .foregroundStyle(filterEnabled ? .primary : .secondary)
                if !filter.invalidTokens.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Ignored: \(filter.invalidTokens.joined(separator: ", "))")
                }
                if !filterSpec.isEmpty {
                    Button {
                        filterSpec = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            HStack {
                Text(isFiltering
                     ? "\(visible.count) of \(monitor.ports.count) listening · filtered"
                     : "\(monitor.ports.count) listening · your processes")
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

            if visible.isEmpty {
                EmptyState(
                    systemImage: "network",
                    title: monitor.lastRefresh == nil ? "Scanning…" : (monitor.ports.isEmpty ? "Nothing is listening" : "No matching ports"),
                    detail: monitor.ports.isEmpty
                        ? "TCP ports opened by your processes show up here. Root-owned servers are not visible."
                        : "\(monitor.ports.count) ports hidden by the filter."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(visible) { entry in
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
