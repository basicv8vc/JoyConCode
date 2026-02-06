# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

JoyConCode is a macOS menubar app (Swift/SwiftUI) that maps Nintendo Joy-Con controller inputs to keyboard shortcuts, designed for hands-free control of Claude Code / Codex CLI. It also supports hook-triggered haptic rumble via URL schemes (`joyconcode://` and `gesturecode://`).

Requires macOS 14+, Swift 5.9+, Xcode 15+.

## Build Commands

```bash
# Build (Release)
xcodebuild -project JoyConCode.xcodeproj -scheme JoyConCode -configuration Release build

# Build (Debug)
xcodebuild -project JoyConCode.xcodeproj -scheme JoyConCode -configuration Debug build

# Archive for distribution
xcodebuild -project JoyConCode.xcodeproj -scheme JoyConCode -configuration Release -archivePath build/JoyConCode.xcarchive archive

# Full release (archive, sign, notarize, DMG, GitHub release)
./scripts/release.sh
```

There are no tests or linting configured in this project.

## Architecture

```
JoyConCode/
├── App/           — App entry point and lifecycle
├── Views/         — SwiftUI views (menubar popover, settings, mapping UI)
├── Services/      — Controller management and keyboard simulation
├── Models/        — Settings persistence and Joy-Con binding types
└── Resources/     — Assets
```

### Key Layers

**App Layer** — `JoyConCodeApp` is the `@main` SwiftUI entry; `AppDelegate` manages the menubar (`NSStatusBar`), wires up services, handles URL scheme events (`joyconcode://joycon/rumble`), and implements focus restoration to prevent desktop switching when hooks trigger the app.

**Services Layer** — `JoyConManager` uses Apple's `GameController` framework to discover Joy-Cons via Bluetooth, reads inputs across multiple controller profiles (`GCExtendedGamepad`, `GCGamepad`, `GCMicroGamepad`, raw `GCPhysicalInputProfile`), applies 50ms stick debouncing with threshold-based edge triggering, and drives `CoreHaptics` rumble. `KeyboardSimulator` synthesizes keyboard input using raw `CGEvent` API (not AppKit) for terminal compatibility, with special handling for Shift+Tab (HID backtab escape sequence) and Fn+Arrow key normalization.

**Models Layer** — `AppSettings` is an `ObservableObject` singleton persisted to `UserDefaults`. Bindings use a side-aware `JoyConBindingKey` (side + input → `KeyChord`) stored as JSON-encoded `Codable` types. V1→V2 migration runs automatically on init.

### Data Flow

```
Joy-Con (Bluetooth)
  → GameController framework
  → JoyConManager (input filtering, debounce, binding lookup)
  → onKeyChordEvent callback
  → KeyboardSimulator (CGEvent synthesis)
  → Target app receives keystrokes
```

### Important Conventions

- **No app sandbox** — disabled in entitlements to allow CGEvent keyboard simulation and Bluetooth access
- **LSUIElement = true** — menubar-only, no dock icon
- **Modifier-only bindings** — Joy-Con buttons can be bound to modifier keys (Shift, Cmd, etc.) with press-and-hold semantics
- **Accessibility required** — CGEvent-based keyboard simulation requires Accessibility permission; the app polls permission status on a 2-second timer
- **URL scheme focus handling** — captures the previously active app before URL activation and restores focus after 500ms
