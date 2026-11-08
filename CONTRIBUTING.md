# Contributing to Meowy

Thanks for considering a contribution. Meowy is a small macOS menu-bar app built with Swift and AppKit.

## Requirements

- macOS 13 or later
- Swift and the macOS Command Line Tools (`xcode-select --install`)

## Build and run

```bash
./build.sh
open Meowy.app
```

This compiles all Swift sources in `Sources/CATApp/` with `swiftc`, assembles the app bundle in `Meowy.app`, and ad-hoc signs it.

The generated `Meowy.app` and `.build/` directory are ignored by Git. Do not commit them.

## Project layout

- `Sources/CATApp/CATApp.swift` - AppKit UI, panels, timers, agent monitoring, jokes, and music features
- `Sources/CATApp/CatSimulation.swift` - Pure simulation logic for cat movement and desktop/dock geometry
- `Sources/CATApp/SpriteSheet.swift` - Sprite sheet parsing and rendering helpers
- `Resources/` - Embedded images, audio, and bundled assets
- `Info.plist` - App bundle metadata
- `build.sh` - Complete build script
- `.github/workflows/` - CI build/test and release automation

## Development guidelines

- Keep changes focused. Avoid mixing refactors with feature work unless they are directly related.
- Prefer small, testable logic in `CatSimulation.swift` or helper types over embedding calculations in UI code.
- Follow the existing naming and style conventions.
- Preserve current user-facing behavior unless the change intentionally changes it and documents the reason.
- Do not add third-party dependencies unless there is a strong reason.
- Avoid committing generated files, binary assets, or large temporary files.

## Testing

There is no separate test suite yet. At minimum:

```bash
./build.sh
```

Confirm the command exits successfully and the app bundle is created. Then launch `Meowy.app` and verify the changed feature works.

For changes to movement or geometry logic, add targeted manual checks or introduce small XCTest coverage if appropriate.

## Pull requests

1. Fork and create a branch from `main`.
2. Make and test your changes.
3. Update documentation if user-facing behavior changes.
4. Open a pull request using the provided template.
5. Respond to review feedback promptly.

Commit messages should be clear and descriptive. Conventional commit prefixes such as `feat:`, `fix:`, `docs:`, and `ci:` are welcome.

## Reporting issues

Use the bug report or feature request issue templates when possible. Include macOS version, Meowy version, reproduction steps, and any useful logs or screenshots.

## Licensing

This repository does not currently include a `LICENSE` file. Please open an issue before reusing or redistributing large portions of the code or before contributing significant changes.