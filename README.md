# SimpleHiDPIScaler

A macOS menu-bar app that makes text and UI larger on an external ultrawide
(built for the **Dell U3425WE, 3440×1440**) while the panel keeps running at its
native resolution. Text stays sharp because the UI is rendered at 2x and
downsampled to the panel.

No network, no telemetry, no accounts, no special permissions.

## How it works

The app creates a virtual display at the "looks like" size you pick (rendered
at 2x) and mirrors the physical panel onto it. Picking 2752×1152, for example,
renders a 5504×2304 image that is downsampled to 3440×1440.

| Row | Looks like | Rendered at |
|---|---|---|
| Native | 3440×1440 | 6880×2880 |
| Larger | 3008×1264 | 6016×2528 |
| Larger+ | 2752×1152 | 5504×2304 |
| Much Larger | 2560×1080 | 5120×2160 |

The panel's refresh rate is kept (120 Hz when the panel is at 120 Hz).

## Requirements

- Apple Silicon Mac, macOS 13+
- Swift 5.9+ toolchain (Xcode or Command Line Tools)
- External display on DisplayPort/HDMI in extended-display mode

## Install

```sh
scripts/build-app.sh --install     # builds ~/Applications/SimpleHiDPIScaler.app
open ~/Applications/SimpleHiDPIScaler.app
```

For development, `swift run SimpleHiDPIScaler` runs the same app as a bare
binary (no "Open at login").

## Use

1. Menu bar → display icon. Select the physical display.
2. Turn on the opt-in toggle, then **Enable HiDPI for this display**.
3. Click a size. It applies immediately (about 1–2 s of flicker).
4. Press **Keep** within 30 seconds, or the change rolls back. Keep also saves
   that size as the default, which is applied automatically at every launch
   without a countdown. **Clear** removes the saved default.
5. **Open at login** adds the app as a login item (approve it in System
   Settings → General → Login Items if macOS asks).

**Restore Defaults** and **Disable for this display** unmirror, remove the
virtual display, and put the panel back in its previous mode.

## Limitations

- Relies on undocumented macOS display APIs; it may break on any OS update and
  cannot be shipped through the App Store.
- Changing size re-creates the virtual display (a brief flicker).
- Quitting the app does not by itself restore the panel's mode; use Disable or
  Restore Defaults first.

## Build & test

```sh
swift build
swift run SelfTest   # hardware-free checks (Command Line Tools only)
swift test           # XCTest suite (needs full Xcode)
swift run LiveProbe dump   # prints every display and its modes
```

`LiveProbe test <displayID> <w> <h>` mirrors the display at a size for about
20 seconds, then tears down and restores it.

## Layout

```
Sources/PrivateBridge/             ObjC bridge to the virtual-display classes
Sources/SimpleHiDPIScalerCore/     detection, modes, gateway, rollback, config, logging
Sources/SimpleHiDPIScaler/         menu-bar UI and view model
Sources/SelfTest/, Sources/LiveProbe/, Tests/
scripts/                           build-app.sh, Info.plist
```

## License

MIT — see `LICENSE`.
