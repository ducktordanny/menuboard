import SwiftUI

struct RootView: View {
    static let size = NSSize(width: 420, height: 500)

    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $state.tab) {
                ForEach(state.tabOrder) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            Divider()

            Group {
                if state.showSettings {
                    SettingsView(menuBar: state.menuBar)
                } else {
                    switch state.tab {
                    case .system: SystemView(stats: state.system)
                    case .memory: ProcessesView(monitor: state.processes)
                    case .audio: AudioView(mixer: state.audio)
                    case .shelf: ShelfView(store: state.shelf)
                    case .clipboard: ClipboardView(store: state.clipboard)
                    case .keyboard: KeyboardView(remapper: state.keys, hyper: state.hyper)
                    case .ports: PortsView(monitor: state.ports)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Text(state.showSettings ? "Settings" : "MenuBoard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                KeepAwakeControl(keepAwake: state.keepAwake)
                Button {
                    state.showSettings.toggle()
                } label: {
                    Image(systemName: state.showSettings ? "xmark.circle.fill" : "gearshape")
                        .foregroundStyle(state.showSettings ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(state.showSettings ? "Close settings" : "Settings")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

private struct KeepAwakeControl: View {
    @ObservedObject var keepAwake: KeepAwake

    var body: some View {
        HStack(spacing: 6) {
            if let text = keepAwake.remainingText {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Menu {
                ForEach(KeepAwake.durations, id: \.title) { option in
                    Button(option.title) { keepAwake.activate(for: option.seconds) }
                }
                if keepAwake.isActive {
                    Divider()
                    Button("Turn Off") { keepAwake.deactivate() }
                }
            } label: {
                Image(systemName: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .foregroundStyle(keepAwake.isActive ? Color.accentColor : Color.secondary)
            } primaryAction: {
                keepAwake.toggle()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(keepAwake.isActive ? "Keep awake is on. Click to turn off." : "Keep the Mac awake. Click to toggle, hold for a duration.")
        }
    }
}
