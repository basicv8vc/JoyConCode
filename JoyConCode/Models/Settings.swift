import Foundation
import SwiftUI

/// User preferences and settings
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // Keys for UserDefaults
    private enum Keys {
        static let isEnabled = "isEnabled"
        static let joyConEnabled = "joyConEnabled"
        static let joyConRumbleEnabled = "joyConRumbleEnabled"
        static let joyConRumbleStrength = "joyConRumbleStrength"
        static let joyConBindings = "joyConBindings"
        static let joyConBindingsV2 = "joyConBindingsV2"
    }

    /// Master enable switch (gates Joy-Con input and URL-triggered rumble).
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
        }
    }

    /// Whether Joy-Con input is enabled
    @Published var joyConEnabled: Bool {
        didSet {
            defaults.set(joyConEnabled, forKey: Keys.joyConEnabled)
        }
    }

    /// Whether Joy-Con rumble is enabled
    @Published var joyConRumbleEnabled: Bool {
        didSet {
            defaults.set(joyConRumbleEnabled, forKey: Keys.joyConRumbleEnabled)
        }
    }

    /// Joy-Con rumble strength (0.0 to 1.0)
    @Published var joyConRumbleStrength: Double {
        didSet {
            defaults.set(joyConRumbleStrength, forKey: Keys.joyConRumbleStrength)
        }
    }

    /// Joy-Con input bindings
    @Published var joyConBindings: [JoyConInput: KeyChord] {
        didSet {
            let data = try? JSONEncoder().encode(joyConBindings)
            defaults.set(data, forKey: Keys.joyConBindings)
        }
    }

    /// Joy-Con input bindings (side-aware)
    @Published var joyConBindingsV2: [JoyConBindingKey: KeyChord] {
        didSet {
            let storage = joyConBindingsV2.map { JoyConBindingEntry(key: $0.key, chord: $0.value) }
            let data = try? JSONEncoder().encode(storage)
            defaults.set(data, forKey: Keys.joyConBindingsV2)
        }
    }

    private init() {
        // Load saved values or use defaults
        self.isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? false
        self.joyConEnabled = defaults.object(forKey: Keys.joyConEnabled) as? Bool ?? false
        self.joyConRumbleEnabled = defaults.object(forKey: Keys.joyConRumbleEnabled) as? Bool ?? true
        self.joyConRumbleStrength = defaults.object(forKey: Keys.joyConRumbleStrength) as? Double ?? 0.6

        if let data = defaults.data(forKey: Keys.joyConBindings),
           let decoded = try? JSONDecoder().decode([JoyConInput: KeyChord].self, from: data) {
            self.joyConBindings = decoded
        } else {
            self.joyConBindings = [:]
        }

        if let data = defaults.data(forKey: Keys.joyConBindingsV2),
           let decoded = try? JSONDecoder().decode([JoyConBindingEntry].self, from: data) {
            var map: [JoyConBindingKey: KeyChord] = [:]
            for entry in decoded {
                map[entry.key] = entry.chord
            }
            self.joyConBindingsV2 = map
        } else {
            self.joyConBindingsV2 = [:]
        }

        migrateJoyConBindingsIfNeeded()
    }

    /// Reset all settings to defaults
    func resetToDefaults() {
        isEnabled = false
        joyConEnabled = false
        joyConRumbleEnabled = true
        joyConRumbleStrength = 0.6
        joyConBindings = [:]
        joyConBindingsV2 = [:]
    }
}

private extension AppSettings {
    struct JoyConBindingEntry: Codable {
        let key: JoyConBindingKey
        let chord: KeyChord
    }

    func migrateJoyConBindingsIfNeeded() {
        guard joyConBindingsV2.isEmpty, !joyConBindings.isEmpty else { return }

        var migrated: [JoyConBindingKey: KeyChord] = [:]
        for (input, chord) in joyConBindings {
            let side = AppSettings.sideForMigration(input: input)
            migrated[JoyConBindingKey(side: side, input: input)] = chord
        }

        joyConBindingsV2 = migrated
        joyConBindings = [:]

        // Persist migration immediately.
        let storage = migrated.map { JoyConBindingEntry(key: $0.key, chord: $0.value) }
        let data = try? JSONEncoder().encode(storage)
        defaults.set(data, forKey: Keys.joyConBindingsV2)
        defaults.removeObject(forKey: Keys.joyConBindings)
    }

    static func sideForMigration(input: JoyConInput) -> JoyConSide {
        switch input {
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
             .leftShoulder, .leftTrigger, .leftThumbstickButton,
             .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight,
             .buttonOptions:
            return .left
        case .buttonA, .buttonB, .buttonX, .buttonY,
             .rightShoulder, .rightTrigger, .rightThumbstickButton,
             .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight,
             .buttonMenu, .buttonHome, .buttonCapture:
            return .right
        }
    }
}
