import AppKit
import Combine
import Quartz
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
    private var escapeMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private static let icon = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "MenuBoard")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }

        button.image = Self.icon
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
        // Transient popovers also close when a menu opens inside them (footer gear, row context menus),
        // so dismissal is handled manually: outside clicks, Escape, and app deactivation.
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentSize = RootView.size
        popover.contentViewController = controller
        self.popover = popover

        state.shelf.onImport = { [weak self] in self?.state.tab = .shelf }

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

        state.menuBar.objectWillChange
            .merge(with: state.system.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateStatusItem() }
            .store(in: &cancellables)
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let settings = state.menuBar
        state.system.backgroundSampling = settings.hasMetrics
        let title = settings.hasMetrics ? StatusItemRenderer.title(stats: state.system, settings: settings) : NSAttributedString()
        let showIcon = settings.showIcon || title.length == 0
        button.attributedTitle = title
        button.image = showIcon ? Self.icon : nil
        button.imagePosition = title.length == 0 ? .imageOnly : (showIcon ? .imageLeading : .noImage)
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
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.closePopover(reason: "outside click")
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            // Let Quick Look consume Escape when its panel is up instead of closing the popover.
            if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { return event }
            self?.closePopover(reason: "escape")
            return nil
        }
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.closePopover(reason: "resign active")
        }
    }

    private func closePopover(reason: String) {
        guard let popover, popover.isShown else { return }
        // Clicks inside the popover must never dismiss it, whichever path reported them.
        if reason != "escape", isMouseInsidePopover() {
            NSLog("MenuBoard: ignored close (%@) with mouse inside popover", reason)
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            return
        }
        NSLog("MenuBoard: closing popover (%@)", reason)
        popover.performClose(nil)
    }

    private func isMouseInsidePopover() -> Bool {
        guard let window = popover?.contentViewController?.view.window else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
        state.popoverDidClose()
        // Give focus back to whatever was in front; an active app with no windows is a dead end.
        NSApp.deactivate()
    }

    private func showContextMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let display = NSMenuItem(title: "Show in Menu Bar", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let iconItem = NSMenuItem(title: "Icon", action: #selector(toggleIcon), keyEquivalent: "")
        iconItem.target = self
        iconItem.state = state.menuBar.showIcon ? .on : .off
        submenu.addItem(iconItem)
        submenu.addItem(.separator())
        for metric in MenuBarMetric.allCases {
            let item = NSMenuItem(title: metric.title, action: #selector(toggleMetric(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = metric.rawValue
            item.state = state.menuBar.isEnabled(metric) ? .on : .off
            submenu.addItem(item)
        }
        display.submenu = submenu
        menu.addItem(display)
        menu.addItem(.separator())

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

    @objc private func toggleIcon() {
        state.menuBar.showIcon.toggle()
    }

    @objc private func toggleMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let metric = MenuBarMetric(rawValue: raw) else { return }
        state.menuBar.toggle(metric)
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.isEnabled.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
