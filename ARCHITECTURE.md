# SimpleHiDPIScaler — Architecture, APIs, Permissions, Risks, PoC, Test plan

This document is the technically honest core of the project: **what macOS
allows, what it does not, and what this proof of concept therefore does.**
It was written before any private API was touched; §2b/§4/§5 now also record
the subsequently user-approved private prototype and everything learned
debugging it live.

## 1. Architecture

```
┌─────────────────────────────────────────────────────────┐
│ MenuBarUI (SwiftUI MenuBarExtra + MenuBarViewModel)     │  UI only. CG work via
│  physical-only picker · virtual-target guards ·         │  manager/gateway.
│  opt-in toggle · kill-switch · 10-s countdowns          │
└──────────────┬──────────────────────┬───────────────────┘
               │ DisplayManaging      │ PrivateHiDPIGateway (opt-in)
┌──────────────▼──────────────────────▼───────────────────┐
│ DisplayManager (facade)                                 │  refresh / apply / restore
│  ├─ DisplayDetector   (DisplayDetecting)                │  CGGetActiveDisplayList,
│  │                       vendor/model/serial, NSScreen  │  CGDisplayVendorNumber…
│  ├─ DisplayModeManager (DisplayModeManaging)            │  CGDisplayCopyAllDisplayModes,
│  │                       current, verified set          │  CGDisplayCopyDisplayMode,
│  ├─ ScalingManager    (ScalingManaging)                 │  CGDisplaySetDisplayMode
│  │                       desired→exposed, HiDPI-required│  pure logic, testable
│  ├─ ConfigurationStore (ConfigurationStoring)           │  UserDefaults only
│  ├─ RollbackManager    (RollbackManaging)               │  10 s confirm-or-restore
│  └─ AppLogger                                          │  unified log + local file
└─────────────────────────────────────────────────────────┘
  PrivateBridge (ObjC, runtime-resolved, no link-time dependency)
   PrivateVirtualDisplayAvailable / Create / Destroy / MirrorPhysicalOntoVirtual
```

- Every collaborator is behind a protocol so tests inject fakes; no test
  touches a real display (SelfTest uses fakes exclusively).
- `DisplayManager.applyMode` saves nothing itself — callers snapshot
  `currentMode` first (the ViewModel does), then `RollbackManager` owns the
  10-second window.
- `ScalingManager` never invents modes. Desired logical sizes (3440×1440,
  3008×1264, 2560×1080) are matched against `allModes` with a 3% tolerance
  for GPU rounding; unmatched rows render as "not exposed by macOS".
  **Scaling rows (Larger/Much Larger) additionally REQUIRE `isHiDPI`** —
  a plain 2560×1080 mode is a resolution change, not scaling, and must never
  match (regression observed live: the panel dropped to 2560 plain).
- The picker lists **physical panels only** (excludes in-process virtual IDs
  plus `SimpleHiDPI*` names, since stale virtuals from dead processes are not
  in this process's map). Public apply and private enable both refuse virtual
  IDs with a message.
- Display names come from `NSScreen`, which goes generic under mirroring
  ("Display 3"); `isDellUWQHD` (vendor `0x10AC` + 3440×1440) backs up the
  strict name-based `looksLikeDellU3425WE` with a "Possible Dell" label.

## 2. Required APIs

### 2a. PUBLIC — used throughout (Quartz Display Services + AppKit)

| API | Framework | Use |
|---|---|---|
| `CGGetActiveDisplayList` | CoreGraphics | enumerate `CGDirectDisplayID`s; also the online-wait poll |
| `CGMainDisplayID`, `CGDisplayIsActive` | CoreGraphics | main vs external |
| `CGDisplayVendorNumber` / `ModelNumber` / `SerialNumber` | CoreGraphics | Dell 0x10AC heuristic + fallback |
| `CGDisplayPixelsWide` / `High` | CoreGraphics | native pixel size |
| `NSScreen.screens` + `localizedName` | AppKit | human name (fragile under mirroring; see §1) |
| `CGDisplayCopyAllDisplayModes(id, nil)` | CoreGraphics | list modes macOS exposes |
| `CGDisplayMode` `width/height/pixelWidth/pixelHeight` | CoreGraphics | logical vs backing size → `isHiDPI = pixels > logical` |
| `CGDisplayMode` `refreshRate` | CoreGraphics | "120 Hz" row |
| `CGDisplayMode` `ioDisplayModeID` | CoreGraphics | re-identify a mode at apply time |
| `CGDisplayMode` `isUsableForDesktopGUI()` | CoreGraphics | filter out unusable modes |
| `CGDisplayCopyDisplayMode` | CoreGraphics | current mode (save-before-apply) |
| `CGDisplaySetDisplayMode(id, mode, nil)` | CoreGraphics | apply a VERIFIED existing mode |
| `CGBeginDisplayConfiguration` / `CGConfigureDisplayMirrorOfDisplay` / `CGCompleteDisplayConfiguration` / `CGCancelDisplayConfiguration` | CoreGraphics | mirror physical→virtual (public fn, private pipeline); 0 unmirrors |
| `NSWorkspace.open(x-apple.systempreferences:…Displays…)` | AppKit | "Open Display Settings" |
| `MenuBarExtra`, `UserDefaults`, `OSLog` | SwiftUI/Foundation | UI, reversible state, local logs |

`CGDisplaySetDisplayMode` safety property (Apple docs): *"The selected display
mode persists for the life of the calling program. When the program terminates,
the display mode automatically reverts."* Quitting the app is a free fail-safe
for public changes. (Private virtuals are torn down via the kill-switch;
stale ones from killed processes can linger — see §4.)

### 2b. PRIVATE — approved opt-in prototype (implemented, gated)

| API | Status | What it does |
|---|---|---|
| `CGVirtualDisplayDescriptor` / `CGVirtualDisplay` / `CGVirtualDisplaySettings` / `CGVirtualDisplayMode` | Private Obj-C classes since 10.14, resolved at runtime via `NSClassFromString` | virtual display with `hiDPI=1`; WindowServer synthesizes 2× variants |
| `CGConfigureDisplayMirrorOfDisplay` | Public fn used in the private pipeline | physical mirrors virtual; DCP downsamples 2× → panel |
| `/Library/Displays/.../Overrides` `scale-resolutions` plists | Intel-era, ignored on Apple Silicon DCP | dead end on M-series |
| DriverKit display extension | Public but Apple-entitlement-gated | the only blessed route; needs Apple approval |

Lifecycle (`PrivateBridge` + `PrivateHiDPIGateway`): availability probe (no
side effects) → `enable()` creates the virtual (unique serial per creation,
dedicated dispatch queue, 120+60 Hz variants per logical size, 6880×2880 max)
→ wait-for-online poll (≤2 s, off-main) → mirror → 10-s confirm or teardown.
`disable()` unmirrors then destroys. Errors are granular: `-10` begin,
`-11`/`-12` configure, `-13` commit, `-20` never-online, `-30` already-creating,
`-5` self-mirror. Swift reaches all of it only through the gateway, which
returns `.optInRequired` unless `privatePrototypeEnabled` is true.

### 2c. Verdict (stated BEFORE any private-API work, as required)

> **The requested behaviour — synthesizing new HiDPI backing stores
> (≈3008×1264 HiDPI, ≈2560×1080 HiDPI) for a sub-4K 3440×1440 panel on Apple
> Silicon — cannot be achieved with public APIs.** Public APIs can only
> enumerate and select modes macOS/the GPU already exposes. This PoC therefore
> implements the honest subset (enumerate truthfully, select safely, say "not
> exposed" otherwise) plus the explicitly approved private prototype above.

## 3. Permission analysis

| Permission | Requested? | Why / why not |
|---|---|---|
| Network (incoming/outgoing) | NO | No network code exists. Verify: `grep -ri URLSession\|Network\|socket Sources/` returns only the System Settings URL opener. |
| Screen Recording (`CGPreflightScreenCaptureAccess`, ScreenCaptureKit) | NO | We never capture pixels; mode metadata needs no capture entitlement. |
| Accessibility / Input Monitoring | NO | No event taps, no key monitoring. |
| Camera / Microphone / Contacts / Calendars / Reminders | NO | Irrelevant to display modes. |
| Documents / Desktop / Downloads folder access | NO | State lives in `UserDefaults`; logs in `~/Library/Logs`. |
| Keychain | NO | Nothing secret is stored. |
| Location / Bluetooth / Automation | NO | Not used. |
| Display mode switching / mirroring | No entitlement exists | `CGDisplaySetDisplayMode` and `CGConfigureDisplayMirrorOfDisplay` among exposed displays require no special permission; zero-entitlement + sandbox-compatible remains correct. |

The `.entitlements` file is intentionally empty so any future request is a
loud diff. See `PRIVACY.md` and `SECURITY.md`.

## 4. Risks / limitations

1. **Sub-4K ultrawides show no HiDPI rows publicly.** Expected on Apple
   Silicon; the UI explains it instead of pretending.
2. **Mode list varies by cable/GPU/macOS version.** Fuzzy matching + "not
   exposed" states, never hard-coded IDs. Refresh can be 60 or 120 Hz on the
   same panel across sessions.
3. **`CGDisplaySetDisplayMode` is per-process-lifetime.** Quit = revert for
   public changes (fail-safe); bad for persistence — documented in UI.
4. **No persistence of custom modes** beyond the running prototype session.
5. **Private prototype costs** (approved, opt-in): breaks on OS updates, App
   Store rejection, notarization scrutiny, typically mixed 60/120 Hz behavior
   while mirrored, mandatory 10-s confirm every enable (unattended launches
   tear down by design).
6. **Fixed live bugs (kept here so they stay fixed):** plain low-res fallback
   offered as scaling (now HiDPI-required); virtual selectable as a target and
   de-HiDPI'd by public Apply (now picker + apply + enable all refuse
   virtuals); main-thread online-wait deadlock (creation now off-main, bridge
   uses a dedicated queue); serial reuse colliding with teardown-limbo
   virtuals (now unique per creation); mirror-before-online commit failures
   (now wait-for-online + single-flight).
7. **Open issues:** the private rows assume virtual modes expose backing =
   2× logical — unverified against `CGDisplayCopyAllDisplayModes(virtual)`.
   Next step is a read-only `DumpModes` comparison (planned, not yet built).
   Stale virtuals from killed processes can linger and confuse selection;
   `SelfTest` writes fake `display=42` lines into the real local log (test
   hygiene debt); `launchDefault*` can go stale if first launch happens while
   scaled (delete the keys while at native and relaunch to recapture).
8. **Multi-display.** Selection is per-`CGDirectDisplayID`; IDs are not stable
   across replugs, so `ConfigurationStore` records geometry as well as ID.

## 5. Minimal proof of concept (what ships in this repo)

- Menu-bar app (`MenuBarExtra`, `LSUIElement`, no dock icon).
- Startup: enumerate displays, flag Dell exact/likely, show name / ID /
  native pixels / current logical+backing / refresh / HiDPI yes-no.
- Physical-only display picker with IDs (never assumes Dell-is-only-external).
- Public scaling rows mapped to exposed HiDPI modes; unavailable rows disabled
  with an honest explanation + pointer to §2.
- Apply → save previous → verify-exists → `CGDisplaySetDisplayMode` →
  10-second "Keep?" countdown → auto-restore on timeout.
- Private section: opt-in toggle → Enable for this display (background
  creation, wait-for-online, mirror) → 10-s confirm or teardown → private 2x
  rows → Apply onto the virtual → Keep. Kill-switch unmirrors + destroys.
- "Restore Defaults" (launch-time mode + private teardown), "Open Display
  Settings", "Clear logs", "Refresh displays".
- Local-only logging (display ID, previous/selected, result code; private
  virtual↔physical IDs and mirror codes).
- Unit tests + `SelfTest` (no hardware): mode selection, identification,
  rollback, private gating.

Build & test (Command Line Tools are enough):

```sh
swift build
swift run SelfTest   # XCTest.framework not in CLT; mirrors swift test
```

Xcode packaging (signed/notarized bundle) is documented in `README.md`.

## 6. Test plan

| Area | Cases (see `Tests/` + `Sources/SelfTest/`) |
|---|---|
| Mode selection | maps 3 rows to exposed modes; prefers HiDPI over plain; prefers 120 Hz; tolerates ±3% rounding; nil when nothing close; plain low-res NEVER matches scaling rows (regression); `isHiDPI` from pixels-vs-logical |
| Identification | Dell vendor+res; name+res when hub masks vendor; rejects wrong res; rejects LG as Dell but flags external-ultrawide; multi-display picks only Dell; `isDellUWQHD` fallback for generic mirrored names; main never external |
| Rollback | fires exactly once on 10th tick; `confirm()` cancels; restores launch default via fake; phantom mode never reaches hardware; store round-trips and clears |
| Private gating (headless) | opt-in off → `.optInRequired` without touching WindowServer; gating matrix (off→refuse, on+absent→unavailable, on+present→proceed); never creates real virtuals in tests |
| Manual (on hardware) | DP + HDMI: enumerate; public Native apply/timeout/confirm/quit-revert/replug/Restore/Clear-logs with no permission prompts; private: opt-in → Enable → Keep → Larger/Much Larger → Keep → verify looks-like vs backing in System Settings → Disable kill-switch → verify standalone; confirm picker never offers SimpleHiDPI targets |

No test requires network. Only the manual private path touches real displays.
