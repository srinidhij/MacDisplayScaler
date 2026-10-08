# Architecture

## Pipeline

1. A virtual display is created with only the requested "looks like" size
   (`hiDPI = 1`, 120 Hz and 60 Hz variants), so the size is its default mode.
2. The physical panel's mode is saved, then the panel is switched to its native
   resolution at its fastest refresh rate (mirroring keeps 120 Hz only if the
   panel is already at 120 Hz).
3. The panel is mirrored onto the virtual display with
   `CGConfigureDisplayMirrorOfDisplay`. The panel is driven at the virtual's 2x
   backing size and downsampled to its native 3440×1440.
4. Teardown (`disable()`): unmirror → wait for the mirror set to clear →
   destroy the virtual → re-apply the saved panel mode.

Changing size is `disable()` followed by `enable()` at the new size.

## Display changes

`MenuBarViewModel` registers a display reconfiguration callback and acts 3 s
after the last change (`PrivateHiDPIGateway.reconcileAction`):

- Panel offline (unplugged, switched off, other input): `disable()`, since the
  virtual would otherwise stay behind as an invisible extended display. An
  unconfirmed size is dropped.
- Panel online but no longer mirroring the virtual: `disable()`.
- Still mirrored but below the panel's fastest native refresh: re-create at
  the same size, without a countdown. If the panel stays slow it is not retried
  until it reconnects.
- The saved default's panel comes online: the saved size is applied.

Other displays joining the mirror set are left alone; macOS adds the built-in
panel when the lid opens.

## Components

```
MenuBarView / MenuBarViewModel      SwiftUI UI; display picker, size rows, Keep countdown
  DisplayManager                    facade: refresh, modes, apply, restore
    DisplayDetector                 CGGetOnlineDisplayList (includes mirrored panels), native size
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
  together with the panel it was confirmed on (`privateDefaultDisplay`, EDID
  vendor-model-serial). Only that size is auto-applied, with no countdown, at
  launch and when that panel reconnects, and never to another display. A size
  saved without a panel belongs to the Dell. With no saved default nothing is
  applied automatically.
- The launch-time mode of the first external panel is stored for Restore
  Defaults. Modes are re-found by geometry, so an IO mode ID never selects
  another display's mode.
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
- `LiveProbe test <id> <w> <h>` on hardware: enable, check `link=` shows the
  native size and refresh while mirrored, tear down, check the panel returned to
  its previous mode.
- Manual: each size row, Keep and timeout, Restore Defaults, relaunch with a
  saved default, login item, unplug and replug the panel, display sleep and
  wake.
