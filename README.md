# JoyConCode

**Joy-Con to keyboard mapping for Claude Code/Codex CLI on macOS.**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

<!-- Add a demo GIF here: ![Demo](assets/demo.gif) -->

JoyConCode is a macOS menubar app that listens to Joy-Con inputs and translates them into keyboard shortcuts — letting you control Claude Code (or Codex CLI) without touching the keyboard.

## Features

- **Joy-Con support** — custom button mapping to any keyboard shortcut
- **Optional rumble feedback** — on input and/or hook-triggered
- **Single instance enforcement** — prevents duplicate instances when launched via hooks
- **Menubar-only app** — no dock icon, stays out of the way

## Installation

### Download

Grab the latest `.dmg` from [Releases](../../releases), open it, and drag JoyConCode to Applications.

### Build from Source

```bash
git clone https://github.com/slowfastai/JoyConCode.git
cd JoyConCode
xcodebuild -project JoyConCode.xcodeproj -scheme JoyConCode -configuration Release build
```

## Setup

1. **Launch** JoyConCode — it appears as a controller icon in your menubar
2. **Grant Accessibility access** — go to System Settings > Privacy & Security > Accessibility and enable JoyConCode (required for keyboard simulation)
3. **Enable the master toggle** in the menubar popover
4. **Enable Joy-Con Input** and configure your mapping

## Claude Code Integration

JoyConCode supports both `joyconcode://` and the legacy `gesturecode://` URL scheme.

### Hook-Triggered Rumble

You can trigger a short Joy-Con rumble on submit via Claude Code hooks. Add this to `~/.claude/settings.json` (global) or `.claude/settings.json` (project-specific):

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

The `-g` flag prevents macOS from switching desktops when the hook runs.

## Configuration

Open the settings panel from the menubar popover:

- **Joy-Con** — enable input, configure mapping, and rumble settings

## Joy-Con Support

JoyConCode can listen to Joy-Con inputs and map them to any keyboard key or modifier combo. Open the Settings panel and click **Configure Joy-Con Mapping**.

## License

MIT — SlowFast AI
