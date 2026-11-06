# Meowy for macOS

Meowy is a small menu-bar app that puts a playful pixel-art cat on your Mac desktop.

## Requirements

- macOS 13 or later
- Swift and the macOS Command Line Tools

If Swift is not installed, run:
```bash
xcode-select --install
```

## Build and run
Clone the repository, enter the project directory, and run:

```bash
./build.sh
open Meowy.app
```

The build script compiles the Swift sources, creates `Meowy.app`, bundles the cat sprites and app icon, and applies an ad-hoc local signature.

## Use Meowy

Click the cat icon in the menu bar to choose:

- **Start Meowy** / **Stop Meowy** — one button toggles the cat on or off.
- **Follow Cursor** — follows the mouse around your desktop.
- **Live on Dock** — wanders along the Dock, pauses to scratch or relax, and takes occasional naps.
- **Jokes** — toggles the 5-minute joke bubble while docked.
- **Joke Source** — choose between Dark Jokes, Dad Jokes, Advice, and Quotes.
- **Agents** — toggles terminal-agent status bubbles.
- **Action Items** — set reminders and pomodoro timers that appear in floating bubbles.
- **Cat Name…** — rename the cat; hovering over the cat shows its name.
- **Size** — adjusts the cat from 50% to 250%.
- **Speed** — adjusts movement from 25% to 200%.
- **Quit Meowy**

Meowy remembers its position, size, speed, mode, joke/agent preferences, and selected cat name. Reduced Motion pauses the pet.

## Agent status
When **Agents** is enabled, Meowy monitors Claude Code automatically:
- Shows “Claude: Thinking” while waiting for a response.
- Shows the current Claude activity/task while working.
- Shows “Claude: work complete” with a notification sound, highlighted in green, then fades after about 7 seconds.

Supported agent processes include Claude Code.

## Reminders and pomodoro
- **Reminder…** — schedule a reminder by minutes from now or by a specific time of day.
- **Pomodoro…** — start a countdown timer with hours and minutes; the cat shows remaining time and plays a sound when it finishes.

All floating message bubbles (jokes, agent status, reminders, pomodoro) use consistent styling and remain visible without overlapping.

## Development
Regenerate the app icon with:
```bash
swiftc -swift-version 5 -O -framework AppKit -framework CoreGraphics -framework ImageIO tools/MakeIcon.swift -o /tmp/MakeIcon
/tmp/MakeIcon /tmp/meowy.iconset
iconutil -c icns /tmp/meowy.iconset -o Resources/Meowy.icns
./build.sh
```
