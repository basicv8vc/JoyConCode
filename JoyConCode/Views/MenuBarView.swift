import SwiftUI

/// Main menubar popover view
struct MenuBarView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var keyboardSimulator: KeyboardSimulator
    @ObservedObject var joyConManager: JoyConManager

    @State private var showSettings = false

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

            // Enable/Disable Toggle (master gate)
            Toggle(isOn: $settings.isEnabled) {
                HStack {
                    Image(systemName: settings.isEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(settings.isEnabled ? .green : .secondary)
                    Text(settings.isEnabled ? "Enabled" : "Disabled")
                }
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.joyConEnabled) {
                    Text("Enable Joy-Con Input")
                }
                .toggleStyle(.switch)
                .disabled(!settings.isEnabled)

                Toggle(isOn: $settings.joyConRumbleEnabled) {
                    Text("Rumble Feedback")
                }
                .toggleStyle(.switch)
                .disabled(!settings.isEnabled || !settings.joyConEnabled)

                HStack {
                    Button("Test Rumble") {
                        joyConManager.rumbleOnce()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!settings.isEnabled || !settings.joyConEnabled || !joyConManager.isConnected || !settings.joyConRumbleEnabled)

                    Spacer()

                    Text(joyConStatusText)
                        .font(.caption)
                        .foregroundColor(joyConManager.isConnected ? .green : .secondary)
                }
            }

            // Status Section
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    StatusRow(
                        icon: "gamecontroller",
                        title: "Joy-Con",
                        status: joyConStatusText,
                        color: joyConManager.isConnected ? .green : .secondary
                    )

                    if !joyConManager.lastInputDescription.isEmpty {
                        StatusRow(
                            icon: "dot.radiowaves.left.and.right",
                            title: "Last Input",
                            status: joyConManager.lastInputDescription,
                            color: .secondary
                        )
                    }

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

            // Permissions Warnings
            if !keyboardSimulator.accessibilityGranted {
                WarningRow(
                    icon: "keyboard",
                    message: "Accessibility access required",
                    action: "Open Settings",
                    onAction: { keyboardSimulator.requestAccessibilityPermissions() }
                )
            }

            Divider()

            // Settings Panel
            if showSettings {
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
