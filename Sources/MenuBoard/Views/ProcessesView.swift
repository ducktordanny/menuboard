import AppKit
import SwiftUI

struct ProcessesView: View {
    @ObservedObject var monitor: ProcessMemoryMonitor

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(monitor.apps.count) apps · your processes")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Format.memory(monitor.totalFootprint))
                    .monospacedDigit()
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if monitor.apps.isEmpty {
                EmptyState(systemImage: "memorychip", title: "Sampling…", detail: "Per-app memory footprint appears here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(monitor.apps) { app in
                            ProcessRow(app: app, maxFootprint: monitor.apps.first?.footprint ?? 1)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }
}

private struct ProcessRow: View {
    let app: AppMemory
    let maxFootprint: UInt64

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(app.name).lineLimit(1)
                    if app.processCount > 1 {
                        Text("×\(app.processCount)")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.callout)
                MeterBar(fraction: Double(app.footprint) / Double(max(maxFootprint, 1)))
            }
            Text(Format.memory(app.footprint))
                .font(.callout)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            if let running = NSRunningApplication(processIdentifier: app.id) {
                Button("Quit \(app.name)") { running.terminate() }
                Button("Force Quit \(app.name)") { running.forceTerminate() }
                Divider()
            }
            Button("Copy PID \(app.id)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(app.id), forType: .string)
            }
        }
    }
}
