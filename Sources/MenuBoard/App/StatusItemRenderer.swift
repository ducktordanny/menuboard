import AppKit

/// Builds the status item title: an SF Symbol plus value for each enabled metric.
enum StatusItemRenderer {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))

    static func title(stats: SystemStats, settings: MenuBarSettings) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for metric in settings.orderedMetrics {
            guard let piece = piece(for: metric, stats: stats) else { continue }
            if result.length > 0 { result.append(text("  ")) }
            if let image = NSImage(systemSymbolName: piece.symbol, accessibilityDescription: metric.title)?
                .withSymbolConfiguration(symbolConfiguration) {
                let attachment = NSTextAttachment()
                attachment.image = image
                let size = image.size
                attachment.bounds = CGRect(x: 0, y: (font.capHeight - size.height) / 2, width: size.width, height: size.height)
                result.append(NSAttributedString(attachment: attachment))
                result.append(text("\u{2009}"))
            }
            result.append(text(piece.value))
        }
        return result
    }

    private static func text(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font])
    }

    private static func piece(for metric: MenuBarMetric, stats: SystemStats) -> (symbol: String, value: String)? {
        switch metric {
        case .cpu:
            return ("cpu", Format.percent(stats.cpu.total))
        case .memory:
            guard let memory = stats.memory else { return nil }
            return ("memorychip", String(format: "%.1f GB", Double(memory.used) / 1_073_741_824))
        case .memoryPercent:
            guard let memory = stats.memory else { return nil }
            return ("memorychip", Format.percent(Double(memory.used) / Double(memory.total)))
        case .battery:
            guard let battery = stats.battery else { return nil }
            return (batterySymbol(battery), "\(battery.percent)%")
        case .disk:
            guard let disk = stats.disk else { return nil }
            return ("internaldrive", String(format: "%.0f GB", Double(disk.free) / 1_000_000_000))
        }
    }

    private static func batterySymbol(_ battery: BatterySample) -> String {
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
