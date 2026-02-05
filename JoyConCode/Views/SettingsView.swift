import SwiftUI

/// Settings panel for configuring the app
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var joyConManager: JoyConManager

    @State private var showJoyConMapping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)

            // Joy-Con Settings
            VStack(alignment: .leading, spacing: 8) {
                Text("Joy-Con")
                    .font(.headline)

                Toggle(isOn: $settings.joyConEnabled) {
                    Text("Enable Joy-Con Input")
                }
                .toggleStyle(.switch)

                Toggle(isOn: $settings.joyConRumbleEnabled) {
                    Text("Rumble Feedback")
                }
                .toggleStyle(.switch)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Rumble Strength")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Slider(value: $settings.joyConRumbleStrength, in: 0.1...1.0, step: 0.1)
                        Text("\(String(format: "%.1f", settings.joyConRumbleStrength))")
                            .font(.caption)
                            .frame(width: 40)
                    }
                }

                Button("Configure Joy-Con Mapping") {
                    showJoyConMapping = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text("Tip: While the mapping window is open, Joy-Con input won't send keystrokes to other apps.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Reset Button
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showJoyConMapping) {
            JoyConMappingView(settings: settings, joyConManager: joyConManager)
                .frame(width: 900, height: 560)
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: AppSettings.shared, joyConManager: JoyConManager())
            .frame(width: 280)
            .padding()
    }
}
#endif
