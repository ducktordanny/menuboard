import AppKit
import SwiftUI

/// Popover content view that accepts external drops anywhere and hands them to the shelf.
/// SwiftUI's drop modifiers can't read file promises (browser image drags), so this stays in AppKit.
/// Drags that start inside the app fall through to SwiftUI so row reordering keeps working.
final class ShelfDropHostingView<Content: View>: NSHostingView<Content> {
    var canAccept: ((NSDraggingInfo) -> Bool)?
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
    var onDrop: ((NSDraggingInfo) -> Bool)?

    private var isHandlingShelfDrop = false

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes(ShelfStore.draggedTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // SwiftUI re-registers its own types; keep the shelf types alongside them.
    override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {
        super.registerForDraggedTypes(Array(Set(newTypes + ShelfStore.draggedTypes)))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if canAccept?(sender) == true {
            isHandlingShelfDrop = true
            onDragEntered?()
            return .copy
        }
        isHandlingShelfDrop = false
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isHandlingShelfDrop ? .copy : super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if isHandlingShelfDrop {
            onDragExited?()
        } else {
            super.draggingExited(sender)
        }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        if isHandlingShelfDrop {
            onDragExited?()
            isHandlingShelfDrop = false
        } else {
            super.draggingEnded(sender)
        }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHandlingShelfDrop ? true : super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHandlingShelfDrop ? (onDrop?(sender) ?? false) : super.performDragOperation(sender)
    }
}
