# SimpleHiDPIScaler

A minimal open-source macOS menu-bar app for making text/UI larger on a
natively connected external ultrawide — primarily the
**Dell U3425WE (3440×1440)** — while keeping the panel at its native physical
resolution.

Two tiers, same safety rules (**save → verify → apply → 10-s confirm or
auto-rollback**):

1. **Public (default):** list what macOS exposes via Quartz Display Services,
   let you pick, roll back if you don't confirm.
2. **Private prototype (explicit opt-in, off by default):** synthesize true
   HiDPI via a gated virtual display + mirror path (see below). Added only
   after the user approved it, when public APIs proved insufficient.

No DDC, no EDID patching, no HDR, no network, no telemetry, no updater, no
accounts.

> **Honest limitation (read first):** on Apple Silicon, macOS only exposes
> HiDPI modes for roughly 4K-and-up panels. There is **no public API** that
> synthesizes new HiDPI backing stores for a 3440×1440 panel, so the public
> rows read *not exposed by macOS* on most setups instead of faking HiDPI.
> `ARCHITECTURE.md` §2 explains why. The private prototype exists precisely
> for that gap — and carries the costs documented below.

## Requirements

- Apple Silicon Mac, macOS 13+
- Swift 5.9+ toolchain (Xcode or Command Line Tools)
- Dell U3425WE (or any external) over DisplayPort/HDMI in extended-display mode

## Build & test

```sh
swift build          # builds PrivateBridge (ObjC) + Core + menu-bar app + SelfTest
swift run SelfTest   # hardware-free verification (works with CLT only, no Xcode)
swift test           # XCTest suite (requires full Xcode; same assertions as SelfTest)
```

`Sources/SimpleHiDPIScalerCore/` holds all testable logic. `SelfTest` mirrors
`Tests/SimpleHiDPIScalerTests/` assertion-for-assertion for environments where
`XCTest.framework` is unavailable (Command Line Tools only).

## Run as a menu-bar app

The SPM executable contains the full `MenuBarExtra` app. For day-to-day use,
bundle it as an `.app` with Xcode:

1. Create a new Xcode project → macOS → App → SwiftUI, name
   `SimpleHiDPIScaler`, bundle id e.g. `com.example.simplehidpiscaler`.
2. Add `Sources/PrivateBridge/*.{h,m}`, `Sources/SimpleHiDPIScalerCore/*.swift`
   and `Sources/SimpleHiDPIScaler/*.swift` to the target.
3. Set `Application is agent (UIElement)` (`LSUIElement = YES`) so there is no
   dock icon — menu bar only.
4. Attach `SimpleHiDPIScaler.entitlements` (intentionally empty — zero
   permissions) and sign/notarize as usual.
5. `swift test` (Xcode) or `swift run SelfTest` (CLT) runs the suite against the same sources.

## Using it

```
SimpleHiDPIScaler (menu bar)
  Display: [ DELL U3425WE — 3440×1440 (ID 3) ▾ ]   # physical panels only
  Current: 3440 × 1440 @ 3440 × 1440 px
  Refresh: 120 Hz   HiDPI: no   ID 3 · 3440×1440 px
  Detected: Dell U3425WE ✓  (or "Possible Dell 34″ UWQHD" when mirrored names go generic)
  Scaling (public):
    ○ Native       3440 × 1440
    ○ Larger       not exposed by macOS
    ○ Much Larger  not exposed by macOS
  [ Apply ]  →  Keep this mode? 9…  [ Keep ]
  [ Restore Defaults ] [ Open Display Settings ] [ Clear logs ] [ Refresh ]
  Private HiDPI prototype (opt-in, off by default): …
```

- **Display picker lists physical panels only**, with IDs. Virtual
  `SimpleHiDPI *` displays are status, never targets — applying a public 1x
  mode to a virtual destroys its HiDPI-ness (observed live; now refused).
- **Apply** saves the current mode, verifies the target still exists, switches,
  and starts a **30-second countdown**. Confirm to keep; otherwise the previous
  mode is restored automatically. Quitting the app reverts public
  `CGDisplaySetDisplayMode` changes only; it does **not** undo the private
  mirror path — use the kill-switch / Restore Defaults for that.
- **Restore Defaults** re-applies the launch-time mode **and** tears down any
  private virtual for that display (kill-switch).
- If no HiDPI rows exist for your cable/GPU/macOS combination, that is the GPU
  telling the truth — try DisplayPort directly, then read `ARCHITECTURE.md` §2.

## Private HiDPI prototype (approved opt-in, off by default)

Public APIs cannot synthesize HiDPI for this panel, so the approved fallback is:

- `Sources/PrivateBridge/` (ObjC, private classes resolved at runtime via
  `NSClassFromString` — no link-time dependency): creates a `hiDPI=1` virtual
  display at the chosen "looks like" size (3440×1440 / 3008×1264 / 2752×1152 /
  2560×1080, each at 120 Hz and 60 Hz, 2x backing) and mirrors the physical Dell onto it with the
  **public** `CGConfigureDisplayMirrorOfDisplay`. The DCP downsamples 2x to
  the panel.
- `PrivateHiDPIGateway` (Swift): `privatePrototypeEnabled` defaults OFF;
  `enable()` / `disable()` lifecycle with kill-switch; creation runs off-main
  with wait-for-online; unique serial per creation; single-flight guards.
- Menu bar → "Private HiDPI prototype": Enable opt-in → Enable HiDPI for this
  display → **Keep within 30 s** or it auto-tears-down. Then click Larger /
  Larger+ / Much Larger — a click applies immediately (the display is re-created
  at that size, ~1–2 s flicker) → Keep. **Keep also saves that size as the
  default**, re-applied at every launch without a countdown ("Clear" removes it).
  `Restore Defaults` also tears down.
- **Open at login**: build the app bundle with `scripts/build-app.sh --install`
  (installs `~/Applications/SimpleHiDPIScaler.app`, menu-bar only, ad-hoc
  signed) and flip the "Open at login" toggle; approve it in System Settings →
  General → Login Items if macOS asks. Bare `swift run` binaries can't do this.
- Prerequisites: select the **physical** Dell (never a SimpleHiDPI entry) and
  set it to Native 3440×1440 first; one action at a time (no rapid retries).

Limits (all observed, not theoretical): needs explicit Keep for each manual
change; the pair runs at 120 Hz only if the panel is at 120 Hz before mirroring
(the app raises it automatically); breaks on OS updates; no App Store;
stale virtuals from killed processes can linger until torn down; the 2x-geometry
assumption for virtual modes is still being verified (see `ARCHITECTURE.md`
§4). Keep it off unless you need it; public rows remain the default.

## Project layout

```
Sources/PrivateBridge/
  PrivateBridge.h/.m         C ABI: availability probe, create/destroy, mirror/unmirror
  CGVirtualDisplayPrivate.h  (private, non-public) reverse-engineered interfaces
Sources/SimpleHiDPIScalerCore/
  DisplayManager.swift        facade (DisplayManaging)
  DisplayDetector.swift       enumeration (DisplayDetecting)
  DisplayModeManager.swift    list/current/verified-set (DisplayModeManaging)
  ScalingManager.swift        desired→exposed matching; scaling rows REQUIRE HiDPI
  ConfigurationStore.swift    UserDefaults reversible state
  RollbackManager.swift       10 s confirm-or-restore
  AppLogger.swift             local-only logging
  Models.swift                DisplayInfo / DisplayModeInfo (isHiDPI = pixels > logical)
  Protocols.swift             all protocols + ScalingOption
  PrivateHiDPIGateway.swift   opt-in gateway (refuses unless enabled)
Sources/SimpleHiDPIScaler/
  SimpleHiDPIScalerApp.swift  MenuBarExtra UI + ViewModel (physical-only picker, guards)
Sources/SelfTest/
  main.swift                  CLT runner mirroring the XCTest suite
Tests/SimpleHiDPIScalerTests/
  ModeSelectionTests.swift / DisplayIdentificationTests.swift / RollbackTests.swift
```

## Permissions

None requested. See `ARCHITECTURE.md` §3 and `PRIVACY.md`. If macOS ever
prompts for anything while running this app, treat it as a bug and file it.

## License

MIT — see `LICENSE`.
