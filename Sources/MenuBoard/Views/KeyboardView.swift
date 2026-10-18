import SwiftUI

struct KeyboardView: View {
    @ObservedObject var remapper: KeyRemapper
    @ObservedObject var hyper: HyperKey
    @State private var from: UInt64 = KeyCatalog.all[0].usage
    @State private var to: UInt64 = KeyCatalog.all[1].usage

    private var capsLock: UInt64 { KeyCatalog.all[0].usage }
    private var rightControl: UInt64 { KeyCatalog.all.first { $0.name == "Right Control" }!.usage }
    private var escape: UInt64 { KeyCatalog.all.first { $0.name == "Escape" }!.usage }
    private var grave: UInt64 { KeyCatalog.all.first { $0.name.hasPrefix("`") }!.usage }
    private var section: UInt64 { KeyCatalog.all.first { $0.name.hasPrefix("§") }!.usage }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Remapping", isOn: $remapper.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                statusLabel
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if remapper.rules.isEmpty {
                        Text("No remaps yet. Pick a preset or build one below.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        VStack(spacing: 2) {
                            ForEach(remapper.rules) { rule in
                                RemapRow(rule: rule) { remapper.remove(rule) }
                            }
                        }
                    }

                    Text("Presets").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Button("Caps Lock → Control") { remapper.add(from: capsLock, to: rightControl) }
                        Button("Caps Lock → Escape") { remapper.add(from: capsLock, to: escape) }
                        Button("Swap ` and §") { remapper.addSwap(grave, section) }
                    }
                    .controlSize(.small)

                    Text("Remaps apply to every keyboard and stay active until you log out. MenuBoard re-applies them at launch. The Caps Lock preset targets Right Control so it stays independent of a Left Control hyper key.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    hyperCard
                }
                .padding(10)
            }

            Divider()

            HStack(spacing: 6) {
                keyPicker("From", selection: $from)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                keyPicker("To", selection: $to)
                Button("Add") { remapper.add(from: from, to: to) }
                    .disabled(from == to)
                if !remapper.rules.isEmpty {
                    Button("Reset") { remapper.removeAll() }
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var hyperCard: some View {
        Card(title: "Hyper Key") {
            Toggle("Hold to get ⌃⌥⇧⌘", isOn: $hyper.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
            HStack {
                Text("Key").foregroundStyle(.secondary)
                Spacer()
                Picker("Key", selection: $hyper.sourceKeyCode) {
                    ForEach(HyperSourceKey.all) { key in
                        Text(key.name).tag(key.keyCode)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 150)
            }
            .font(.caption)
            Toggle("Tap alone sends Escape", isOn: $hyper.tapSendsEscape)
                .toggleStyle(.switch)
                .controlSize(.small)
            hyperStatus
        }
    }

    @ViewBuilder
    private var hyperStatus: some View {
        switch hyper.status {
        case .off:
            Text("Off").font(.caption).foregroundStyle(.secondary)
        case .active:
            Label("Active", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .needsPermission:
            HStack {
                Label("Needs Accessibility permission", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Spacer()
                Button("Open Settings") { HyperKey.openAccessibilitySettings() }
                    .controlSize(.small)
            }
            .font(.caption)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let error = remapper.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .lineLimit(1)
                .help(error)
        } else if remapper.isApplied {
            Label("Active", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Text(remapper.isEnabled ? "Nothing applied" : "Disabled").foregroundStyle(.secondary)
        }
    }

    private func keyPicker(_ title: String, selection: Binding<UInt64>) -> some View {
        Picker(title, selection: selection) {
            ForEach(KeyCatalog.all) { key in
                Text(key.name).tag(key.usage)
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }
}

private struct RemapRow: View {
    let rule: KeyRemap
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard").foregroundStyle(.secondary)
            Text(KeyCatalog.name(for: rule.from)).font(.callout)
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
            Text(KeyCatalog.name(for: rule.to)).font(.callout.weight(.medium))
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }
}
