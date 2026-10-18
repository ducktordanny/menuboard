import Combine
import Foundation

enum Tab: String, CaseIterable, Identifiable {
    case system, memory, audio, shelf, clipboard, keyboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .memory: "Memory"
        case .audio: "Audio"
        case .shelf: "Shelf"
        case .clipboard: "Clips"
        case .keyboard: "Keys"
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

    let system = SystemStats()
    let processes = ProcessMemoryMonitor()
    let audio = AudioMixer()
    let shelf = ShelfStore()
    let clipboard = ClipboardStore()
    let menuBar = MenuBarSettings()
    let keys = KeyRemapper()
    let hyper = HyperKey()

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
        case .shelf, .clipboard, .keyboard: break
        }
    }

    private func stopAll() {
        system.stop()
        processes.stop()
        audio.stop()
    }
}
