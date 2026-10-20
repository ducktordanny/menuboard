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
    private static let orderKey = "menubar.order"

    @Published var showIcon: Bool {
        didSet { UserDefaults.standard.set(showIcon, forKey: Self.iconKey) }
    }

    @Published var metrics: Set<MenuBarMetric> {
        didSet { UserDefaults.standard.set(metrics.map(\.rawValue).sorted(), forKey: Self.metricsKey) }
    }

    /// Display order of all metrics, enabled or not; the readout shows the enabled ones in this order.
    @Published var order: [MenuBarMetric] {
        didSet { UserDefaults.standard.set(order.map(\.rawValue), forKey: Self.orderKey) }
    }

    init() {
        showIcon = UserDefaults.standard.object(forKey: Self.iconKey) as? Bool ?? true
        let saved = UserDefaults.standard.stringArray(forKey: Self.metricsKey) ?? []
        metrics = Set(saved.compactMap(MenuBarMetric.init(rawValue:)))
        let savedOrder = (UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []).compactMap(MenuBarMetric.init(rawValue:))
        order = savedOrder + MenuBarMetric.allCases.filter { !savedOrder.contains($0) }
    }

    var hasMetrics: Bool { !metrics.isEmpty }

    var orderedMetrics: [MenuBarMetric] { order.filter(metrics.contains) }

    func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }

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
