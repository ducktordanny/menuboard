import Combine
import Foundation

enum Tab: String, CaseIterable, Identifiable {
    case system, memory, audio, shelf, clipboard, keyboard, ports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .memory: "Memory"
        case .audio: "Audio"
        case .shelf: "Shelf"
        case .clipboard: "Clips"
        case .keyboard: "Keys"
        case .ports: "Ports"
        }
    }
}

final class AppState: ObservableObject {
    @Published var tab: Tab = .system {
        didSet {
            showSettings = false
            if isVisible { activate(tab) }
        }
    }
    @Published var showSettings = false

    private static let tabOrderKey = "tabs.order"

    @Published var tabOrder: [Tab] {
        didSet { UserDefaults.standard.set(tabOrder.map(\.rawValue), forKey: Self.tabOrderKey) }
    }

    init() {
        let saved = (UserDefaults.standard.stringArray(forKey: Self.tabOrderKey) ?? []).compactMap(Tab.init(rawValue:))
        tabOrder = saved + Tab.allCases.filter { !saved.contains($0) }
    }

    func moveTab(_ tab: Tab, by offset: Int) {
        guard let index = tabOrder.firstIndex(of: tab), tabOrder.indices.contains(index + offset) else { return }
        tabOrder.swapAt(index, index + offset)
    }

    let system = SystemStats()
    let processes = ProcessMemoryMonitor()
    let audio = AudioMixer()
    let shelf = ShelfStore()
    let clipboard = ClipboardStore()
    let menuBar = MenuBarSettings()
    let keys = KeyRemapper()
    let hyper = HyperKey()
    let ports = PortMonitor()
    let keepAwake = KeepAwake()

    private var isVisible = false

    func popoverDidShow() {
        isVisible = true
        activate(tab)
    }

    func popoverDidClose() {
        isVisible = false
        stopAll()
    }

    private func activate(_ tab: Tab) {
        stopAll()
        switch tab {
        case .system: system.start()
        case .memory: processes.start()
        case .audio: audio.start()
        case .ports: ports.start()
        case .shelf, .clipboard, .keyboard: break
        }
    }

    private func stopAll() {
        system.stop()
        processes.stop()
        audio.stop()
        ports.stop()
    }
}
