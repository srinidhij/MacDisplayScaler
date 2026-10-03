# Privacy Policy

SimpleHiDPIScaler collects nothing, transmits nothing, and has no network code.

## Data stored locally (and only locally)

| What | Where | Purpose |
|---|---|---|
| Launch-time display mode (width, height, pixel size, refresh, IO mode ID) | `UserDefaults` (standard app domain) | "Restore Defaults" reversibility |
| Last selected display ID + logical width | `UserDefaults` | convenience pre-selection |
| Display-change log lines: display ID, previous mode, selected mode, result code | Unified Log (`com.simplehidpiscaler.app`) + `~/Library/Logs/SimpleHiDPIScaler.log` | local diagnostics |
| Private prototype events: opt-in on/off, virtual display ID ↔ physical ID, mirror result | Same local log only | audit the opt-in boundary |

No display pixel contents, no screenshots, no window titles, no file paths,
no user identity, no location, no serial numbers are logged. (Vendor/model
numbers are used in-memory for the Dell heuristic and never written to disk.)

## Data transmitted

None. There is no network capability to audit: no `URLSession`, no sockets, no
analytics SDK, no updater, no cloud endpoints. The only URL opened is the local
System Settings deep link (`x-apple.systempreferences:…Displays…`) via
`NSWorkspace`, which stays on-device.

## Permissions

The app requests zero macOS permissions (see `SimpleHiDPIScaler.entitlements`,
empty by design, and `ARCHITECTURE.md` §3). If the OS ever prompts for files,
camera, microphone, screen recording, accessibility, or keychain while running
this app, do not grant it — file a bug instead.

## Your controls

- **Clear logs**: the "Clear logs" button in the menu-bar UI deletes
  `~/Library/Logs/SimpleHiDPIScaler.log`.
- **Forget saved modes**: delete the app's `UserDefaults` domain
  (`defaults delete <bundle-id>`) or use "Restore Defaults" then quit.
- **Full revert**: quit the app — Apple automatically reverts
  `CGDisplaySetDisplayMode` changes made by a terminated process.

## Contact

Privacy questions: file an issue against this repo (no account or personal
data required beyond what your forge already holds).
