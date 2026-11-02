# Meowl for macOS

## Build and run

From this directory:

```bash
./build.sh
open Meowl.app
```

The app runs as a menu-bar-only application and uses the same pixel-art spritesheet and directional movement. Choose between two cat lives:

- **Follow Cursor** — the cat follows the global macOS cursor anywhere across your desktop.
- **Live on Dock** — the cat wanders in short playful trips at a steady pace, sits for 10–15 seconds to scratch or relax, takes random 2–3 minute naps, and then continues exploring like a real desktop pet.

Click or right-click the cat menu icon to open:

- **Start Meowl**
- **Stop Meowl**
- **Follow Cursor** or **Live on Dock**
- **Cat size** slider from 0.5× to 2.5×
- **Quit Meowl**

The app stores its last cat state, size, and behavior mode in `UserDefaults` under `meowl-cat`, `meowl-cat-scale`, and `meowl-cat-mode`. Reduced Motion disables the pet, and the app is intended for macOS desktop screens.
