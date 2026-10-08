# AGENTS.md

macOS menu-bar app (Swift Package) that gives a 3440×1440 external display a
larger, sharp UI: it creates a virtual display at a chosen "looks like" size
(rendered at 2x) and mirrors the physical panel onto it. See `README.md` for
use and `ARCHITECTURE.md` for the pipeline.

## Commands

```sh
swift build                          # all targets
swift run SelfTest                   # hardware-free checks (works with Command Line Tools)
swift test                           # XCTest; fails here: full Xcode is not installed
swift run LiveProbe dump             # list displays + modes (read-only); link= is the timing sent over the cable
swift run LiveProbe test <id> <w> <h>   # live mirror test, then teardown + restore
swift run LiveProbe restore <id> [max]  # put panel back to native 3440x1440 (max = fastest refresh)
scripts/build-app.sh --install       # build + ad-hoc sign ~/Applications/SimpleHiDPIScaler.app
```

## Layout

- `Sources/PrivateBridge/` — ObjC bridge to the undocumented virtual-display classes
  (runtime-resolved). Only `PrivateHiDPIGateway` calls it.
- `Sources/SimpleHiDPIScalerCore/` — testable logic: detection, modes, gateway,
  rollback, config, `PrivateDefaultStore`, logging.
- `Sources/SimpleHiDPIScaler/SimpleHiDPIScalerApp.swift` — SwiftUI menu-bar UI + view model.
- `Sources/LiveProbe/`, `Sources/SelfTest/`, `Tests/`, `scripts/`.

## Working on display code

These steps change real display configuration. A bad teardown can leave the
panel at the wrong mode.

- Test live changes with `LiveProbe`, which has a 40 s watchdog that tears down
  and restores. Check state afterwards with `LiveProbe dump`.
- Before killing the app or the probe mid-run, expect the mirror to drop; verify
  the Dell is `mirror=false` at 3440×1440 and fix with `LiveProbe restore 3`.
- Teardown must go through `PrivateHiDPIGateway.disable()` (unmirror → wait for
  mirror set to clear → destroy virtual → re-apply saved panel mode). Quitting
  does not restore a mirrored panel by itself.
- The virtual's mode list can't be switched while mirrored; a size change is
  `disable()` + `enable()` with only the new size.
- Mirroring keeps 120 Hz only if the panel already runs at 120 Hz; `enable()`
  first switches it to its fastest native mode. A mirrored panel's mode can't be
  changed in place (the configuration is refused), so raising its refresh later
  is `disable()` + `enable()`.
- Check sharpness and refresh with `link=` in `LiveProbe dump`: mirrored at any
  size it should read 3440x1440 at 120 Hz. The CG mode only shows the looks-like
  size. After a quit, macOS leaves the panel at a plain 2560×1080 mode.
- The panel's native size comes from its native-flagged mode
  (`DisplayModeManager.nativeModes`); `CGDisplayPixelsWide` is the current
  looks-like size.
- The app handles display changes 3 s after the last one: it tears the virtual
  down when its panel goes offline or stops mirroring it, re-creates once when a
  mirrored panel runs below its native refresh, and re-applies the saved default
  when that panel comes back. Other displays joining the mirror (the built-in
  panel when the lid opens) are left alone.
- A mirrored panel is `active=false` but still online: enumerate with
  `CGGetOnlineDisplayList`, never the active list.
- Identify our virtual display by vendor `0x5348` / model `0x4849`
  (`DisplayInfo.isOwnVirtual`), not by name.
- Opt-in (`privatePrototypeEnabled`) is per defaults domain: `com.simplehidpiscaler.app`
  for the .app, `SimpleHiDPIScaler` for a bare binary, `LiveProbe` for the probe.

## Conventions

- No network code, no telemetry, no new entitlements or permissions, no
  dependencies. Update `SECURITY.md` / `PRIVACY.md` if that ever changes.
- Keep docs as current-state reference: no history, post-mortems or "observed
  live" notes.
- The only auto-applied display state is a size the user confirmed with Keep,
  and only on the display it was confirmed on.
- Every manual change gets the 30 s Keep/rollback window (`keepTimeoutSeconds`).

## Environment gotchas

- zsh does not word-split unquoted variables (`for s in "a b"` passes one arg).
- macOS has no `timeout` command.
- XCTest is unavailable, so `swift test` can't run; use `SelfTest`.
