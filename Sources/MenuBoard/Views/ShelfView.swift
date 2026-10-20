import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @State private var previewURL: URL?

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
                            ShelfRow(item: item, store: store) { previewURL = store.previewURL(for: item) }
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
                    ShareLink(items: store.urls) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .controlSize(.small)
                    Button("Clear") { store.clear() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .quickLookPreview($previewURL, in: store.items.map { store.previewURL(for: $0) })
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
    let onPreview: () -> Void
    @State private var showsInlinePreview = false

    var body: some View {
        HStack(spacing: 10) {
            ShelfThumbnail(item: item, store: store)
            VStack(alignment: .leading, spacing: 2) {
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
            ShareLink(item: item.url) {
                Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Share")
            Button {
                showsInlinePreview.toggle()
            } label: {
                Image(systemName: showsInlinePreview ? "eye.fill" : "eye")
                    .foregroundStyle(showsInlinePreview ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Preview")
            .popover(isPresented: $showsInlinePreview, arrowEdge: .trailing) {
                InlinePreview(title: item.title, url: store.previewURL(for: item)) {
                    showsInlinePreview = false
                    store.open(item)
                }
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
            Button("Quick Look", action: onPreview)
            Button(item.isFile ? "Open" : "Open in Browser") { store.open(item) }
            ShareLink(item: item.url) { Label("Share…", systemImage: "square.and.arrow.up") }
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

private struct ShelfThumbnail: View {
    let item: ShelfItem
    // Observed so the row re-renders when the lazily generated preview lands.
    @ObservedObject var store: ShelfStore

    var body: some View {
        Group {
            if item.isFile {
                if let thumbnail = store.preview(for: item) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary, lineWidth: 1))
                } else {
                    Image(nsImage: store.icon(for: item))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(3)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5))
                    if let favicon = store.preview(for: item) {
                        Image(nsImage: favicon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(nsImage: store.icon(for: item))
                            .resizable()
                            .frame(width: 26, height: 26)
                    }
                }
            }
        }
        .frame(width: 44, height: 44)
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
