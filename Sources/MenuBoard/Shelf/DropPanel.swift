import AppKit
import SwiftUI

/// Small floating drop zone that appears under the menu bar icon while something is being dragged.
final class DropPanelController {
    private static let size = NSSize(width: 200, height: 76)

    private let shelf: ShelfStore
    private let panel: NSPanel
    private let zone = DropZoneState()
    private var hideWork: DispatchWorkItem?

    init(shelf: ShelfStore) {
        self.shelf = shelf

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let target = DropTargetView(frame: NSRect(origin: .zero, size: Self.size))
        target.canAccept = { [weak self] info in self?.shelf.canAccept(info) ?? false }
        target.onTargetedChange = { [weak self] targeted in self?.zone.isTargeted = targeted }
        target.onDrop = { [weak self] info in
            guard let self, self.shelf.importDrop(info) else { return false }
            self.zone.phase = .dropped
            self.hide(after: 0.9)
            return true
        }

        let hosting = NSHostingView(rootView: DropZoneView(state: zone))
        hosting.frame = target.bounds
        hosting.autoresizingMask = [.width, .height]
        target.addSubview(hosting)
        panel.contentView = target
    }

    func show(below anchor: NSRect?) {
        hideWork?.cancel()
        zone.phase = .waiting
        zone.isTargeted = false

        let screen = NSScreen.screens.first { $0.frame.contains(anchor?.origin ?? .zero) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let anchorRect = anchor ?? NSRect(x: visible.maxX - 60, y: visible.maxY, width: 0, height: 0)

        var x = anchorRect.midX - Self.size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - Self.size.width - 8)
        let finalFrame = NSRect(x: x, y: visible.maxY - Self.size.height - 6, width: Self.size.width, height: Self.size.height)

        guard !panel.isVisible else {
            panel.setFrame(finalFrame, display: true)
            return
        }

        panel.alphaValue = 0
        panel.setFrame(finalFrame.offsetBy(dx: 0, dy: 10), display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
    }

    func hide(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideNow() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    var isDroppedPhase: Bool { zone.phase == .dropped }

    private func hideNow() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            panel.orderOut(nil)
        })
    }
}

private final class DropTargetView: NSView {
    var canAccept: ((NSDraggingInfo) -> Bool)?
    var onTargetedChange: ((Bool) -> Void)?
    var onDrop: ((NSDraggingInfo) -> Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(ShelfStore.draggedTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept?(sender) == true else { return [] }
        onTargetedChange?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetedChange?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetedChange?(false)
        return onDrop?(sender) ?? false
    }
}

private final class DropZoneState: ObservableObject {
    enum Phase { case waiting, dropped }

    @Published var isTargeted = false
    @Published var phase = Phase.waiting
}

private struct DropZoneView: View {
    @ObservedObject var state: DropZoneState

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: state.phase == .dropped ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                .font(.system(size: 20))
                .foregroundStyle(state.phase == .dropped ? Color.green : state.isTargeted ? Color.accentColor : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
            Text(state.phase == .dropped ? "Added to shelf" : "Drop to shelf")
                .font(.caption.weight(.medium))
                .foregroundStyle(state.isTargeted ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    state.isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: state.isTargeted ? 2 : 1, dash: state.isTargeted ? [] : [5, 4])
                )
                .padding(4)
        }
        .animation(.easeOut(duration: 0.12), value: state.isTargeted)
    }
}
