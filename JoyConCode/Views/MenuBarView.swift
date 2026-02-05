import SwiftUI

/// Main menubar popover view
struct MenuBarView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var keyboardSimulator: KeyboardSimulator
    @ObservedObject var joyConManager: JoyConManager

    @State private var showSettings = false
    @State private var showDetails = false

    private var joyConStatusText: String {
        if joyConManager.connectedCount > 1 {
            return "Connected (\(joyConManager.connectedCount))"
        } else if joyConManager.isConnected {
            return "Connected"
        } else {
            return "Not Connected"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .font(.title2)
                Text("JoyConCode")
                    .font(.headline)
                Spacer()
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                MenuToggleRow(
                    icon: settings.isEnabled ? "checkmark.circle.fill" : "circle",
                    iconColor: settings.isEnabled ? .green : .secondary,
                    title: settings.isEnabled ? "Enabled" : "Disabled",
                    isOn: $settings.isEnabled,
                    tint: .green
                )

                MenuToggleRow(
                    icon: "waveform.path",
                    iconColor: .secondary,
                    title: "Rumble Feedback",
                    isOn: $settings.joyConRumbleEnabled,
                    tint: .accentColor
                )

                HStack {
                    Button("Test Rumble") {
                        joyConManager.rumbleOnce()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!settings.isEnabled || !joyConManager.isConnected || !settings.joyConRumbleEnabled)

                    Spacer()

                    StatusBadge(
                        text: joyConStatusText,
                        color: joyConManager.isConnected ? .green : .secondary
                    )
                }
            }

            DisclosureGroup(isExpanded: $showDetails) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusRow(
                            icon: "gamecontroller",
                            title: "Joy-Con",
                            status: joyConStatusText,
                            color: joyConManager.isConnected ? .green : .secondary
                        )

                        StatusRow(
                            icon: "rectangle.3.group",
                            title: "Background",
                            status: joyConManager.backgroundEventsEnabled ? "Monitoring On" : "Monitoring Off",
                            color: joyConManager.backgroundEventsEnabled ? .secondary : .orange
                        )

                        if !joyConManager.controllerProfilesDescription.isEmpty {
                            StatusRow(
                                icon: "info.circle",
                                title: "Profile",
                                status: joyConManager.controllerProfilesDescription,
                                color: .secondary
                            )
                        }

                        StatusRow(
                            icon: "waveform.path.ecg",
                            title: "Raw Input",
                            status: joyConManager.lastRawElementDescription.isEmpty ? "No events received" : joyConManager.lastRawElementDescription,
                            color: .secondary
                        )

                        StatusRow(
                            icon: "dot.radiowaves.left.and.right",
                            title: "Last Input",
                            status: joyConManager.lastInputDescription.isEmpty ? "—" : joyConManager.lastInputDescription,
                            color: .secondary
                        )

                        if !keyboardSimulator.lastKeyPressed.isEmpty {
                            StatusRow(
                                icon: "keyboard",
                                title: "Last Action",
                                status: keyboardSimulator.lastKeyPressed,
                                color: .purple
                            )
                        }
                    }
                }
            } label: {
                Text("Details")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if joyConManager.hasUnknownMicroGamepadSide {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Some Joy-Con controllers couldn't be identified as (L)/(R). Those inputs default to Right, so your mapping may not match.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            // Permissions Warnings
            if !keyboardSimulator.accessibilityGranted {
                WarningRow(
                    icon: "keyboard",
                    message: "Accessibility access required",
                    action: "Open Settings",
                    onAction: { keyboardSimulator.requestAccessibilityPermissions() }
                )
            }

            // Settings Panel
            if showSettings {
                Divider()
                SettingsView(settings: settings, joyConManager: joyConManager)
            }

            Divider()

            // Footer
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.9")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Supporting Views

struct StatusRow: View {
    let icon: String
    let title: String
    let status: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(status)
                .foregroundColor(color)
        }
        .font(.caption)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct MenuToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 20)
            Text(title)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(tint)
                .accessibilityLabel(title)
        }
        .font(.callout)
    }
}

struct WarningRow: View {
    let icon: String
    let message: String
    let action: String
    let onAction: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
            Spacer()
            Button(action, action: onAction)
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

#if DEBUG
struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarView(
            keyboardSimulator: KeyboardSimulator(),
            joyConManager: JoyConManager()
        )
    }
}
#endif
