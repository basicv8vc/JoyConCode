import Foundation
import ApplicationServices
import AppKit

/// Simulates keyboard input using CGEvent API
class KeyboardSimulator: ObservableObject {
    @Published var accessibilityGranted = false
    @Published var lastKeyPressed: String = ""

    private var pollTimer: Timer?
    private var heldModifierKinds = Set<ModifierKey>()
    private var heldModifierKeyCodes: [ModifierKey: UInt16] = [:]

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
        let normalized = normalizeFnChord(chord)

        if shouldSendBacktabEscapeSequence(chord: normalized) {
            // Prefer posting a HID-level Shift+Tab, which most terminals translate into ^[[Z (backtab).
            simulateBacktab()
        } else if normalized.modifiers.isEmpty {
            simulateKeyPress(keyCode: normalized.keyCode)
        } else {
            simulateKeyWithModifiers(keyCode: normalized.keyCode, modifiers: normalized.modifiers)
        }
        lastKeyPressed = description ?? normalized.displayString()
    }

    func handleJoyConChordEvent(chord: KeyChord, pressed: Bool, description: String? = nil) {
        let normalized = normalizeFnChord(chord)

        if isHoldableModifierOnlyChord(normalized) {
            if pressed {
                holdModifierKeyDown(keyCode: normalized.keyCode)
                lastKeyPressed = (description ?? normalized.displayString()) + " (down)"
            } else {
                holdModifierKeyUp(keyCode: normalized.keyCode)
                lastKeyPressed = (description ?? normalized.displayString()) + " (up)"
            }
            return
        }

        // Only act on press for non-modifier bindings.
        guard pressed else { return }
        simulateKey(chord: normalized, description: description)
    }

    /// Simulate pressing a key with modifier keys (e.g., Shift+Tab)
    func simulateKeyWithModifiers(keyCode: UInt16, modifiers: CGEventFlags) {
        guard accessibilityGranted else {
            print("Accessibility permissions not granted")
            requestAccessibilityPermissions()
            return
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            print("Failed to create CGEventSource")
            return
        }

        let modifierSequence = ModifierKey.sequence(from: modifiers)
        let heldFlags = heldModifierFlags()
        var activeFlags: CGEventFlags = heldFlags
        var pressedForThisCall: [ModifierKey] = []

        // Press modifiers in order: Ctrl -> Option -> Shift -> Cmd -> Fn
        for modifierKey in modifierSequence {
            if heldModifierKinds.contains(modifierKey) { continue }
            activeFlags.insert(modifierKey.flag)
            guard postKeyEvent(
                source: source,
                keyCode: modifierKey.keyCode,
                isKeyDown: true,
                flags: activeFlags
            ) else {
                print("Failed to post modifier keyDown: \(modifierKey)")
                return
            }
            pressedForThisCall.append(modifierKey)
            usleep(1000)
        }

        // Press main key with all modifiers active.
        guard postKeyEvent(source: source, keyCode: keyCode, isKeyDown: true, flags: activeFlags),
              postKeyEvent(source: source, keyCode: keyCode, isKeyDown: false, flags: activeFlags) else {
            print("Failed to post main key events with modifiers")
            return
        }
        usleep(1000)

        // Release modifiers in reverse order.
        for modifierKey in pressedForThisCall.reversed() {
            activeFlags.remove(modifierKey.flag)
            guard postKeyEvent(
                source: source,
                keyCode: modifierKey.keyCode,
                isKeyDown: false,
                flags: activeFlags
            ) else {
                print("Failed to post modifier keyUp: \(modifierKey)")
                return
            }
            usleep(1000)
        }

        print("Simulated key press: \(keyCode) with modifiers: \(modifiers)")
    }

    /// Simulate pressing and releasing a key
    func simulateKeyPress(keyCode: UInt16) {
        guard accessibilityGranted else {
            print("Accessibility permissions not granted")
            requestAccessibilityPermissions()
            return
        }

        // If Shift is being held (via a separate Joy-Con binding) and the user presses Tab, prefer a HID-level
        // Shift+Tab to maximize compatibility with terminals/TUIs.
        if keyCode == 48 {
            let held = heldModifierFlags()
            if held == .maskShift, shouldSendBacktabEscapeSequence(chord: KeyChord(keyCode: 48, modifiers: .maskShift)) {
                simulateBacktab()
                return
            }
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            print("Failed to create CGEventSource")
            return
        }

        let flags = heldModifierFlags()
        guard postKeyEvent(source: source, keyCode: keyCode, isKeyDown: true, flags: flags),
              postKeyEvent(source: source, keyCode: keyCode, isKeyDown: false, flags: flags) else {
            print("Failed to post key events")
            return
        }

        print("Simulated key press: \(keyCode)")
    }

    private func simulateBacktab() {
        guard accessibilityGranted else {
            print("Accessibility permissions not granted")
            requestAccessibilityPermissions()
            return
        }

        // Post as HID events so terminal apps can translate Shift+Tab into the expected escape sequence.
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("Failed to create CGEventSource")
            return
        }

        let flags: CGEventFlags = .maskShift
        guard postKeyEvent(source: source, keyCode: 48, isKeyDown: true, flags: flags, tap: .cghidEventTap),
              postKeyEvent(source: source, keyCode: 48, isKeyDown: false, flags: flags, tap: .cghidEventTap) else {
            print("Failed to post backtab events")
            return
        }
    }

    private func postKeyEvent(
        source: CGEventSource,
        keyCode: UInt16,
        isKeyDown: Bool,
        flags: CGEventFlags,
        tap: CGEventTapLocation = .cgSessionEventTap
    ) -> Bool {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isKeyDown) else {
            return false
        }
        event.flags = flags
        event.post(tap: tap)
        return true
    }

    private func heldModifierFlags() -> CGEventFlags {
        heldModifierKinds.reduce(into: CGEventFlags()) { result, kind in
            result.insert(kind.flag)
        }
    }

    private func isHoldableModifierOnlyChord(_ chord: KeyChord) -> Bool {
        guard chord.modifiers.isEmpty else { return false }
        return ModifierKey.kind(for: chord.keyCode) != nil
    }

    private func holdModifierKeyDown(keyCode: UInt16) {
        guard accessibilityGranted else { return }
        guard let kind = ModifierKey.kind(for: keyCode) else { return }
        guard !heldModifierKinds.contains(kind) else { return }

        heldModifierKinds.insert(kind)
        heldModifierKeyCodes[kind] = keyCode

        let (source, tap) = eventSourceAndTap(for: keyCode)
        guard let source else { return }
        _ = postKeyEvent(source: source, keyCode: keyCode, isKeyDown: true, flags: heldModifierFlags(), tap: tap)
    }

    private func holdModifierKeyUp(keyCode: UInt16) {
        guard accessibilityGranted else { return }
        guard let kind = ModifierKey.kind(for: keyCode) else { return }
        guard heldModifierKinds.contains(kind) else { return }

        heldModifierKinds.remove(kind)
        let actualKeyCode = heldModifierKeyCodes.removeValue(forKey: kind) ?? keyCode

        let (source, tap) = eventSourceAndTap(for: actualKeyCode)
        guard let source else { return }
        _ = postKeyEvent(source: source, keyCode: actualKeyCode, isKeyDown: false, flags: heldModifierFlags(), tap: tap)
    }

    private func eventSourceAndTap(for keyCode: UInt16) -> (CGEventSource?, CGEventTapLocation) {
        // Fn is special on macOS; best-effort: use HID tap/source to more closely resemble hardware.
        if keyCode == 63 {
            return (CGEventSource(stateID: .hidSystemState), .cghidEventTap)
        }
        return (CGEventSource(stateID: .combinedSessionState), .cgSessionEventTap)
    }

    /// Type a string of text
    func typeText(_ text: String) {
        guard accessibilityGranted else {
            print("Accessibility permissions not granted")
            requestAccessibilityPermissions()
            return
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            print("Failed to create CGEventSource")
            return
        }

        for scalar in text.unicodeScalars {
            var value = UInt16(scalar.value)

            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }

            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)

            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)

            usleep(10000) // 10ms
        }

        lastKeyPressed = "Typed: \(text.prefix(20))\(text.count > 20 ? "..." : "")"
    }
}

private extension KeyboardSimulator {
    func normalizeFnChord(_ chord: KeyChord) -> KeyChord {
        guard chord.modifiers.contains(.maskSecondaryFn) else { return chord }

        // `Fn` is not reliably synthesizable via CGEvent. For the common Fn combinations on macOS,
        // translate them into their semantic equivalents and drop the Fn modifier.
        //
        // Fn+←  => Home
        // Fn+→  => End
        // Fn+↑  => Page Up
        // Fn+↓  => Page Down
        // Fn+Delete(Backspace) => Forward Delete
        let translatedKeyCode: UInt16 = switch chord.keyCode {
        case 123: 115 // Left -> Home
        case 124: 119 // Right -> End
        case 126: 116 // Up -> Page Up
        case 125: 121 // Down -> Page Down
        case 51: 117  // Backspace/Delete -> Forward Delete
        default: chord.keyCode
        }

        var modifiers = chord.modifiers
        modifiers.remove(.maskSecondaryFn)
        return KeyChord(keyCode: translatedKeyCode, modifiers: modifiers)
    }

    func shouldSendBacktabEscapeSequence(chord: KeyChord) -> Bool {
        // Backtab is typically Shift+Tab.
        guard chord.keyCode == 48 else { return false } // Tab
        guard chord.modifiers == .maskShift else { return false }

        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmostApp?.bundleIdentifier ?? ""
        let name = (frontmostApp?.localizedName ?? "").lowercased()

        // Terminal apps: prefer the escape sequence ESC [ Z.
        // This is what many TUI apps (including Claude Code/Codex CLI) expect for Shift+Tab.
        let terminalBundleIDs: Set<String> = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "dev.warp.Warp",
            "com.github.wez.wezterm",
            "net.kovidgoyal.kitty",
            "org.alacritty",
            "io.alacritty",
            "com.mitchellh.ghostty",
            "co.zeit.hyper",
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.cursor.Cursor",
            "com.apple.dt.Xcode"
        ]

        if terminalBundleIDs.contains(bundleID) { return true }
        if name.contains("terminal") || name.contains("iterm") || name.contains("warp") || name.contains("wezterm") || name.contains("ghostty") {
            return true
        }
        return false
    }
}

private enum ModifierKey: CustomStringConvertible {
    case control
    case option
    case shift
    case command
    case fn

    var keyCode: UInt16 {
        switch self {
        case .command: return 55
        case .shift: return 56
        case .option: return 58
        case .control: return 59
        case .fn: return 63
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .shift: return .maskShift
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .fn: return .maskSecondaryFn
        }
    }

    var description: String {
        switch self {
        case .control: return "Ctrl"
        case .option: return "Option"
        case .shift: return "Shift"
        case .command: return "Cmd"
        case .fn: return "Fn"
        }
    }

    static func sequence(from flags: CGEventFlags) -> [ModifierKey] {
        var result: [ModifierKey] = []
        // Order matters for reliability: Ctrl -> Option -> Shift -> Cmd -> Fn
        if flags.contains(.maskControl) { result.append(.control) }
        if flags.contains(.maskAlternate) { result.append(.option) }
        if flags.contains(.maskShift) { result.append(.shift) }
        if flags.contains(.maskCommand) { result.append(.command) }
        if flags.contains(.maskSecondaryFn) { result.append(.fn) }
        return result
    }

    static func kind(for keyCode: UInt16) -> ModifierKey? {
        switch keyCode {
        case 55, 54: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        case 63: return .fn
        default: return nil
        }
    }
}
