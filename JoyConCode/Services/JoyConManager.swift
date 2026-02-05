import Foundation
import GameController
import CoreHaptics

class JoyConManager: ObservableObject {
    @Published var isConnected = false
    @Published var connectedCount = 0
    @Published var lastInputDescription = ""
    @Published var isInMappingMode = false
    @Published var hasUnknownMicroGamepadSide = false
    @Published var controllerProfilesDescription = ""
    @Published var lastRawElementDescription = ""
    @Published var backgroundEventsEnabled = false

    private let settings = AppSettings.shared
    private var joyCons: [GCController] = []
    private var hapticEngines: [ObjectIdentifier: CHHapticEngine] = [:]
    private var stickStates: [ObjectIdentifier: StickState] = [:]
    private var microGamepadSides: [ObjectIdentifier: JoyConSide] = [:]
    private var pressedInputs: [ObjectIdentifier: Set<JoyConInput>] = [:]
    private var configurationRetries: [ObjectIdentifier: Int] = [:]
    private var lastRawElementUpdateTime: Date?

    var onKeyChord: ((KeyChord) -> Void)?
    var onKeyChordEvent: ((KeyChord, Bool) -> Void)?
    var onInput: ((JoyConBindingKey) -> Void)?

    init() {
        if #available(macOS 11.3, *) {
            // Menubar apps are often not frontmost; without this, macOS may not forward controller inputs.
            GCController.shouldMonitorBackgroundEvents = true
            backgroundEventsEnabled = GCController.shouldMonitorBackgroundEvents
        } else {
            backgroundEventsEnabled = true
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidConnect(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidDisconnect(_:)),
            name: .GCControllerDidDisconnect,
            object: nil
        )

        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        for controller in GCController.controllers() {
            attachIfJoyCon(controller)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        GCController.stopWirelessControllerDiscovery()
    }

    func rumbleOnce() {
        guard !isInMappingMode else { return }
        guard settings.isEnabled, settings.joyConRumbleEnabled else { return }
        for controller in joyCons {
            playRumble(on: controller)
        }
    }

    func setMappingMode(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.isInMappingMode = enabled
        }
    }

    @objc private func controllerDidConnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        attachIfJoyCon(controller)
    }

    @objc private func controllerDidDisconnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        detachController(controller)
    }

    private func attachIfJoyCon(_ controller: GCController) {
        guard isJoyCon(controller) else { return }
        if joyCons.contains(where: { $0 == controller }) {
            return
        }

        joyCons.append(controller)
        configureController(controller)
        updateConnectionState()
    }

    private func detachController(_ controller: GCController) {
        guard isJoyCon(controller) else { return }
        joyCons.removeAll { $0 == controller }
        hapticEngines.removeValue(forKey: ObjectIdentifier(controller))
        stickStates.removeValue(forKey: ObjectIdentifier(controller))
        microGamepadSides.removeValue(forKey: ObjectIdentifier(controller))
        pressedInputs.removeValue(forKey: ObjectIdentifier(controller))
        configurationRetries.removeValue(forKey: ObjectIdentifier(controller))
        updateConnectionState()
    }

    private func updateConnectionState() {
        DispatchQueue.main.async {
            self.connectedCount = self.joyCons.count
            self.isConnected = !self.joyCons.isEmpty
            self.updateControllerProfilesDescription()
        }
    }

    private func isJoyCon(_ controller: GCController) -> Bool {
        let name = controller.vendorName?.lowercased() ?? ""
        let category = controller.productCategory.lowercased()
        return name.contains("joy-con") || name.contains("joy con") || category.contains("joy-con") || category.contains("joy con")
    }

    private func configureController(_ controller: GCController) {
        controller.handlerQueue = DispatchQueue.main
        controller.controllerPausedHandler = { [weak self] controller in
            // Best-effort: map the "pause" button to Plus/Menu.
            self?.handleRawInput(.buttonMenu, controller: controller)
        }

        configurePhysicalInputProfile(controller.physicalInputProfile, controller: controller)

        if let gamepad = controller.extendedGamepad {
            configureExtendedGamepad(gamepad, controller: controller)
        } else if let gamepad = controller.gamepad {
            configureGamepad(gamepad, controller: controller)
        } else if let microGamepad = controller.microGamepad {
            configureMicroGamepad(microGamepad, controller: controller)
        } else {
            // Some controllers populate their profiles asynchronously after connect.
            scheduleConfigureRetry(controller)
        }

        updateConnectionState()
    }

    private func configurePhysicalInputProfile(_ profile: GCPhysicalInputProfile, controller: GCController) {
        if #available(macOS 13.0, *) {
            profile.valueDidChangeHandler = { [weak self] profile, element in
                guard let self else { return }
                let now = Date()
                if let last = self.lastRawElementUpdateTime, now.timeIntervalSince(last) < 0.05 {
                    return
                }
                self.lastRawElementUpdateTime = now

                var parts: [String] = []
                if let name = element.localizedName ?? element.unmappedLocalizedName {
                    parts.append(name)
                }
                let aliases = element.aliases
                    .map { $0 }
                    .sorted()
                    .prefix(3)
                if !aliases.isEmpty {
                    parts.append("aliases: \(aliases.joined(separator: ","))")
                }

                if let button = element as? GCControllerButtonInput {
                    parts.append(button.isPressed ? "pressed" : "released")
                    parts.append(String(format: "v=%.2f", button.value))
                } else if let dpad = element as? GCControllerDirectionPad {
                    parts.append(String(format: "x=%.2f", dpad.xAxis.value))
                    parts.append(String(format: "y=%.2f", dpad.yAxis.value))
                }

                DispatchQueue.main.async {
                    self.lastRawElementDescription = parts.joined(separator: " · ")
                }
            }
        }

        // Some controllers (or OS versions) may not populate `extendedGamepad/gamepad/microGamepad`,
        // but will still provide a `physicalInputProfile` with alias-based element lookup.
        //
        // We bind best-effort by matching common aliases / localized names.
        bindPhysicalButton(profile, matching: ["Button A", "A"], input: .buttonA, controller: controller)
        bindPhysicalButton(profile, matching: ["Button B", "B"], input: .buttonB, controller: controller)
        bindPhysicalButton(profile, matching: ["Button X", "X"], input: .buttonX, controller: controller)
        bindPhysicalButton(profile, matching: ["Button Y", "Y"], input: .buttonY, controller: controller)

        bindPhysicalButton(profile, matching: ["Left Shoulder", "L"], input: .leftShoulder, controller: controller)
        bindPhysicalButton(profile, matching: ["Right Shoulder", "R"], input: .rightShoulder, controller: controller)
        bindPhysicalButton(profile, matching: ["Left Trigger", "ZL"], input: .leftTrigger, controller: controller)
        bindPhysicalButton(profile, matching: ["Right Trigger", "ZR"], input: .rightTrigger, controller: controller)

        bindPhysicalButton(profile, matching: ["Left Thumbstick Button", "Left Stick Button"], input: .leftThumbstickButton, controller: controller)
        bindPhysicalButton(profile, matching: ["Right Thumbstick Button", "Right Stick Button"], input: .rightThumbstickButton, controller: controller)

        bindPhysicalButton(profile, matching: ["Menu", "Plus", "Button Menu"], input: .buttonMenu, controller: controller)
        bindPhysicalButton(profile, matching: ["Options", "Minus", "Button Options"], input: .buttonOptions, controller: controller)
        bindPhysicalButton(profile, matching: ["Home"], input: .buttonHome, controller: controller)
        bindPhysicalButton(profile, matching: ["Capture"], input: .buttonCapture, controller: controller)

        if let dpad = resolvePhysicalDpad(profile) {
            preferDirectInput(dpad)
            dpad.valueChangedHandler = { [weak self] _, x, y in
                self?.handleDpad(controller: controller, x: x, y: y)
            }
        }
    }

    private func bindPhysicalButton(
        _ profile: GCPhysicalInputProfile,
        matching candidates: [String],
        input: JoyConInput,
        controller: GCController
    ) {
        guard let button = resolvePhysicalButton(profile, matching: candidates) else { return }
        preferDirectInput(button)
        bindButton(button, input: input, controller: controller)
    }

    private func preferDirectInput(_ element: GCControllerElement?) {
        guard let element else { return }
        // If the system binds an element to a gesture, it can delay or fully intercept input.
        // Prefer always receiving, and disable gestures when we detect a binding.
        if element.isBoundToSystemGesture {
            element.preferredSystemGestureState = .disabled
        } else {
            element.preferredSystemGestureState = .alwaysReceive
        }
    }

    private func resolvePhysicalButton(_ profile: GCPhysicalInputProfile, matching candidates: [String]) -> GCControllerButtonInput? {
        let normalizedCandidates = Set(candidates.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        for button in profile.allButtons {
            let names: [String] = [
                button.localizedName,
                button.unmappedLocalizedName
            ].compactMap { $0?.lowercased() }

            let aliases = button.aliases.map { $0.lowercased() }
            if !normalizedCandidates.isDisjoint(with: aliases) { return button }
            if names.contains(where: { normalizedCandidates.contains($0) }) { return button }
        }

        // Try keyed lookup with the most specific candidate first.
        for candidate in candidates {
            if let button = profile.buttons[candidate] {
                return button
            }
        }

        return nil
    }

    private func resolvePhysicalDpad(_ profile: GCPhysicalInputProfile) -> GCControllerDirectionPad? {
        // Prefer an element that advertises itself as the main D-pad / Direction Pad.
        let preferredTokens = ["direction pad", "d-pad", "dpad"]
        for dpad in profile.allDpads {
            let aliases = dpad.aliases.map { $0.lowercased() }
            let name = dpad.localizedName?.lowercased()
            let unmapped = dpad.unmappedLocalizedName?.lowercased()
            if aliases.contains(where: { token in preferredTokens.contains(where: token.contains) }) {
                return dpad
            }
            if let name, preferredTokens.contains(where: name.contains) {
                return dpad
            }
            if let unmapped, preferredTokens.contains(where: unmapped.contains) {
                return dpad
            }
        }

        // If there is exactly one dpad-like element, use it.
        if profile.allDpads.count == 1 {
            return profile.allDpads.first
        }

        return nil
    }

    private func configureGamepad(_ gamepad: GCGamepad, controller: GCController) {
        preferDirectInput(gamepad.dpad)
        gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
            self?.handleDpad(controller: controller, x: x, y: y)
        }

        bindButton(gamepad.buttonA, input: .buttonA, controller: controller)
        bindButton(gamepad.buttonB, input: .buttonB, controller: controller)
        bindButton(gamepad.buttonX, input: .buttonX, controller: controller)
        bindButton(gamepad.buttonY, input: .buttonY, controller: controller)

        bindButton(gamepad.leftShoulder, input: .leftShoulder, controller: controller)
        bindButton(gamepad.rightShoulder, input: .rightShoulder, controller: controller)
    }

    private func configureExtendedGamepad(_ gamepad: GCExtendedGamepad, controller: GCController) {
        preferDirectInput(gamepad.dpad)
        gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
            self?.handleDpad(controller: controller, x: x, y: y)
        }

        bindButton(gamepad.buttonA, input: .buttonA, controller: controller)
        bindButton(gamepad.buttonB, input: .buttonB, controller: controller)
        bindButton(gamepad.buttonX, input: .buttonX, controller: controller)
        bindButton(gamepad.buttonY, input: .buttonY, controller: controller)

        bindButton(gamepad.leftShoulder, input: .leftShoulder, controller: controller)
        bindButton(gamepad.rightShoulder, input: .rightShoulder, controller: controller)
        bindButton(gamepad.leftTrigger, input: .leftTrigger, controller: controller)
        bindButton(gamepad.rightTrigger, input: .rightTrigger, controller: controller)

        if #available(macOS 13.0, *) {
            bindButton(gamepad.leftThumbstickButton, input: .leftThumbstickButton, controller: controller)
            bindButton(gamepad.rightThumbstickButton, input: .rightThumbstickButton, controller: controller)
        }

        if #available(macOS 13.0, *) {
            bindButton(gamepad.buttonMenu, input: .buttonMenu, controller: controller)
            bindButton(gamepad.buttonOptions, input: .buttonOptions, controller: controller)
            bindButton(gamepad.buttonHome, input: .buttonHome, controller: controller)
        }

        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.handleStick(controller: controller, isLeft: true, x: x, y: y)
        }
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.handleStick(controller: controller, isLeft: false, x: x, y: y)
        }
    }

    private func configureMicroGamepad(_ microGamepad: GCMicroGamepad, controller: GCController) {
        microGamepad.reportsAbsoluteDpadValues = true
        let side = resolveMicroGamepadSide(controller)
        microGamepadSides[ObjectIdentifier(controller)] = side
        preferDirectInput(microGamepad.dpad)
        microGamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
            self?.handleDpad(controller: controller, x: x, y: y)
        }

        bindButton(microGamepad.buttonA, input: .buttonA, controller: controller)
        bindButton(microGamepad.buttonX, input: .buttonX, controller: controller)
    }

    private func bindButton(_ button: GCControllerButtonInput?, input: JoyConInput, controller: GCController) {
        preferDirectInput(button)
        let handler: GCControllerButtonValueChangedHandler = { [weak self] _, _, pressed in
            self?.handleButtonChange(input: input, controller: controller, pressed: pressed)
        }
        button?.pressedChangedHandler = handler
        button?.valueChangedHandler = handler
    }

    private func handleButtonChange(input: JoyConInput, controller: GCController, pressed: Bool) {
        let id = ObjectIdentifier(controller)
        var current = pressedInputs[id] ?? []

        if pressed {
            guard !current.contains(input) else { return }
            current.insert(input)
            pressedInputs[id] = current
            handleRawInput(input, controller: controller)
        } else {
            current.remove(input)
            pressedInputs[id] = current

            // For holdable modifier-only bindings, emit key up on release.
            let side = resolveSide(for: input, controller: controller)
            let bindingKey = JoyConBindingKey(side: side, input: input)
            if let chord = settings.joyConBindingsV2[bindingKey], JoyConManager.isHoldableModifierChord(chord) {
                DispatchQueue.main.async {
                    self.onKeyChordEvent?(chord, false)
                }
            }
        }
    }

    private func handleRawInput(_ input: JoyConInput, controller: GCController) {
        let side = resolveSide(for: input, controller: controller)
        let bindingKey = JoyConBindingKey(side: side, input: input)

        DispatchQueue.main.async {
            self.onInput?(bindingKey)
        }

        // Mapping mode: never emit key events or rumble.
        if isInMappingMode {
            DispatchQueue.main.async {
                self.lastInputDescription = "\(bindingKey.displayName) (Mapping)"
            }
            return
        }

        guard settings.isEnabled else {
            DispatchQueue.main.async {
                self.lastInputDescription = "\(bindingKey.displayName) (Disabled)"
            }
            return
        }

        if let chord = settings.joyConBindingsV2[bindingKey] {
            DispatchQueue.main.async {
                self.lastInputDescription = "\(bindingKey.displayName): \(chord.displayString())"
                if let onKeyChordEvent = self.onKeyChordEvent {
                    onKeyChordEvent(chord, true)
                } else {
                    self.onKeyChord?(chord)
                }
            }
        } else {
            DispatchQueue.main.async {
                self.lastInputDescription = "\(bindingKey.displayName) (Unassigned)"
            }
        }

        if settings.joyConRumbleEnabled {
            playRumble(on: controller)
        }
    }

    private static func isHoldableModifierChord(_ chord: KeyChord) -> Bool {
        guard chord.modifiers.isEmpty else { return false }
        // KeyCodes for modifiers; include Fn.
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        return modifierKeyCodes.contains(chord.keyCode)
    }

    private func handleDpad(controller: GCController, x: Float, y: Float) {
        let id = ObjectIdentifier(controller)
        var state = stickStates[id] ?? StickState()

        let threshold: Float = 0.5
        let reset: Float = 0.2

        updateAxis(
            value: x,
            positiveInput: .dpadRight,
            negativeInput: .dpadLeft,
            state: &state.dpadX,
            threshold: threshold,
            reset: reset,
            controller: controller
        )
        updateAxis(
            value: y,
            positiveInput: .dpadUp,
            negativeInput: .dpadDown,
            state: &state.dpadY,
            threshold: threshold,
            reset: reset,
            controller: controller
        )

        stickStates[id] = state
    }

    private func playRumble(on controller: GCController) {
        guard let haptics = controller.haptics else { return }
        let id = ObjectIdentifier(controller)
        let engine: CHHapticEngine

        if let cached = hapticEngines[id] {
            engine = cached
        } else {
            guard let created = haptics.createEngine(withLocality: .default) else { return }
            engine = created
            hapticEngines[id] = engine
        }

        let intensity = Float(max(0.0, min(1.0, settings.joyConRumbleStrength)))
        let sharpness: Float = 0.5
        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensityParam, sharpnessParam], relativeTime: 0)

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic: \(error)")
        }
    }

    private func handleStick(controller: GCController, isLeft: Bool, x: Float, y: Float) {
        let id = ObjectIdentifier(controller)
        var state = stickStates[id] ?? StickState()

        let threshold: Float = 0.5
        let reset: Float = 0.2

        if isLeft {
            updateAxis(
                value: x,
                positiveInput: .leftStickRight,
                negativeInput: .leftStickLeft,
                state: &state.leftX,
                threshold: threshold,
                reset: reset,
                controller: controller
            )
            updateAxis(
                value: y,
                positiveInput: .leftStickUp,
                negativeInput: .leftStickDown,
                state: &state.leftY,
                threshold: threshold,
                reset: reset,
                controller: controller
            )
        } else {
            updateAxis(
                value: x,
                positiveInput: .rightStickRight,
                negativeInput: .rightStickLeft,
                state: &state.rightX,
                threshold: threshold,
                reset: reset,
                controller: controller
            )
            updateAxis(
                value: y,
                positiveInput: .rightStickUp,
                negativeInput: .rightStickDown,
                state: &state.rightY,
                threshold: threshold,
                reset: reset,
                controller: controller
            )
        }

        stickStates[id] = state
    }

    private func updateAxis(
        value: Float,
        positiveInput: JoyConInput,
        negativeInput: JoyConInput,
        state: inout AxisState,
        threshold: Float,
        reset: Float,
        controller: GCController
    ) {
        if value > threshold {
            if !state.positiveActive {
                handleRawInput(positiveInput, controller: controller)
            }
            state.positiveActive = true
            state.negativeActive = false
        } else if value < -threshold {
            if !state.negativeActive {
                handleRawInput(negativeInput, controller: controller)
            }
            state.negativeActive = true
            state.positiveActive = false
        }

        if abs(value) < reset {
            state.positiveActive = false
            state.negativeActive = false
        }
    }

    private func resolveSide(for input: JoyConInput, controller: GCController) -> JoyConSide {
        // Only treat a controller as "micro" for side resolution when it *only* exposes the micro profile.
        // Some controllers (e.g. "Joy-Con (L/R)") can expose multiple profiles simultaneously; in that case
        // using the micro side heuristic can mis-classify left-side inputs as right-side and break bindings.
        if controller.microGamepad != nil, controller.extendedGamepad == nil, controller.gamepad == nil {
            return microGamepadSides[ObjectIdentifier(controller)] ?? .right
        }

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

    private func resolveMicroGamepadSide(_ controller: GCController) -> JoyConSide {
        let name = controller.vendorName?.lowercased() ?? ""
        if name.contains("(l)") || name.contains(" left") || name.contains("left ") {
            return .left
        }
        if name.contains("(r)") || name.contains(" right") || name.contains("right ") {
            return .right
        }

        DispatchQueue.main.async {
            self.hasUnknownMicroGamepadSide = true
        }
        return .right
    }

    private func scheduleConfigureRetry(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        let attempts = configurationRetries[id] ?? 0
        guard attempts < 15 else { return }
        configurationRetries[id] = attempts + 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            guard self.joyCons.contains(where: { $0 == controller }) else { return }

            if controller.extendedGamepad == nil, controller.gamepad == nil, controller.microGamepad == nil {
                self.scheduleConfigureRetry(controller)
                return
            }

            self.configureController(controller)
        }
    }

    private func updateControllerProfilesDescription() {
        guard !joyCons.isEmpty else {
            controllerProfilesDescription = ""
            return
        }

        controllerProfilesDescription = joyCons.map { controller in
            let name = controller.vendorName ?? "Unknown"
            var profiles: [String] = []
            if controller.extendedGamepad != nil { profiles.append("extended") }
            if controller.gamepad != nil { profiles.append("gamepad") }
            if controller.microGamepad != nil { profiles.append("micro") }
            profiles.append("physical")
            if profiles.isEmpty { profiles.append("none") }
            return "\(name) [\(profiles.joined(separator: ","))]"
        }.joined(separator: " · ")
    }
}

private struct AxisState {
    var positiveActive = false
    var negativeActive = false
}

private struct StickState {
    var leftX = AxisState()
    var leftY = AxisState()
    var rightX = AxisState()
    var rightY = AxisState()
    var dpadX = AxisState()
    var dpadY = AxisState()
}
