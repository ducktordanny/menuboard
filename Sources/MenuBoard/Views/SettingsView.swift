import SwiftUI

struct SettingsView: View {
    @ObservedObject var menuBar: MenuBarSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Show in Menu Bar") {
                Toggle("Icon", isOn: $menuBar.showIcon)
                ForEach(menuBar.order) { metric in
                    HStack {
                        Toggle(metric.title, isOn: menuBar.binding(for: metric))
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                            .help("Drag to reorder")
                    }
                }
                .onMove { source, destination in menuBar.move(from: source, to: destination) }
                Text("Drag rows to change the order in the menu bar. Metrics are sampled every 2 seconds while enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
