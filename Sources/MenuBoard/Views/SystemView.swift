import SwiftUI

struct SystemView: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                header
                cpuCard
                if let memory = stats.memory { memoryCard(memory) }
                if let disk = stats.disk { diskCard(disk) }
                if let battery = stats.battery { batteryCard(battery) }
            }
            .padding(10)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stats.hostName.isEmpty ? stats.modelName : stats.hostName)
                .font(.headline)
            Text("\(stats.chipName) · \(stats.coreCount) cores · \(stats.modelName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("macOS \(stats.osVersion) · up \(Format.duration(stats.uptime))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
    }

    private var cpuCard: some View {
        Card(title: "CPU", trailing: Format.percent(stats.cpu.total)) {
            MeterBar(fraction: stats.cpu.total, color: color(for: stats.cpu.total))
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(stats.cpu.perCore.enumerated()), id: \.offset) { _, load in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1.5).fill(.quaternary)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(color(for: load))
                            .frame(height: max(2, 20 * load))
                    }
                }
            }
            .frame(height: 20)
            StatRow(label: "Load average", value: stats.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: "  "))
            StatRow(label: "Thermal", value: thermalLabel)
        }
    }

    private func memoryCard(_ memory: MemorySample) -> some View {
        let total = Double(memory.total)
        return Card(title: "Memory", trailing: "\(Format.memory(memory.used)) / \(Format.memory(memory.total))") {
            MeterBar(segments: [
                .init(fraction: Double(memory.app) / total, color: .blue),
                .init(fraction: Double(memory.wired) / total, color: .orange),
                .init(fraction: Double(memory.compressed) / total, color: .purple),
            ])
            HStack(spacing: 10) {
                LegendDot(color: .blue, label: "App \(Format.memory(memory.app))")
                LegendDot(color: .orange, label: "Wired \(Format.memory(memory.wired))")
                LegendDot(color: .purple, label: "Compressed \(Format.memory(memory.compressed))")
            }
            StatRow(label: "Cached files", value: Format.memory(memory.cached))
            StatRow(label: "Swap used", value: "\(Format.memory(memory.swapUsed)) / \(Format.memory(memory.swapTotal))")
            HStack {
                Text("Pressure").foregroundStyle(.secondary)
                Spacer()
                Text(memory.pressure.label)
                    .foregroundStyle(memory.pressure == .normal ? Color.green : memory.pressure == .warning ? .yellow : .red)
            }
            .font(.caption)
        }
    }

    private func diskCard(_ disk: DiskSample) -> some View {
        let fraction = disk.total > 0 ? Double(disk.used) / Double(disk.total) : 0
        return Card(title: "Disk", trailing: "\(Format.file(disk.free)) free") {
            MeterBar(fraction: fraction, color: color(for: fraction))
            StatRow(label: "Used", value: "\(Format.file(disk.used)) of \(Format.file(disk.total))")
        }
    }

    private func batteryCard(_ battery: BatterySample) -> some View {
        let fraction = Double(battery.percent) / 100
        let status: String = {
            if battery.isCharging, let minutes = battery.minutesRemaining { return "Charging · \(Format.minutes(minutes)) to full" }
            if battery.isCharging { return "Charging" }
            if battery.onAC { return "Plugged in" }
            if let minutes = battery.minutesRemaining { return "\(Format.minutes(minutes)) remaining" }
            return "On battery"
        }()
        return Card(title: "Battery", trailing: "\(battery.percent)%") {
            MeterBar(fraction: fraction, color: battery.isCharging ? .green : fraction < 0.2 ? .red : .green)
            StatRow(label: "Status", value: status)
            if let cycles = battery.cycleCount {
                StatRow(label: "Cycle count", value: "\(cycles)")
            }
        }
    }

    private var thermalLabel: String {
        switch stats.thermalState {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    private func color(for fraction: Double) -> Color {
        fraction > 0.9 ? .red : fraction > 0.7 ? .orange : .accentColor
    }
}
