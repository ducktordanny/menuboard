import AppKit
import SwiftUI

/// Popover content view that accepts drops anywhere and hands them to the shelf.
/// SwiftUI's drop modifiers can't read file promises (browser image drags), so this stays in AppKit.
final class ShelfDropHostingView<Content: View>: NSHostingView<Content> {
    var canAccept: ((NSDraggingInfo) -> Bool)?
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
    var onDrop: ((NSDraggingInfo) -> Bool)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes(ShelfStore.draggedTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept?(sender) == true else { return [] }
        onDragEntered?()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDragExited?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop?(sender) ?? false
    }
}
