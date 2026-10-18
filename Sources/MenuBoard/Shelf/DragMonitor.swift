import AppKit

/// Detects system-wide drag sessions. There is no public "drag began" notification, so this watches the
/// drag pasteboard's change count while the mouse is dragged; a new count means a new drag session.
final class DragMonitor {
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var monitors: [Any] = []
    private var lastChangeCount = NSPasteboard(name: .drag).changeCount
    private var isTracking = false

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event, local: false)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event, local: true)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handle(_ event: NSEvent, local: Bool) {
        switch event.type {
        case .leftMouseDragged:
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != lastChangeCount else { return }
            lastChangeCount = pasteboard.changeCount
            // Drags that start in one of our own windows (shelf rows) must not summon the drop zone.
            let isOwnDrag = local && event.window != nil
            guard !isOwnDrag, ShelfStore.canAccept(pasteboard: pasteboard) else { return }
            isTracking = true
            onDragBegan?()
        case .leftMouseUp:
            guard isTracking else { return }
            isTracking = false
            onDragEnded?()
        default:
            break
        }
    }
}
