import SwiftUI

struct RootView: View {
    static let size = NSSize(width: 380, height: 500)

    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $state.tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            Divider()

            Group {
                switch state.tab {
                case .system: SystemView(stats: state.system)
                case .memory: ProcessesView(monitor: state.processes)
                case .audio: AudioView(mixer: state.audio)
                case .shelf: ShelfView(store: state.shelf)
                case .clipboard: ClipboardView(store: state.clipboard)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            FooterView()
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

private struct FooterView: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        HStack {
            Text("MenuBoard")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Divider()
                Button("Quit MenuBoard") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onChange(of: launchAtLogin) { _, enabled in
            LaunchAtLogin.isEnabled = enabled
            launchAtLogin = LaunchAtLogin.isEnabled
        }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}
