import AppKit

/// Transparent overlay on the status bar button that accepts drags.
/// Mouse clicks are forwarded to the button so normal click handling still works.
final class StatusItemDropView: NSView {
    var canAccept: ((NSDraggingInfo) -> Bool)?
    var onDragEntered: (() -> Void)?
    var onDrop: ((NSDraggingInfo) -> Bool)?
    var onRightClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(ShelfStore.draggedTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept?(sender) == true else { return [] }
        onDragEntered?()
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop?(sender) ?? false
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?()
        } else {
            superview?.mouseDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}
