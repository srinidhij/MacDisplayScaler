# Post-mortem — private HiDPI prototype, session of 2026-10-03

Diagnosis of why "the earlier build out of HiDPI scaler did not work", based on
`~/Library/Logs/SimpleHiDPIScaler.log` plus read-only CoreGraphics probes taken
after the fact. Companion to `ARCHITECTURE.md` (design) and `SECURITY.md`
(guarantees). Nothing in this pass created, mirrored, or destroyed a display.

## Verdict

**The architecture is sound and it worked.** A true-HiDPI virtual master
(6880×2880 backing, 3440×1440 logical) was mirrored onto the Dell and the panel
showed it. The failure is entirely in the *lifecycle*: the app never restores
the panel when the virtual goes away, and it can never switch the virtual's mode
while the pair is mirrored. The public tier is, as `ARCHITECTURE.md` §2c states,
impossible on this hardware — that part is not a bug.

Worse, the failure mode is *worse than doing nothing*: the panel was left at
2560×1080 1x instead of its native 3440×1440.

## Environment

| | |
|---|---|
| Host | Apple M5, macOS 27.0 (26A428) |
| Panel | DELL U3425WE — vendor `0x10ac`, model `0xa243`, serial `808736844` |
| Binary tested | `./.build/debug/SimpleHiDPIScaler` (bare SPM executable, no `.app` bundle) |
| Run window | launched 10:31 IST, last log line 10:32:23 IST, exited before 11:40 IST |
| Opt-in state | `privatePrototypeEnabled = 1`, domain `SimpleHiDPIScaler` |

## What the evidence shows

### 1. The prototype did work, once

`system_profiler SPDisplaysDataType` captured while the app was live:

```
SimpleHiDPI 3:  Resolution 6880x2880 · UI Looks like 3440x1440 @120Hz · Master Mirror
DELL U3425WE:   Resolution 6880x2880 · UI Looks like 3440x1440 @60Hz  · Hardware Mirror
```

The Dell was a hardware-mirror slave being driven at the virtual's 6880×2880
timing and downsampled to the panel. That is the entire goal, achieved. It
corresponds to the log line `display=3 private virtual=38 created+mirrored`.

This also **disproves** a hypothesis worth recording: `CGVirtualDisplayMode`
width/height are *logical*, not pixel, dimensions. A probe of virtual id 38
returned 28 modes and a current mode of `3440x1440@6880x2880`, so `hiDPI=1` does
synthesize the 2x variant from logical inputs. Do not "fix" `PrivateBridge.m`
by doubling the mode arrays.

### 2. Teardown stranded the panel (observed, worst)

Final state after the app exited:

```
id=3  DELL U3425WE  current=2560x1080@2560x1080 60Hz   isMain=true, not HiDPI
```

`PrivateHiDPIGateway.disable()` (`PrivateHiDPIGateway.swift:174`) only unmirrors
and destroys the virtual. Nothing re-applies a mode to the physical panel
afterwards. Callers inherit the omission:

- `SimpleHiDPIScalerApp.swift:337` — 10-second timeout branch: teardown, no restore
- `SimpleHiDPIScalerApp.swift:307` — kill-switch button: teardown, no restore
- only `restoreDefaults()` (`:196`) restores a mode

**The documented free fail-safe does not cover this path.** `ARCHITECTURE.md` §2a
and `SECURITY.md` §7 both claim quitting reverts changes. That is true only for
`CGDisplaySetDisplayMode`. The panel's mode here was changed by the *mirror
configuration*, so process exit reverts nothing. `README.md` and `SECURITY.md`
must be corrected.

Also observed: after teardown the MacBook's built-in display was **absent from
`CGGetOnlineDisplayList` entirely**. Cause not established. Worth a repro.

### 3. Mode switching on a mirrored display cannot use `CGDisplaySetDisplayMode`

`DisplayModeManager.setMode` (`DisplayModeManager.swift:42`) calls
`CGDisplaySetDisplayMode(displayID, mode, nil)`. On a display that is a member of
a mirror set this is not a valid operation — mirror-set modes are changed inside
a `CGBeginDisplayConfiguration` / `CGConfigureDisplayMode` /
`CGCompleteDisplayConfiguration` transaction. So every "Apply" against the
virtual while mirroring is expected to fail regardless of the mode chosen.

`PrivateBridge.m:110` already implements a correct begin/configure/complete
transaction for *mirroring*. It should be extended to configure the mode in the
same transaction, making enable and mode-switch one atomic operation.

### 4. The virtual's HiDPI modes are not enumerable

Probe of virtual id 38: `CGDisplayCopyAllDisplayModes` → 28 modes, **0 of them
HiDPI**, all 1x. Yet `CGDisplayCopyDisplayMode` → `3440x1440@6880x2880`.

So the active 2x mode is not in the mode list. `findLiveMode`
(`DisplayModeManager.swift:48`) searches only that list, so it can never match a
2x target and `setMode` always returns `kCGErrorFailure`. This is the open item in
`ARCHITECTURE.md` §4.7 — now **measured, not theoretical**. A read-only
`DumpModes` tool is needed before the virtual's rows can be designed honestly.

### 5. The app fabricates the virtual's mode rows

`SimpleHiDPIScalerApp.swift:118-133` hardcodes three `ScalingOption`s with 2x
backing, a hardcoded 60 Hz, and `ioModeID: nil`, instead of enumerating. This is
a guess presented to the user as fact, and it guarantees the mismatch in §4.

### 6. Virtuals leak; identification is name-based

The leaked virtual from the crashed earlier runs is real, not theoretical: at
10:31 the probe found a single active display, id 38, vendor `0x5348`,
model `0x4849` — the app's own IDs from `PrivateHiDPIGateway.swift:136` — sitting
as **main display** with the Dell as its hardware-mirror slave.

Two causes:

- `PrivateBridge.m:53` allocates `CGVirtualDisplayDescriptor` as a local and
  releases it when `PrivateVirtualDisplayCreate` returns; only the
  `CGVirtualDisplay` is retained in `gDisplays`.
- No `terminationHandler` is set, so when WindowServer ends a display nobody
  prunes `_active` (`PrivateHiDPIGateway.swift:50`).

Identification uses `activeMap` plus `name.hasPrefix("SimpleHiDPI")` at five
sites (`SimpleHiDPIScalerApp.swift:67`, `:100`, `:176`, `:267`, `:328`). The log
shows virtual IDs reaching `enable(physicalDisplayID:)` regardless —
`display=15`, `19`, `23`, `28`, `36` — so the guards miss in practice. The
authoritative test is vendor `0x5348` / model `0x4849`, which survives process
death and generic `NSScreen` names.

### 7. Earlier sessions: mirror failures

`ARCHITECTURE.md` §4.6 attributes these to already-fixed causes. The log agrees
the fixes helped — post-fix runs reach `created+mirrored` — but `mirrorFailed`
and `creationFailed(-20)` still recur (`05:00:20`, `05:01:45`, `05:02:12`). The
virtual is created and comes online, then the mirror transaction fails. §3
above is the prime suspect.

### 8. `launchDefaultMode` is a single global slot

`DisplayManager.swift:28-34` captures the launch mode from `cached.first` — not
from the selected display. `restoreDefaults()` then applies that geometry to
whichever panel the user has selected. On this machine the stored value happens
to be a valid Dell mode (`3440x1440@3440x1440 60Hz`, `launchDefaultIOID = 82`),
so it worked by luck rather than by design.

### 9. Public tier — confirmed dead, not a defect

Dell exposes **71 modes, 0 HiDPI** (3440×1440, 3008×1264, 2560×1080, …, all
1x). `ARCHITECTURE.md` §2c's verdict holds. Every public "Larger / Much Larger"
row will correctly read *not exposed by macOS*.

## Root causes and proposed fixes

| # | Root cause | Fix | Where |
|---|---|---|---|
| 1 | Teardown never restores the physical panel | Make `disable()` the single teardown primitive: unmirror → poll `CGDisplayIsInMirrorSet` until clear → re-apply the mode captured before mirroring. Route the timeout branch, the kill-switch, and `restoreDefaults()` through it. | `PrivateHiDPIGateway.swift:174`, `SimpleHiDPIScalerApp.swift:307`, `:337` |
| 2 | `CGDisplaySetDisplayMode` is invalid on a mirror slave | Add `PrivateConfigureMode(displayID, mode)` doing begin → `CGConfigureDisplayMode` → `CGConfigureDisplayMirrorOfDisplay` → complete, and use it for private mode switches. | `PrivateBridge.m:110`, `DisplayModeManager.swift:42` |
| 3 | Virtual rows are fabricated | Build rows from `CGDisplayCopyAllDisplayModes(virtualID)`; render "not exposed" honestly where absent. | `SimpleHiDPIScalerApp.swift:118` |
| 4 | Virtual 2x modes absent from the mode list | Ship the `DumpModes` diagnostic §4.7 promised, then design the rows from its output. | new tool |
| 5 | Descriptor released; no termination handler | Retain the descriptor in a holder object alongside the display; set `terminationHandler` to prune `_active`. | `PrivateBridge.m:53`, `PrivateHiDPIGateway.swift:50` |
| 6 | Name-based virtual detection | Add `DisplayInfo.isOwnVirtual` (vendor `0x5348` + model `0x4849`); use it at all five guard sites. | `Models.swift`, `SimpleHiDPIScalerApp.swift` ×5 |
| 7 | Global `launchDefaultMode` | Key by display ID, keep geometry as the replug fallback. | `ConfigurationStore.swift`, `DisplayManager.swift:28` |
| 8 | Docs claim a fail-safe that does not exist | Correct `ARCHITECTURE.md` §2a, `README.md`, `SECURITY.md` §7: only `CGDisplaySetDisplayMode` reverts on quit; the mirror path does not. | docs |

### Lower-severity, same pass

- `PRIVACY.md:37` tells the user to run `defaults delete <bundle-id>`. The SPM
  binary has no bundle id; the live domain is `SimpleHiDPIScaler`. As written the
  instruction deletes nothing.
- `SelfTest` writes `display=42` lines into the real log, and leaks a
  `test.simplehidpiscaler.<uuid>` `UserDefaults` suite per run — 8 had
  accumulated. Route test logging to a temp file and clean up suites.
- `ScalingManager.scalingOptions(for:availableModes:)` ignores its `display`
  parameter, and the "compact generic list for non-ultrawide panels" comment at
  `ScalingManager.swift:34` describes behaviour that was never written.
- The tested artifact is a bare SPM executable, so `LSUIElement`, a real
  `Info.plist`, and menu-bar-only behaviour were never exercised. Build a proper
  `.app` before further live testing.
- No git repository. Take one before refactoring.

## Suggested order

1. #1 and #2 — these are the two that make the feature usable and stop it
   damaging the panel.
2. #5, #6, #7 — stop the leaks and the mis-targeted calls.
3. #4, then #3 — design the virtual rows from real data.
4. #8 and the hygiene items.

## Recovering this machine

The panel is at 2560×1080 1x and the built-in display is offline. Options:

- **Set `privatePrototypeEnabled = 0`** before relaunching. It is currently `1`,
  and `maybeAutoEnablePrivate()` (`SimpleHiDPIScalerApp.swift:320`) re-arms the
  teardown on every launch, which is what stranded the panel.
- Re-apply 3440×1440 from the app's own public "Native" row (that mode exists on
  the Dell, io `79` at 120 Hz / stored launch default io `82` at 60 Hz).
- Investigate the missing built-in display separately; it is outside this app's
  scope and was not reproduced under control.

## Open questions

1. Why does the built-in display leave `CGGetOnlineDisplayList` after teardown?
2. With the mirror configured, can `CGConfigureDisplayMode` on the virtual
   retarget the pair in one transaction? This is the load-bearing assumption
   behind fix #2 and needs a live experiment.
3. Does the virtual expose its 2x variant to `CGConfigureDisplayMode` even
   though `CGDisplayCopyAllDisplayModes` omits it?
4. Is the 60 Hz master / 120 Hz slave asymmetry inherent to hardware mirroring on
   this panel, or an artefact of the mode list we supplied?
