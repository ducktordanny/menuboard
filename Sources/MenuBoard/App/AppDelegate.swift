import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private static var instance: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        instance = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private let state = AppState()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let dragMonitor = DragMonitor()
    private var dropPanel: DropPanelController?
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        guard let button = item.button else { return }

        button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "MenuBoard")
        button.target = self
        button.action = #selector(togglePopover)

        let dropView = StatusItemDropView(frame: button.bounds)
        dropView.autoresizingMask = [.width, .height]
        dropView.canAccept = { [weak self] info in self?.state.shelf.canAccept(info) ?? false }
        dropView.onDragEntered = { [weak self] in self?.showPopover(tab: .shelf) }
        dropView.onDrop = { [weak self] info in self?.state.shelf.importDrop(info) ?? false }
        dropView.onRightClick = { [weak self] in self?.showContextMenu() }
        button.addSubview(dropView)

        let host = ShelfDropHostingView(rootView: RootView().environmentObject(state))
        // Fixed size up front; letting SwiftUI resize the popover after it is shown pushes it off-screen.
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: RootView.size)
        host.canAccept = { [weak self] info in self?.state.shelf.canAccept(info) ?? false }
        host.onDragEntered = { [weak self] in
            self?.state.tab = .shelf
            self?.state.shelf.isDropTargeted = true
        }
        host.onDragExited = { [weak self] in self?.state.shelf.isDropTargeted = false }
        host.onDrop = { [weak self] info in self?.state.shelf.importDrop(info) ?? false }

        let controller = NSViewController()
        controller.view = host
        controller.preferredContentSize = RootView.size

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = RootView.size
        popover.contentViewController = controller
        self.popover = popover

        let dropPanel = DropPanelController(shelf: state.shelf)
        self.dropPanel = dropPanel
        dragMonitor.onDragBegan = { [weak self] in
            dropPanel.show(below: self?.statusItemScreenRect())
        }
        dragMonitor.onDragEnded = {
            // A drop on the panel schedules its own, longer, hide so the confirmation stays readable.
            guard !dropPanel.isDroppedPhase else { return }
            dropPanel.hide(after: 0.3)
        }
        dragMonitor.start()
    }

    private func statusItemScreenRect() -> NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.audio.teardown()
    }

    @objc private func togglePopover() {
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            showPopover(tab: nil)
        }
    }

    private func showPopover(tab: Tab?) {
        guard let popover, let button = statusItem?.button else { return }
        if let tab { state.tab = tab }
        guard !popover.isShown else { return }
        // The cooperative `activate()` is often refused for accessory apps, leaving the popover unfocused.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverWillShow(_ notification: Notification) {
        state.popoverDidShow()
        // Transient popovers only auto-close while the app is active, which an accessory app often isn't.
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.popover?.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        state.popoverDidClose()
        // Give focus back to whatever was in front; an active app with no windows is a dead end.
        NSApp.deactivate()
    }

    private func showContextMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit MenuBoard", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.isEnabled.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
