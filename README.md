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

The build script compiles the Swift sources, creates `Meowy.app`, bundles the cat sprites, and applies an ad-hoc local signature.

## Use Meowy

Click the cat icon in the menu bar to choose:

- **Follow Cursor** — follows the mouse around your desktop.
- **Live on Dock** — wanders along the Dock, pauses to scratch or relax, and takes occasional naps.
- **Start Meowy** / **Stop Meowy** — one button toggles the cat on or off.
- **Size** — adjusts the cat from 50% to 250%.
- **Speed** — adjusts movement from 25% to 200%.
- **Quit Meowy**

Meowy remembers its position, size, and selected mode. Reduced Motion pauses the pet.
