import Combine
import Foundation
import SwiftUI

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpu, memory, memoryPercent, battery, disk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU usage"
        case .memory: "Memory used"
        case .memoryPercent: "Memory %"
        case .battery: "Battery"
        case .disk: "Disk free"
        }
    }
}

final class MenuBarSettings: ObservableObject {
    private static let iconKey = "menubar.showIcon"
    private static let metricsKey = "menubar.metrics"

    @Published var showIcon: Bool {
        didSet { UserDefaults.standard.set(showIcon, forKey: Self.iconKey) }
    }

    @Published var metrics: Set<MenuBarMetric> {
        didSet { UserDefaults.standard.set(metrics.map(\.rawValue).sorted(), forKey: Self.metricsKey) }
    }

    init() {
        showIcon = UserDefaults.standard.object(forKey: Self.iconKey) as? Bool ?? true
        let saved = UserDefaults.standard.stringArray(forKey: Self.metricsKey) ?? []
        metrics = Set(saved.compactMap(MenuBarMetric.init(rawValue:)))
    }

    var hasMetrics: Bool { !metrics.isEmpty }

    var orderedMetrics: [MenuBarMetric] { MenuBarMetric.allCases.filter(metrics.contains) }

    func isEnabled(_ metric: MenuBarMetric) -> Bool { metrics.contains(metric) }

    func toggle(_ metric: MenuBarMetric) {
        if metrics.contains(metric) { metrics.remove(metric) } else { metrics.insert(metric) }
    }

    func binding(for metric: MenuBarMetric) -> Binding<Bool> {
        Binding(
            get: { self.metrics.contains(metric) },
            set: { enabled in if enabled { self.metrics.insert(metric) } else { self.metrics.remove(metric) } }
        )
    }
}
