import Foundation
import GameController
import CoreHaptics

class JoyConManager: ObservableObject {
    @Published var isConnected = false
    @Published var connectedCount = 0
    @Published var lastInputDescription = ""
    @Published var isInMappingMode = false
    @Published var hasUnknownMicroGamepadSide = false

    private let settings = AppSettings.shared
    private var joyCons: [GCController] = []
    private var hapticEngines: [ObjectIdentifier: CHHapticEngine] = [:]
    private var stickStates: [ObjectIdentifier: StickState] = [:]
    private var microGamepadSides: [ObjectIdentifier: JoyConSide] = [:]

    var onKeyChord: ((KeyChord) -> Void)?
    var onInput: ((JoyConBindingKey) -> Void)?

    init() {
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
        guard settings.isEnabled, settings.joyConEnabled, settings.joyConRumbleEnabled else { return }
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
        updateConnectionState()
    }

    private func updateConnectionState() {
        DispatchQueue.main.async {
            self.connectedCount = self.joyCons.count
            self.isConnected = !self.joyCons.isEmpty
        }
    }

    private func isJoyCon(_ controller: GCController) -> Bool {
        let name = controller.vendorName?.lowercased() ?? ""
        let category = controller.productCategory.lowercased()
        return name.contains("joy-con") || name.contains("joy con") || category.contains("joy-con") || category.contains("joy con")
    }

    private func configureController(_ controller: GCController) {
        if let gamepad = controller.extendedGamepad {
            configureExtendedGamepad(gamepad, controller: controller)
        } else if let microGamepad = controller.microGamepad {
            configureMicroGamepad(microGamepad, controller: controller)
        }
    }

    private func configureExtendedGamepad(_ gamepad: GCExtendedGamepad, controller: GCController) {
        bindButton(gamepad.dpad.up, input: .dpadUp, controller: controller)
        bindButton(gamepad.dpad.down, input: .dpadDown, controller: controller)
        bindButton(gamepad.dpad.left, input: .dpadLeft, controller: controller)
        bindButton(gamepad.dpad.right, input: .dpadRight, controller: controller)

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
        let side = resolveMicroGamepadSide(controller)
        microGamepadSides[ObjectIdentifier(controller)] = side
        bindButton(microGamepad.dpad.up, input: .dpadUp, controller: controller)
        bindButton(microGamepad.dpad.down, input: .dpadDown, controller: controller)
        bindButton(microGamepad.dpad.left, input: .dpadLeft, controller: controller)
        bindButton(microGamepad.dpad.right, input: .dpadRight, controller: controller)

        bindButton(microGamepad.buttonA, input: .buttonA, controller: controller)
        bindButton(microGamepad.buttonX, input: .buttonX, controller: controller)
    }

    private func bindButton(_ button: GCControllerButtonInput?, input: JoyConInput, controller: GCController) {
        button?.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.handleRawInput(input, controller: controller)
        }
    }

    private func handleRawInput(_ input: JoyConInput, controller: GCController) {
        let side = resolveSide(for: input, controller: controller)
        let bindingKey = JoyConBindingKey(side: side, input: input)

        DispatchQueue.main.async {
            self.lastInputDescription = bindingKey.displayName
            self.onInput?(bindingKey)
        }

        // Mapping mode: never emit key events or rumble.
        guard !isInMappingMode else { return }

        guard settings.isEnabled, settings.joyConEnabled else { return }
        guard let chord = settings.joyConBindingsV2[bindingKey] else { return }

        DispatchQueue.main.async {
            self.lastInputDescription = "\(bindingKey.displayName): \(chord.displayString())"
            self.onKeyChord?(chord)
        }

        if settings.joyConRumbleEnabled {
            playRumble(on: controller)
        }
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
        if controller.microGamepad != nil {
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
}
