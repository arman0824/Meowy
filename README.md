# Meowl for macOS

## Build and run

From this directory:

```bash
./build.sh
open Meowl.app
```

The app runs as a menu-bar-only application. The cat follows the global macOS cursor, uses the same pixel-art spritesheet and directional movement, and includes the same idle, sleeping, alert, and scratching behaviors.

Click or right-click the cat menu icon to open:

- **Start Meowl**
- **Stop Meowl**
- **Cat size** slider from 0.5× to 2.5×
- **Quit Meowl**

The app stores its last cat state and size in the app’s `UserDefaults` under `meowl-cat` and `meowl-cat-scale`. Reduced Motion disables the pet, and the app is intended for macOS desktop screens.
