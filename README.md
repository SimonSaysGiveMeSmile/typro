# Typro

A macOS menu-bar app that watches your typing, detects typos using on-device spell-check, and auto-selects the wrong part of the word so you can fix it with a single Delete tap.

## How it works

```
You type:   "mistika "
Typro sees: "mista" is the common prefix with "mistake"
Typro selects: "ika" (the wrong suffix, 3 chars)
You press:  Delete → then type "ke"
Result:     "mistake "
```

The selection happens instantly after you type the word boundary (space or punctuation). No popup, no autocorrect — just a selection you can accept or ignore.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode command-line tools (`xcode-select --install`)

## Install

**Option 1 — prebuilt release (fastest)**

Grab the latest zip from [Releases](https://github.com/SimonSaysGiveMeSmile/typro/releases/latest), unzip it, and run:

```bash
./install.sh          # installs typro-fix CLI + zsh integration
open Typro            # launches the menu-bar app
```

**Option 2 — build from source**

```bash
git clone https://github.com/SimonSaysGiveMeSmile/typro
cd typro
swift run Typro
```

On first launch, Typro will ask for **Accessibility permission** — this is required to monitor keystrokes and post selection events.

> System Settings → Privacy & Security → Accessibility → enable **Typro**

Then relaunch with `swift run`.

## Website demo

The showcase is a React + TypeScript app powered by Node tooling.

```bash
cd website
npm install
npm run dev
```

Then open the local URL printed by Vite to try the browser demo and download the
project ZIP from the page.

## Preferences

Click the menu-bar icon → **Preferences…**

| Setting | Description |
|---|---|
| Enable/Pause | Toggle Typro on or off |
| Minimum word length | Skip short words (default: 4) |
| Language | Spell-check language |
| App filter | Run everywhere, only in listed apps, or everywhere except listed apps |

**Add Frontmost** in the app filter captures the bundle ID of whatever app is in front — handy for quickly adding your editor or browser.

## Architecture

| File | Role |
|---|---|
| `TyproApp.swift` | `NSApplication` entry point, menu-bar status item |
| `KeyMonitor.swift` | `CGEventTap` — captures keystrokes globally |
| `TypoEngine.swift` | Word buffer, orchestrates detection → selection |
| `SuggestionEngine.swift` | `NSSpellChecker` wrapper, common-prefix diff |
| `KeyPoster.swift` | Posts synthetic Shift+Arrow events to select text |
| `Settings.swift` | `UserDefaults`-backed preferences singleton |
| `PreferencesView.swift` | SwiftUI preferences window |
| `PermissionsHelper.swift` | Accessibility permission prompt |

## Limitations

- Works in apps that use standard macOS text input (NSTextField, web text fields, most editors). Terminal apps and games that bypass the input system may not respond to the synthetic arrow events.
- The selection is placed after the word boundary character (space/punct) is already typed. If you immediately start typing before Typro posts its events (~50 ms), the selection may land in the wrong place.
- Spell-check quality depends on `NSSpellChecker` and the selected language dictionary.
