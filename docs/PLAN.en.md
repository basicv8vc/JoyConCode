# Plan: Joy-Con Custom Mapping + Rumble + Claude Code Hook Rumble

## Summary
Add Joy-Con support using Apple’s GameController framework, with a dedicated mapping modal to fully customize button bindings (supporting any keyboard key and modifier combinations). Joy-Con input is gated by the existing master enable toggle. Provide rumble feedback on each action with adjustable strength. Add a new URL scheme endpoint so Claude Code’s `UserPromptSubmit` hook can trigger a short Joy-Con rumble.

## Public Interfaces / Type Changes
- New service: `JoyConManager` (ObservableObject)
- New settings in `AppSettings`:
  - `joyConEnabled: Bool` (default `false`)
  - `joyConRumbleEnabled: Bool` (default `true`)
  - `joyConRumbleStrength: Double` (default `0.6`)
  - `joyConStickMode: JoyConStickMode` (`.dpad` / `.off`)
  - `joyConBindings: [JoyConInput: KeyChord]` (persisted as Data)
- New types:
  - `JoyConInput: String, CaseIterable, Codable`
  - `KeyChord: Codable` (`keyCode: UInt16`, `modifiers: CGEventFlags`)
  - `JoyConStickMode: String, CaseIterable`
- `MenuBarView` / `SettingsView` accept `JoyConManager`
- `KeyboardSimulator` adds `simulateKey(chord:)`

## URL Scheme Extension
- Add: `joyconcode://joycon/rumble`
- Behavior: triggers one short rumble
- Gated by `settings.isEnabled && settings.joyConEnabled && settings.joyConRumbleEnabled`
- If no Joy-Con connected, ignore silently

## Mapping Model
`JoyConInput` covers all bindable inputs (buttons + stick directions):
- `dpadUp`, `dpadDown`, `dpadLeft`, `dpadRight`
- `buttonA`, `buttonB`, `buttonX`, `buttonY`
- `leftShoulder`, `rightShoulder`
- `leftTrigger`, `rightTrigger`
- `leftThumbstickButton`, `rightThumbstickButton`
- `buttonMenu` (Plus), `buttonOptions` (Minus)
- `buttonHome`, `buttonCapture` (if available)
- `leftStickUp`, `leftStickDown`, `leftStickLeft`, `leftStickRight`
- `rightStickUp`, `rightStickDown`, `rightStickLeft`, `rightStickRight`

Unbound inputs do nothing.

## Stick Handling
- If `joyConStickMode == .dpad`:
  - Map stick directions to corresponding `JoyConInput`.
  - Use threshold + edge-triggering (example: trigger at 0.5, reset at 0.2).
- If `joyConStickMode == .off`: ignore sticks.

## Action Trigger + Rumble
On input:
1. Check `settings.isEnabled && settings.joyConEnabled`.
2. Look up `KeyChord` for the `JoyConInput`.
3. Call `keyboardSimulator.simulateKey(chord:)`.
4. Update `keyboardSimulator.lastKeyPressed`.
5. If `joyConRumbleEnabled`, play a short transient rumble with strength `joyConRumbleStrength`.

Rumble uses `controller.haptics` and a `GCHapticEngine`. If unsupported, skip.

## UI Changes
- Settings panel adds “Joy-Con” section:
  - Enable Joy-Con Input (toggle)
  - Rumble Feedback (toggle)
  - Rumble Strength (slider)
  - Joy-Con Stick Mode (segmented)
  - “Configure Mapping” button
- “Configure Mapping” opens a dedicated mapping modal:
  - Group inputs by category (buttons / D-pad / sticks)
  - Each row shows current binding (e.g., `Shift+Enter`)
  - “Bind” enters capture mode
  - Capture listens to `keyDown` and requires a non-modifier key
  - “Clear” removes binding
  - Esc is not a cancel key (it can be bound)

## Implementation Steps
1. Add `JoyConManager`:
   - Start discovery, observe connect/disconnect
   - Filter Joy-Con by name
   - Support `GCExtendedGamepad` and `GCMicroGamepad`
   - Map inputs to `JoyConInput`, invoke callback
2. `AppDelegate`:
   - Create `JoyConManager`
   - Bind action callback to keyboard simulation + rumble
   - Extend URL handler for `joyconcode://joycon/rumble`
3. `KeyboardSimulator`:
   - Add `simulateKey(chord:)`
   - Add chord display helper
4. Mapping modal UI:
   - Read/write `settings.joyConBindings`
   - Implement bind/capture/clear flow
5. `AppSettings`:
   - Add fields and UserDefaults persistence
6. `Info.plist`:
   - Add `NSBluetoothAlwaysUsageDescription`
7. README:
   - Document Joy-Con support, mapping UI, hook rumble

## Claude Code Hook Example
```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "open -g \"joyconcode://joycon/rumble\"", "timeout": 5 }]
      }
    ]
  }
}
```

## Test Scenarios
1. Connect Joy-Con, enable Joy-Con input, bind a key, and verify key press occurs.
2. Disable master toggle: Joy-Con input should not trigger.
3. Stick mode = D-pad: stick directions trigger; mode = Off: no trigger.
4. Rumble toggle/strength changes take effect.
5. Disconnect Joy-Con: status updates to disconnected.
6. Bind special keys (Esc/Enter/Tab/Arrows) and verify correct display/trigger.
7. `joyconcode://joycon/rumble` triggers rumble on `UserPromptSubmit`.
8. Bindings persist across app restart.

## Assumptions and Defaults
- Joy-Con input is opt-in (default off).
- Rumble is enabled by default at strength 0.6.
- Bindings support keyboard keys + modifier combos only.
- Unbound inputs are ignored.
- Only `UserPromptSubmit` hook is supported for rumble at this stage.
