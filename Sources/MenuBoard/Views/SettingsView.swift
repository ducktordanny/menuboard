import SwiftUI

struct SettingsView: View {
    @ObservedObject var menuBar: MenuBarSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Show in Menu Bar") {
                Toggle("Icon", isOn: $menuBar.showIcon)
                ForEach(MenuBarMetric.allCases) { metric in
                    Toggle(metric.title, isOn: menuBar.binding(for: metric))
                }
                Text("Metrics are sampled every 2 seconds while enabled.")
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
