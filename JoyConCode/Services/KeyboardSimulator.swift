import Foundation
import ApplicationServices

/// Simulates keyboard input using CGEvent API
class KeyboardSimulator: ObservableObject {
    @Published var accessibilityGranted = false
    @Published var lastKeyPressed: String = ""

    private var pollTimer: Timer?

    init() {
        checkAccessibilityPermissions()
        startPollingIfNeeded()
    }

    deinit {
        pollTimer?.invalidate()
    }

    private func startPollingIfNeeded() {
        guard !accessibilityGranted, pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = AXIsProcessTrusted()
            if granted {
                self.accessibilityGranted = true
                self.pollTimer?.invalidate()
                self.pollTimer = nil
            }
        }
    }

    /// Check if accessibility permissions are granted
    func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    /// Request accessibility permissions (opens System Settings)
    func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        startPollingIfNeeded()
    }

    /// Simulate a key press for the given chord
    func simulateKey(chord: KeyChord, description: String? = nil) {
        if chord.modifiers.isEmpty {
            simulateKeyPress(keyCode: chord.keyCode)
        } else {
            simulateKeyWithModifiers(keyCode: chord.keyCode, modifiers: chord.modifiers)
        }
        lastKeyPressed = description ?? chord.displayString()
    }

    /// Simulate pressing a key with modifier keys (e.g., Shift+Tab)
    func simulateKeyWithModifiers(keyCode: UInt16, modifiers: CGEventFlags) {
        guard accessibilityGranted else {
            print("Accessibility permissions not granted")
            requestAccessibilityPermissions()
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            print("Failed to create key events with modifiers")
            return
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        print("Simulated key press: \(keyCode) with modifiers: \(modifiers)")
    }

    /// Simulate pressing and releasing a key
    func simulateKeyPress(keyCode: UInt16) {
        guard accessibilityGranted else {
            print("Accessibility permissions not granted")
            requestAccessibilityPermissions()
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)

        // Key down event
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else {
            print("Failed to create key down event")
            return
        }

        // Key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            print("Failed to create key up event")
            return
        }

        // Post the events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        print("Simulated key press: \(keyCode)")
    }

    /// Type a string of text
    func typeText(_ text: String) {
        guard accessibilityGranted else {
            print("Accessibility permissions not granted")
            requestAccessibilityPermissions()
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)

        for character in text {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                continue
            }

            var unicodeChar = [UniChar](character.utf16)
            event.keyboardSetUnicodeString(stringLength: unicodeChar.count, unicodeString: &unicodeChar)
            event.post(tap: .cghidEventTap)

            // Key up
            if let upEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                upEvent.keyboardSetUnicodeString(stringLength: unicodeChar.count, unicodeString: &unicodeChar)
                upEvent.post(tap: .cghidEventTap)
            }

            // Small delay between characters for reliability
            usleep(10000) // 10ms
        }

        lastKeyPressed = "Typed: \(text.prefix(20))\(text.count > 20 ? "..." : "")"
    }
}
