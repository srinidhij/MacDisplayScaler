# Security Policy

Reports are welcome against the latest commit on the default branch. Open a
private issue and include macOS version, Mac model, and connection type
(DP/HDMI/dock). Do not include EDID dumps or serial numbers.

## Principles

1. **No network.** There is no networking code; `grep -ri "URLSession\|socket("
   Sources/` should find nothing.
2. **No telemetry.** Logging is local only (`OSLog` and
   `~/Library/Logs/SimpleHiDPIScaler.log`).
3. **No dependencies.** Apple frameworks plus one in-repo ObjC bridge.
4. **No permissions.** The entitlements file is empty. The app never touches
   Documents, Desktop, contacts, camera, microphone, screen recording,
   accessibility, input monitoring, or the keychain.
5. **Undocumented APIs are isolated.** Virtual-display classes are used only in
   `Sources/PrivateBridge/`, resolved at runtime (no link-time dependency), and
   reached from Swift only through `PrivateHiDPIGateway`, which refuses unless
   the user has turned on the opt-in. If the classes are missing the feature
   reports itself unavailable instead of crashing.
6. **Reversible.** Each change saves the previous panel mode. Without a Keep
   within 30 seconds the virtual display is removed and the mode restored.
   Disable and Restore Defaults do the same on demand. Quitting does not restore
   a mirrored panel by itself.

## Known limitations

- Undocumented APIs can change or disappear in any macOS update.
- Not suitable for App Store distribution.
- The packaged app is ad-hoc signed and not notarized.

## Supply chain

`swift package show-dependencies` should report no dependencies.
