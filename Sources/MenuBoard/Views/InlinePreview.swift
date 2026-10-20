import AppKit
import Quartz
import SwiftUI

/// Yoink-style preview: Quick Look content rendered inline in a popover next to the row.
struct InlinePreview: View {
    let title: String
    let url: URL
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            QuickLookPreviewView(url: url)
                .frame(width: 540, height: 450)
            Divider()
            HStack {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Open", action: onOpen)
                    .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

private struct QuickLookPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.shouldCloseWithWindow = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
