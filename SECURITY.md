# Security Policy

## Supported

This is a minimal proof of concept. Security reports are welcome against the
latest commit on the default branch.

## How to report

Open a private issue / contact the maintainer listed in the repo metadata.
Include: macOS version, Mac model, connection type (DP/HDMI/dock), and steps.
Do NOT include EDID dumps, serial numbers, or system profilers unless asked —
they are unnecessary for display-mode bugs.

## Security principles (enforced)

1. **No network.** There is no networking code. `grep -ri "URLSession\|Network\
   |CFNetwork\|socket(" Sources/` must return nothing except the single
   `NSWorkspace.open` of the local System Settings URL.
2. **No analytics/telemetry/crash-report uploading.** `OSLog` + a local file
   in `~/Library/Logs/SimpleHiDPIScaler.log` only.
3. **No external dependencies.** Swift stdlib + Apple frameworks only
   (SwiftUI, AppKit, CoreGraphics, Foundation, OSLog) plus one in-repo ObjC
   helper (`Sources/PrivateBridge`, no third-party code).
4. **Minimum permissions.** The `.entitlements` file is intentionally empty.
   Display enumeration, mode switching among exposed modes, and display
   mirroring configuration require no entitlement. Any PR adding an
   entitlement must update this file, `ARCHITECTURE.md` §3, and `PRIVACY.md`
   with justification.
5. **Never touches** Documents, Desktop, Contacts, Camera, Microphone, Screen
   Recording, Accessibility, Input Monitoring, or Keychain. CI / review should
   reject any API from those domains (e.g. `CGPreflightScreenCaptureAccess`,
   `AXIsProcessTrusted`, `EKEventStore`, `AVCaptureDevice`).
6. **Private APIs — approved prototype only, gated.** `CGVirtualDisplay*`
   symbol usage is confined to `Sources/PrivateBridge/` (runtime-resolved via
   `NSClassFromString`, no link-time dependency, dedicated dispatch queue;
   `PrivateVirtualDisplayAvailable` probes before touching anything). Swift
   reaches it only through `PrivateHiDPIGateway`, which refuses unless the
   user enables the `privatePrototypeEnabled` opt-in (default OFF for fresh
   installs). Protections: unique serial per creation, wait-for-online before
   mirroring, single-flight creation, virtual IDs refused as apply/enable
   targets, kill-switch (`disable()` = unmirror + destroy), mandatory 30-s
   Keep/rollback on every manual enable and size switch (a size the user already
   confirmed with Keep is re-applied at launch without a countdown). Any PR touching this path
   must update this file, `ARCHITECTURE.md` §2b, `README.md`, and `PRIVACY.md`.
   App Store submission is out of scope while this path exists.
7. **Reversible by design.** Every apply path snapshots the previous mode;
   the keep-timeout rollback restores it (public) or tears down the virtual
   and re-applies the panel's pre-mirror mode (private). Quitting reverts only
   `CGDisplaySetDisplayMode` changes (Apple semantics); the private mirror path
   does **not** revert on quit by itself, so use the kill-switch or Restore
   Defaults rather than relying on exit;
   "Restore Defaults" returns to the launch-time mode and kills any private
   virtual for that display.

## Known limitations (not vulnerabilities)

- `CGDisplaySetDisplayMode` is process-lifetime scoped: public modes do not
  survive app quit/reboot. That is Apple's documented behaviour. It does not
  cover the private mirror path (see §7).
- Sub-4K panels may expose zero HiDPI modes publicly. The app reports this;
  it does not escalate privileges or patch the system to "fix" it.
- Private virtuals can outlive the process that created them in teardown
  limbo; the picker excludes them by ID and name prefix, but Display Settings
  remains the final arbiter of mirror state.
- `SelfTest` currently logs fake `display=42` lines to the real local log;
  test-only hygiene debt, no user data involved.

## Supply chain

No package dependencies (`Package.swift` has none). Verify with
`swift package show-dependencies` (expect: no dependencies).
