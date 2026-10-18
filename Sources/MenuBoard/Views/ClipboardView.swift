import AppKit
import SwiftUI

struct ClipboardView: View {
    @ObservedObject var store: ClipboardStore
    @State private var query = ""

    private var filtered: [ClipboardEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return store.entries }
        return store.entries.filter { $0.searchText.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if filtered.isEmpty {
                EmptyState(
                    systemImage: store.isRecording ? "doc.on.clipboard" : "pause.circle",
                    title: query.isEmpty ? (store.isRecording ? "Nothing copied yet" : "Recording paused") : "No matches",
                    detail: query.isEmpty ? "Text, files and images you copy show up here. Click one to copy it again." : "Try a different search."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { entry in
                            ClipRow(entry: entry, store: store)
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            HStack {
                Toggle("Record", isOn: $store.isRecording)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
                Spacer()
                Text("\(store.entries.count) / \(ClipboardStore.maxEntries)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Clear") { store.clear() }
                    .controlSize(.small)
                    .disabled(store.entries.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

private struct ClipRow: View {
    let entry: ClipboardEntry
    let store: ClipboardStore
    @State private var isHovered = false

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if let icon = store.appIcon(for: entry) {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: symbolName).foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 20)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                preview
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if store.lastCopiedID == entry.id {
                Label("Copied", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { store.copy(entry) }
        .contextMenu {
            Button("Copy") { store.copy(entry) }
            if case .files(let paths) = entry.content {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
                }
            }
            Divider()
            Button("Delete") { store.remove(entry) }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch entry.content {
        case .text(let text):
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.callout)
                .lineLimit(3)
                .textSelection(.disabled)
        case .files(let paths):
            Text(paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))
                .font(.callout)
                .lineLimit(2)
        case .image:
            if let image = store.image(for: entry) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 64, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text("Image").font(.callout)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let app = entry.appName { parts.append(app) }
        parts.append(Self.relative.localizedString(for: entry.date, relativeTo: Date()))
        switch entry.content {
        case .text(let text):
            parts.append("\(text.count) chars")
        case .files(let paths):
            parts.append("\(paths.count) file\(paths.count == 1 ? "" : "s")")
        case .image:
            if let image = store.image(for: entry) {
                parts.append("\(Int(image.size.width))×\(Int(image.size.height))")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var symbolName: String {
        switch entry.content {
        case .text: "text.alignleft"
        case .files: "doc"
        case .image: "photo"
        }
    }
}
