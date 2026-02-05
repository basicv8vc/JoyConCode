import SwiftUI
import AppKit

struct JoyConMappingView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var joyConManager: JoyConManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedKey: JoyConBindingKey?
    @State private var highlightedKey: JoyConBindingKey?
    @State private var isAwaitingKeyboard = false
    @State private var pendingModifierKeyCode: UInt16?
    @State private var sawNonModifierKeyDown = false
    @State private var lastModifierFlags: NSEvent.ModifierFlags = []
    @State private var localEventMonitor: Any?

    var body: some View {
        VStack(spacing: 12) {
            header

            HStack(alignment: .top, spacing: 16) {
                JoyConSideCard(
                    side: .left,
                    selectedKey: selectedKey,
                    highlightedKey: highlightedKey,
                    bindingProvider: binding(for:),
                    onSelect: handleSelect(_:)
                )

                JoyConSideCard(
                    side: .right,
                    selectedKey: selectedKey,
                    highlightedKey: highlightedKey,
                    bindingProvider: binding(for:),
                    onSelect: handleSelect(_:)
                )
            }

            Spacer(minLength: 0)
        }
        .padding()
        .background(
            KeyCaptureView(
                isActive: isAwaitingKeyboard,
                onKeyDown: { event in handleKeyDown(event) },
                onFlagsChanged: { event in handleFlagsChanged(event) }
            )
            .frame(width: 1, height: 1)
        )
        .onAppear {
            joyConManager.setMappingMode(true)
            joyConManager.onInput = { key in
                DispatchQueue.main.async {
                    highlightedKey = key
                    handleSelect(key)

                    // Flash highlight briefly.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        if highlightedKey == key {
                            highlightedKey = nil
                        }
                    }
                }
            }

            // Capture modifier-only keys (Shift/Fn/etc.) reliably. These often emit `flagsChanged`
            // and may not reach our 1x1 first-responder view depending on focus.
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                guard isAwaitingKeyboard else { return event }
                if event.type == .keyDown {
                    handleKeyDown(event)
                    return nil
                }
                if event.type == .flagsChanged {
                    handleFlagsChanged(event)
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            joyConManager.onInput = nil
            joyConManager.setMappingMode(false)
            if let localEventMonitor {
                NSEvent.removeMonitor(localEventMonitor)
                self.localEventMonitor = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Joy-Con Mapping")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 8) {
                Text(joyConManager.isConnected ? "Connected (\(joyConManager.connectedCount))" : "Not Connected")
                    .font(.caption)
                    .foregroundColor(joyConManager.isConnected ? .green : .secondary)

                Spacer()

                Text("Press a Joy-Con button to select, then press a keyboard shortcut to bind.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if joyConManager.hasUnknownMicroGamepadSide {
                Text("Some controllers could not be identified as (L)/(R). Those inputs will default to Right.")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    let boundChord = selectedKey.flatMap { settings.joyConBindingsV2[$0] }
                    Text(selectedKey?.displayName ?? "No input selected")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Text(boundChord != nil ? "Bound: \(boundChord!.displayString())" : "Unassigned")
                        .font(.caption2)
                        .foregroundColor(boundChord != nil ? .green : .secondary)
                }

                Spacer()

                if isAwaitingKeyboard {
                    Text("Waiting for keyboard…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Button("Clear") {
                    if let key = selectedKey {
                        clearBinding(key)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!(selectedKey.flatMap { settings.joyConBindingsV2[$0] } != nil))

                if isAwaitingKeyboard {
                    Button("Cancel") {
                        isAwaitingKeyboard = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func handleSelect(_ key: JoyConBindingKey) {
        selectedKey = key
        isAwaitingKeyboard = true
        pendingModifierKeyCode = nil
        sawNonModifierKeyDown = false
        lastModifierFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard isAwaitingKeyboard, let selectedKey else { return }
        guard let chord = KeyChord.from(event: event) else { return }
        settings.joyConBindingsV2[selectedKey] = chord
        isAwaitingKeyboard = false
        pendingModifierKeyCode = nil
        sawNonModifierKeyDown = true
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard isAwaitingKeyboard, let selectedKey else { return }

        let newFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let changed = lastModifierFlags.symmetricDifference(newFlags)
        lastModifierFlags = newFlags

        guard let resolved = ResolvedModifierChange(eventKeyCode: event.keyCode, changedFlags: changed) else { return }
        let isDown = newFlags.contains(resolved.kind.flag)

        if isDown {
            // Don't bind immediately; user might be doing Shift+K etc.
            pendingModifierKeyCode = resolved.keyCode
            sawNonModifierKeyDown = false
            return
        }

        // Modifier released. If no non-modifier key was pressed in between, treat as modifier-only binding.
        guard pendingModifierKeyCode == resolved.keyCode, !sawNonModifierKeyDown else { return }

        settings.joyConBindingsV2[selectedKey] = KeyChord(keyCode: resolved.keyCode, modifiers: [])
        isAwaitingKeyboard = false
        pendingModifierKeyCode = nil
    }

    private func clearBinding(_ key: JoyConBindingKey) {
        settings.joyConBindingsV2.removeValue(forKey: key)
    }

    private func binding(for key: JoyConBindingKey?) -> String? {
        guard let key, let chord = settings.joyConBindingsV2[key] else { return nil }
        return chord.displayString()
    }
}

private struct JoyConSideCard: View {
    let side: JoyConSide
    let selectedKey: JoyConBindingKey?
    let highlightedKey: JoyConBindingKey?
    let bindingProvider: (JoyConBindingKey?) -> String?
    let onSelect: (JoyConBindingKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(side.displayName)
                .font(.headline)

            JoyConDiagram(
                side: side,
                selectedKey: selectedKey,
                highlightedKey: highlightedKey,
                bindingProvider: bindingProvider,
                onSelect: onSelect
            )
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JoyConDiagram: View {
    enum NodeShape {
        case circle
        case capsule
        case ring
        case pill
    }

    struct NodeSpec: Identifiable {
        let id = UUID()
        let input: JoyConInput
        let label: String
        let shape: NodeShape
        let center: CGPoint   // normalized (0..1)
        let size: CGSize      // normalized (0..1), relative to container width/height
        let help: String
    }

    let side: JoyConSide
    let selectedKey: JoyConBindingKey?
    let highlightedKey: JoyConBindingKey?
    let bindingProvider: (JoyConBindingKey?) -> String?
    let onSelect: (JoyConBindingKey) -> Void

    private var shellTint: Color {
        switch side {
        case .left: return Color(red: 0.08, green: 0.42, blue: 0.95)
        case .right: return Color(red: 0.92, green: 0.20, blue: 0.28)
        }
    }

    private var specs: [NodeSpec] {
        switch side {
        case .left:
            return leftSpecs
        case .right:
            return rightSpecs
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                RoundedRectangle(cornerRadius: min(w, h) * 0.30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                shellTint.opacity(0.22),
                                shellTint.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: min(w, h) * 0.30, style: .continuous)
                            .strokeBorder(shellTint.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: shellTint.opacity(0.10), radius: 18, x: 0, y: 8)

                // Inner rails to hint real Joy-Con plastic.
                RoundedRectangle(cornerRadius: min(w, h) * 0.24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    .padding(w * 0.08)

                RoundedRectangle(cornerRadius: min(w, h) * 0.24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.07), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(w * 0.10)

                ForEach(specs) { spec in
                    let key = JoyConBindingKey(side: side, input: spec.input)
                    let isSelected = selectedKey == key
                    let isHighlighted = highlightedKey == key
                    let boundText = bindingProvider(key)

                    JoyConControlNode(
                        label: spec.label,
                        shape: spec.shape,
                        isSelected: isSelected,
                        isHighlighted: isHighlighted,
                        isBound: boundText != nil
                    ) {
                        onSelect(key)
                    }
                    .help(helpText(for: key, boundText: boundText))
                    .frame(width: spec.size.width * w, height: spec.size.height * h)
                    .position(x: spec.center.x * w, y: spec.center.y * h)
                }
            }
        }
        .aspectRatio(0.48, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func helpText(for key: JoyConBindingKey, boundText: String?) -> String {
        if let boundText {
            return "\(key.displayName)\n\(boundText)"
        }
        return "\(key.displayName)\nUnassigned"
    }

    private var leftSpecs: [NodeSpec] {
        [
            // Top shoulder/trigger
            NodeSpec(input: .leftTrigger, label: "ZL", shape: .capsule, center: CGPoint(x: 0.50, y: 0.06), size: CGSize(width: 0.70, height: 0.08), help: "Left Trigger"),
            NodeSpec(input: .leftShoulder, label: "L", shape: .capsule, center: CGPoint(x: 0.50, y: 0.14), size: CGSize(width: 0.60, height: 0.08), help: "Left Shoulder"),

            // Minus
            NodeSpec(input: .buttonOptions, label: "−", shape: .circle, center: CGPoint(x: 0.74, y: 0.25), size: CGSize(width: 0.16, height: 0.10), help: "Minus"),

            // Left stick (press)
            NodeSpec(input: .leftThumbstickButton, label: "LS", shape: .ring, center: CGPoint(x: 0.50, y: 0.38), size: CGSize(width: 0.34, height: 0.23), help: "Left Stick Button"),

            // Left stick directions (ring arrows)
            NodeSpec(input: .leftStickUp, label: "↑", shape: .pill, center: CGPoint(x: 0.50, y: 0.28), size: CGSize(width: 0.22, height: 0.07), help: "Left Stick Up"),
            NodeSpec(input: .leftStickDown, label: "↓", shape: .pill, center: CGPoint(x: 0.50, y: 0.48), size: CGSize(width: 0.22, height: 0.07), help: "Left Stick Down"),
            NodeSpec(input: .leftStickLeft, label: "←", shape: .pill, center: CGPoint(x: 0.34, y: 0.38), size: CGSize(width: 0.22, height: 0.07), help: "Left Stick Left"),
            NodeSpec(input: .leftStickRight, label: "→", shape: .pill, center: CGPoint(x: 0.66, y: 0.38), size: CGSize(width: 0.22, height: 0.07), help: "Left Stick Right"),

            // D-pad cluster (separate buttons)
            NodeSpec(input: .dpadUp, label: "▲", shape: .circle, center: CGPoint(x: 0.50, y: 0.63), size: CGSize(width: 0.18, height: 0.12), help: "D-Pad Up"),
            NodeSpec(input: .dpadDown, label: "▼", shape: .circle, center: CGPoint(x: 0.50, y: 0.79), size: CGSize(width: 0.18, height: 0.12), help: "D-Pad Down"),
            NodeSpec(input: .dpadLeft, label: "◀", shape: .circle, center: CGPoint(x: 0.35, y: 0.71), size: CGSize(width: 0.18, height: 0.12), help: "D-Pad Left"),
            NodeSpec(input: .dpadRight, label: "▶", shape: .circle, center: CGPoint(x: 0.65, y: 0.71), size: CGSize(width: 0.18, height: 0.12), help: "D-Pad Right")
        ]
    }

    private var rightSpecs: [NodeSpec] {
        [
            // Top shoulder/trigger
            NodeSpec(input: .rightTrigger, label: "ZR", shape: .capsule, center: CGPoint(x: 0.50, y: 0.06), size: CGSize(width: 0.70, height: 0.08), help: "Right Trigger"),
            NodeSpec(input: .rightShoulder, label: "R", shape: .capsule, center: CGPoint(x: 0.50, y: 0.14), size: CGSize(width: 0.60, height: 0.08), help: "Right Shoulder"),

            // Plus (near left edge)
            NodeSpec(input: .buttonMenu, label: "+", shape: .circle, center: CGPoint(x: 0.30, y: 0.25), size: CGSize(width: 0.16, height: 0.10), help: "Plus"),

            // ABXY cluster
            NodeSpec(input: .buttonX, label: "X", shape: .circle, center: CGPoint(x: 0.50, y: 0.39), size: CGSize(width: 0.18, height: 0.12), help: "X"),
            NodeSpec(input: .buttonB, label: "B", shape: .circle, center: CGPoint(x: 0.50, y: 0.55), size: CGSize(width: 0.18, height: 0.12), help: "B"),
            NodeSpec(input: .buttonY, label: "Y", shape: .circle, center: CGPoint(x: 0.35, y: 0.47), size: CGSize(width: 0.18, height: 0.12), help: "Y"),
            NodeSpec(input: .buttonA, label: "A", shape: .circle, center: CGPoint(x: 0.65, y: 0.47), size: CGSize(width: 0.18, height: 0.12), help: "A"),

            // Right stick (press)
            NodeSpec(input: .rightThumbstickButton, label: "RS", shape: .ring, center: CGPoint(x: 0.50, y: 0.74), size: CGSize(width: 0.34, height: 0.23), help: "Right Stick Button"),

            // Right stick directions (ring arrows)
            NodeSpec(input: .rightStickUp, label: "↑", shape: .pill, center: CGPoint(x: 0.50, y: 0.64), size: CGSize(width: 0.22, height: 0.07), help: "Right Stick Up"),
            NodeSpec(input: .rightStickDown, label: "↓", shape: .pill, center: CGPoint(x: 0.50, y: 0.84), size: CGSize(width: 0.22, height: 0.07), help: "Right Stick Down"),
            NodeSpec(input: .rightStickLeft, label: "←", shape: .pill, center: CGPoint(x: 0.34, y: 0.74), size: CGSize(width: 0.22, height: 0.07), help: "Right Stick Left"),
            NodeSpec(input: .rightStickRight, label: "→", shape: .pill, center: CGPoint(x: 0.66, y: 0.74), size: CGSize(width: 0.22, height: 0.07), help: "Right Stick Right"),

            // Home (left-down of the stick)
            NodeSpec(input: .buttonHome, label: "⌂", shape: .circle, center: CGPoint(x: 0.30, y: 0.90), size: CGSize(width: 0.16, height: 0.10), help: "Home")
        ]
    }
}

private struct JoyConControlNode: View {
    let label: String
    let shape: JoyConDiagram.NodeShape
    let isSelected: Bool
    let isHighlighted: Bool
    let isBound: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            nodeBackground
                .overlay(nodeBorder)
                .shadow(color: Color.black.opacity(isHighlighted ? 0.10 : 0.06), radius: 10, x: 0, y: 6)
                .overlay {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(textColor)
                        .padding(.horizontal, 6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            .scaleEffect(isHighlighted ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHighlighted)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var nodeBackground: some View {
        switch shape {
        case .circle:
            Circle().fill(background)
        case .capsule:
            Capsule(style: .continuous).fill(background)
        case .ring:
            Circle().fill(background)
        case .pill:
            Capsule(style: .continuous).fill(background)
        }
    }

    @ViewBuilder
    private var nodeBorder: some View {
        switch shape {
        case .circle:
            Circle().strokeBorder(borderColor, lineWidth: borderWidth)
        case .capsule:
            Capsule(style: .continuous).strokeBorder(borderColor, lineWidth: borderWidth)
        case .ring:
            Circle().strokeBorder(borderColor, lineWidth: borderWidth)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                        .padding(6)
                )
        case .pill:
            Capsule(style: .continuous).strokeBorder(borderColor, lineWidth: borderWidth)
        }
    }

    private var background: Color {
        if isHighlighted {
            return Color.accentColor.opacity(0.90)
        }
        if isSelected {
            return Color.accentColor.opacity(0.20)
        }
        if isBound {
            return Color.green.opacity(0.18)
        }
        return Color(NSColor.windowBackgroundColor).opacity(0.85)
    }

    private var borderColor: Color {
        if isHighlighted {
            return Color.accentColor.opacity(0.95)
        }
        if isSelected {
            return Color.accentColor.opacity(0.60)
        }
        if isBound {
            return Color.green.opacity(0.55)
        }
        return Color.black.opacity(0.14)
    }

    private var borderWidth: CGFloat {
        (isSelected || isHighlighted) ? 2 : 1
    }

    private var textColor: Color {
        isHighlighted ? .white : .primary
    }
}

private struct KeyCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onKeyDown: (NSEvent) -> Void
    let onFlagsChanged: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyDown = onKeyDown
        view.onFlagsChanged = onFlagsChanged
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.onFlagsChanged = onFlagsChanged
        if isActive {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

private final class KeyCaptureNSView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?
    var onFlagsChanged: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }

    override func flagsChanged(with event: NSEvent) {
        onFlagsChanged?(event)
    }
}

private enum ModifierKind {
    case shift
    case control
    case option
    case command
    case function

    init?(keyCode: UInt16) {
        switch keyCode {
        case 56, 60:
            self = .shift
        case 59, 62:
            self = .control
        case 58, 61:
            self = .option
        case 54, 55:
            self = .command
        case 63:
            self = .function
        default:
            return nil
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .control: return .control
        case .option: return .option
        case .command: return .command
        case .function: return .function
        }
    }
}

private struct ResolvedModifierChange {
    let kind: ModifierKind
    let keyCode: UInt16

    init?(eventKeyCode: UInt16, changedFlags: NSEvent.ModifierFlags) {
        // Prefer the actual hardware keyCode when it is one of the known modifier keyCodes.
        if let kind = ModifierKind(keyCode: eventKeyCode) {
            self.kind = kind
            self.keyCode = eventKeyCode
            return
        }

        // Fallback: detect which modifier flag changed. This helps with Fn/Globe on some keyboards,
        // where the keyCode isn't always the classic kVK_Function (63).
        if changedFlags.contains(.function) {
            self.kind = .function
            self.keyCode = 63
            return
        }
        if changedFlags.contains(.shift) {
            self.kind = .shift
            self.keyCode = 56
            return
        }
        if changedFlags.contains(.control) {
            self.kind = .control
            self.keyCode = 59
            return
        }
        if changedFlags.contains(.option) {
            self.kind = .option
            self.keyCode = 58
            return
        }
        if changedFlags.contains(.command) {
            self.kind = .command
            self.keyCode = 55
            return
        }
        return nil
    }
}

#if DEBUG
struct JoyConMappingView_Previews: PreviewProvider {
    static var previews: some View {
        JoyConMappingView(settings: AppSettings.shared, joyConManager: JoyConManager())
            .frame(width: 900, height: 560)
    }
}
#endif
