import SwiftUI

struct SettingsView: View {
    @ObservedObject var menuBar: MenuBarSettings
    @EnvironmentObject private var state: AppState
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Show in Menu Bar") {
                Toggle("Icon", isOn: $menuBar.showIcon)
                ForEach(menuBar.order) { metric in
                    HStack {
                        Toggle(metric.title, isOn: menuBar.binding(for: metric))
                        Spacer()
                        ReorderButtons(
                            canMoveUp: menuBar.order.first != metric,
                            canMoveDown: menuBar.order.last != metric,
                            moveUp: { menuBar.move(metric, by: -1) },
                            moveDown: { menuBar.move(metric, by: 1) }
                        )
                    }
                }
                Text("Order here is the order in the menu bar. Metrics are sampled every 2 seconds while enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tabs") {
                ForEach(state.tabOrder) { tab in
                    HStack {
                        Text(tab.title)
                        Spacer()
                        ReorderButtons(
                            canMoveUp: state.tabOrder.first != tab,
                            canMoveDown: state.tabOrder.last != tab,
                            moveUp: { state.moveTab(tab, by: -1) },
                            moveDown: { state.moveTab(tab, by: 1) }
                        )
                    }
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
            }

            Section {
                Button("Quit MenuBoard", role: .destructive) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .onChange(of: launchAtLogin) { _, enabled in
            LaunchAtLogin.isEnabled = enabled
            launchAtLogin = LaunchAtLogin.isEnabled
        }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}


private struct ReorderButtons: View {
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: moveUp) { Image(systemName: "chevron.up") }
                .disabled(!canMoveUp)
                .help("Move up")
            Button(action: moveDown) { Image(systemName: "chevron.down") }
                .disabled(!canMoveDown)
                .help("Move down")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}
