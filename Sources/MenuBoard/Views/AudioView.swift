import SwiftUI

struct AudioView: View {
    @ObservedObject var mixer: AudioMixer

    var body: some View {
        VStack(spacing: 0) {
            masterSection
            Divider()

            if let message = mixer.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(message).lineLimit(3)
                    Spacer()
                    Button("Settings") { AudioCapturePermission.openSystemSettings() }
                        .controlSize(.small)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                Divider()
            }

            if mixer.apps.isEmpty {
                EmptyState(
                    systemImage: "speaker.slash",
                    title: "No apps are playing audio",
                    detail: "Apps appear here while they output sound. Lowering a slider needs System Audio Recording permission."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(mixer.apps) { app in
                            AppVolumeRow(app: app, mixer: mixer)
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private var masterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "hifispeaker")
                Text(mixer.outputDeviceName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                if mixer.masterAvailable {
                    Text(Format.percent(mixer.masterVolume))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if mixer.masterAvailable {
                HStack(spacing: 8) {
                    MuteButton(isMuted: mixer.masterMuted) { mixer.setMasterMuted(!mixer.masterMuted) }
                    Slider(value: Binding(get: { mixer.masterVolume }, set: { mixer.setMasterVolume($0) }), in: 0...1)
                        .controlSize(.small)
                }
            } else {
                Text("This device has no software volume control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }
}

private struct AppVolumeRow: View {
    let app: AudioApp
    let mixer: AudioMixer

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).font(.callout).lineLimit(1)
                    if app.isPlaying {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.variableColor.iterative, isActive: true)
                    }
                    Spacer()
                    Text(app.isMuted ? "Muted" : Format.percent(app.volume))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    MuteButton(isMuted: app.isMuted) { mixer.setMuted(!app.isMuted, for: app.id) }
                    Slider(value: Binding(get: { app.volume }, set: { mixer.setVolume($0, for: app.id) }), in: 0...1)
                        .controlSize(.small)
                        .disabled(app.isMuted)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

private struct MuteButton: View {
    let isMuted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .frame(width: 16)
                .foregroundStyle(isMuted ? Color.red : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(isMuted ? "Unmute" : "Mute")
    }
}
