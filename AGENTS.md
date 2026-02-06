# Repository Guidelines

## Project Structure & Module Organization

- `JoyConCode/`: Swift (SwiftUI) menubar app source.
- `JoyConCode/App/`: app entry + `AppDelegate`.
- `JoyConCode/Views/`: UI (menubar popover, settings, mapping UI).
- `JoyConCode/Services/`: device + I/O logic (Joy-Con input, keyboard simulation).
- `JoyConCode/Models/`: settings and mapping data models.
- `JoyConCode/Resources/`: app resources.
- `JoyConCode.xcodeproj/`: Xcode project and shared schemes.
- `docs/`: lightweight planning docs (`docs/PLAN.en.md`, `docs/PLAN.zh.md`).
- `scripts/`: packaging helpers (DMG/release automation).

## Build, Test, and Development Commands

- Build (Release): `xcodebuild -project JoyConCode.xcodeproj -scheme JoyConCode -configuration Release build`
- Build (Debug): `xcodebuild -project JoyConCode.xcodeproj -scheme JoyConCode -configuration Debug build`
- Run locally: open `JoyConCode.xcodeproj` in Xcode and Run the `JoyConCode` scheme (menubar-only app).
- Create a DMG (requires `create-dmg`): `scripts/create-dmg.sh /path/to/JoyConCode.app`
- Release automation: `scripts/release.sh` is gitignored and intended for maintainers (codesign + notarization); do not add signing credentials to the repo.

## Coding Style & Naming Conventions

- Swift 5.9 / SwiftUI; use Xcode’s default formatting (4-space indentation).
- Types use `UpperCamelCase`; methods/properties use `lowerCamelCase`.
- Keep boundaries clear: UI in `JoyConCode/Views/`, hardware and keyboard simulation in `JoyConCode/Services/`, persisted config in `JoyConCode/Models/Settings.swift`.

## Testing Guidelines

- No automated test target is currently checked in.
- For PRs, include a short manual test note.
- Verify Joy-Con mapping works in foreground and background (including terminals).
- Verify Accessibility permission flow (required for keyboard simulation).
- If relevant, verify `joyconcode://joycon/rumble` hook behavior.

## Commit & Pull Request Guidelines

- Commit subjects generally follow `type: summary` (examples seen in history: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `ui:`).
- PRs should include: a brief rationale, testing steps (and macOS version), screenshots for UI changes, and call out any entitlement/permission-related changes.
- Do not include generated artifacts in PRs (`build/`, `.dmg`, `.xcarchive` are ignored by default).
