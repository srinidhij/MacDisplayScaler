# Privacy

SimpleHiDPIScaler collects nothing, sends nothing, and has no network code.

## Stored locally

| What | Where | Why |
|---|---|---|
| Launch-time display mode | `UserDefaults` | Restore Defaults |
| Last selected display ID and size | `UserDefaults` | pre-selection |
| Saved default size | `UserDefaults` | applied at launch |
| Opt-in flag | `UserDefaults` | gates the feature |
| Log lines: display ID, previous/selected mode, result code, virtual display ID | Unified Log and `~/Library/Logs/SimpleHiDPIScaler.log` | diagnostics |

No screen contents, screenshots, window titles, file paths, serial numbers, or
identity are logged. The only URL opened is the local System Settings link.

## Permissions

None requested. If macOS prompts for anything while the app runs, don't grant
it; file a bug.

## Your controls

- **Clear logs**: menu button; deletes the log file.
- **Forget settings**: `defaults delete com.simplehidpiscaler.app` (packaged
  app) or `defaults delete SimpleHiDPIScaler` (bare binary). **Clear** next to
  the default size removes just that.
- **Revert the display**: Disable for this display, or Restore Defaults.
- **Open at login** is a normal login item; remove it in System Settings →
  General → Login Items.
