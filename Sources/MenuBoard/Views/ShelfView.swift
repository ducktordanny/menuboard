import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject var store: ShelfStore

    var body: some View {
        VStack(spacing: 0) {
            if store.items.isEmpty {
                EmptyState(
                    systemImage: "tray.and.arrow.down",
                    title: "Drop anything here",
                    detail: "Files, links, or images from a browser. You can also drop them on the menu bar icon or the drop zone that appears while dragging."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.items) { item in
                            ShelfRow(item: item, store: store)
                        }
                    }
                    .padding(8)
                }
                Divider()
                HStack {
                    Label("Drag all", systemImage: "hand.draw")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                        .overlay(MultiFileDragHandle(urls: store.urls))
                    Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { store.clear() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .overlay {
            if store.isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct ShelfRow: View {
    let item: ShelfItem
    let store: ShelfStore

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: store.icon(for: item))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.callout).lineLimit(1)
                Text(store.detail(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if item.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                store.remove(item)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove from shelf")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .draggable(item.url)
        .onTapGesture(count: 2) { store.open(item) }
        .contextMenu {
            Button(item.isFile ? "Open" : "Open in Browser") { store.open(item) }
            if item.isFile {
                Button("Show in Finder") { store.reveal(item) }
            }
            Button(item.isFile ? "Copy Path" : "Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.isFile ? item.url.path : item.url.absoluteString, forType: .string)
            }
            Divider()
            Button("Remove") { store.remove(item) }
        }
    }
}

/// SwiftUI can't start a multi-item drag, so this AppKit view drags every shelf item at once.
private struct MultiFileDragHandle: NSViewRepresentable {
    let urls: [URL]

    func makeNSView(context: Context) -> MultiFileDragView { MultiFileDragView() }

    func updateNSView(_ view: MultiFileDragView, context: Context) {
        view.urls = urls
    }
}

final class MultiFileDragView: NSView, NSDraggingSource {
    var urls: [URL] = []

    override func mouseDragged(with event: NSEvent) {
        guard !urls.isEmpty else { return }
        let items = urls.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = url.isFileURL
                ? NSWorkspace.shared.icon(forFile: url.path)
                : (NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage())
            item.setDraggingFrame(NSRect(x: 0, y: 0, width: 32, height: 32), contents: icon)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link] : []
    }
}
