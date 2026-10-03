# Architecture

## Pipeline

1. A virtual display is created with only the requested "looks like" size
   (`hiDPI = 1`, 120 Hz and 60 Hz variants), so the size is its default mode.
2. The physical panel is raised to its fastest native refresh rate, then its
   mode is saved.
3. The panel is mirrored onto the virtual display with
   `CGConfigureDisplayMirrorOfDisplay`. The panel is driven at the virtual's 2x
   backing size and downsampled to its native 3440×1440.
4. Teardown (`disable()`): unmirror → wait for the mirror set to clear →
   destroy the virtual → re-apply the saved panel mode.

Changing size is `disable()` followed by `enable()` at the new size.

## Components

```
MenuBarView / MenuBarViewModel      SwiftUI UI; display picker, size rows, Keep countdown
  DisplayManager                    facade: refresh, modes, apply, restore
    DisplayDetector                 CGGetOnlineDisplayList (includes mirrored panels)
    DisplayModeManager              list / current / verified mode set
    ScalingManager                  matches desired sizes to exposed modes
    ConfigurationStore              UserDefaults: launch-time mode, last selection
    RollbackManager                 confirm-or-restore timer
    AppLogger                       unified log + ~/Library/Logs/SimpleHiDPIScaler.log
  PrivateHiDPIGateway               enable / disable lifecycle, active-size tracking
  PrivateDefaultStore               saved default size, applied at launch
PrivateBridge (ObjC)                virtual-display create/destroy, mirror/unmirror
```

- Collaborators sit behind protocols so tests inject fakes; no test touches a
  real display.
- The virtual display is identified by vendor `0x5348` / model `0x4849`, which
  survives process restarts.
- The bridge keeps each virtual display's descriptor alive with it and sets a
  termination handler, which prunes the gateway's state when a virtual ends.
- Creation uses a unique serial per virtual display, a dedicated dispatch queue,
  and waits for the display to come online before mirroring. Only one creation
  runs at a time.
- Error codes from the bridge: `-10` begin, `-11`/`-12` configure, `-13`
  commit, `-20` never came online, `-30` creation already in flight, `-5`
  self-mirror.

## Persistence

- Only a size confirmed with **Keep** is saved (`privateDefaultWidth/Height`),
  and only that size is auto-applied at launch, with no countdown. With no saved
  default nothing is applied automatically.
- The launch-time mode is stored for Restore Defaults.
- The packaged app uses the `com.simplehidpiscaler.app` defaults domain and
  migrates settings from the bare binary's `SimpleHiDPIScaler` domain once.
- Open at login uses `SMAppService.mainApp` and needs the `.app` bundle.

## Safety

- Every manual change is followed by a 30-second Keep window; without Keep the
  virtual display is torn down and the panel restored.
- The picker lists physical panels only; virtual displays are never targets.
- Quitting does not restore a mirrored panel by itself. Use Disable for this
  display or Restore Defaults.

## Test plan

- `swift run SelfTest` / `swift test`: mode matching, display identification,
  rollback timing, with fakes.
- `LiveProbe test <id> <w> <h>` on hardware: enable, check the mirrored mode
  (`looks-like@backing`, refresh), tear down, check the panel returned to its
  previous mode.
- Manual: each size row, Keep and timeout, Restore Defaults, relaunch with a
  saved default, login item.
