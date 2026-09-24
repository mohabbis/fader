import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var engine: AudioEngine
    var showsOpenButton: Bool
    @Environment(\.colorScheme) private var scheme

    private var palette: Palette { Palette.forScheme(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            master
            Divider().overlay(palette.line)
            content
        }
        .frame(width: 372)
        .background(palette.background)
    }

    private var header: some View {
        HStack(spacing: 10) {
            FaderMark(color: palette.copper)
                .frame(width: 16, height: 16)
            Text("Fader")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.text)
            Spacer()
            if showsOpenButton {
                Button("Open mixer") {
                    MixerWindow.show(engine: engine)
                }
                .buttonStyle(QuietButtonStyle(palette: palette))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var master: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Master")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondary)
                Spacer()
                Text(percent(engine.masterVolume))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.text)
                    .monospacedDigit()
            }
            FaderSlider(
                value: Binding(
                    get: { engine.masterVolume },
                    set: { engine.setMasterVolume($0) }
                ),
                accessibilityLabel: "Master volume",
                palette: palette
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var content: some View {
        if engine.permission == .needsApproval && engine.apps.isEmpty {
            permissionCard
        } else if engine.apps.isEmpty {
            empty
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    if engine.permission == .needsApproval {
                        permissionCard
                    }
                    ForEach(engine.apps) { app in
                        AppRow(app: app, engine: engine, palette: palette)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 460)
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(palette.copper)
            Text("Nothing is playing")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.text)
            Text("Start music or a video in any app and it will show up here.")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Allow system audio")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(engine.status ?? "Fader needs System Audio Recording so it can set each app’s volume and output.")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") {
                openPrivacySettings()
            }
            .buttonStyle(QuietButtonStyle(palette: palette))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.elevated, in: RoundedRectangle(cornerRadius: 10))
        .padding(engine.apps.isEmpty ? 16 : 0)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct AppRow: View {
    let app: PlayingApp
    @ObservedObject var engine: AudioEngine
    var palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(app.isFallback ? palette.danger : palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                devicePicker
            }
            HStack(spacing: 10) {
                Button {
                    engine.setMuted(app.id, !app.isMuted)
                } label: {
                    Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(app.isMuted ? palette.danger : palette.secondary)
                        .background(palette.track, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.isMuted ? "Unmute \(app.name)" : "Mute \(app.name)")
                FaderSlider(
                    value: Binding(
                        get: { app.volume },
                        set: { engine.setVolume(app.id, $0) }
                    ),
                    accessibilityLabel: "\(app.name) volume",
                    palette: palette
                )
                Text("\(Int((app.volume * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 36, alignment: .trailing)
                    .monospacedDigit()
            }
            level
        }
        .padding(10)
        .background(palette.elevated, in: RoundedRectangle(cornerRadius: 12))
        .opacity(app.isMuted ? 0.72 : 1)
    }

    private var caption: String {
        if app.isFallback, let missing = app.pinnedDeviceName {
            return "\(missing) unavailable · \(app.activeDeviceName)"
        }
        if app.followsSystem {
            return "System output · \(app.activeDeviceName)"
        }
        return app.activeDeviceName
    }

    private var icon: some View {
        Group {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(palette.track)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(String(app.name.prefix(1)))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.text)
                    )
            }
        }
    }

    private var devicePicker: some View {
        Picker(
            "Output",
            selection: Binding(
                get: { app.followsSystem ? "" : (app.pinnedDeviceUID ?? "") },
                set: { engine.selectOutput(app.id, deviceUID: $0.isEmpty ? nil : $0) }
            )
        ) {
            Text("System output").tag("")
            if app.isFallback, let uid = app.pinnedDeviceUID, let name = app.pinnedDeviceName {
                Text("\(name) unavailable").tag(uid)
            }
            ForEach(engine.devices) { device in
                Text(device.name).tag(device.uid)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 150)
    }

    private var level: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                Capsule()
                    .fill(palette.copper.opacity(0.85))
                    .frame(width: geo.size.width * CGFloat(min(app.level, 1)))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

private struct FaderMark: View {
    var color: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            bar(height: 8)
            bar(height: 14)
            bar(height: 10)
        }
    }

    private func bar(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 3, height: height)
    }
}

private struct QuietButtonStyle: ButtonStyle {
    var palette: Palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(palette.elevated, in: Capsule())
            .overlay(Capsule().stroke(palette.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

func openPrivacySettings() {
    let candidates = [
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AudioCapture",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
    ]
    for candidate in candidates {
        guard let url = URL(string: candidate) else { continue }
        if NSWorkspace.shared.open(url) { return }
    }
}

enum MixerWindow {
    private static var controller: NSWindowController?

    @MainActor
    static func show(engine: AudioEngine) {
        if let window = controller?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: PanelView(engine: engine, showsOpenButton: false))
        let window = NSWindow(contentViewController: host)
        window.title = "Fader"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 372, height: 520))
        window.minSize = NSSize(width: 372, height: 280)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
