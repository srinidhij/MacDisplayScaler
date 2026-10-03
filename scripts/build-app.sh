#!/bin/zsh
# Builds SimpleHiDPIScaler.app (menu-bar only, ad-hoc signed) and, with
# `--install`, copies it to ~/Applications. Needed for "Open at login".
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product SimpleHiDPIScaler
BIN="$(swift build -c release --show-bin-path)/SimpleHiDPIScaler"
APP="build/SimpleHiDPIScaler.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/SimpleHiDPIScaler"
cp scripts/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --entitlements SimpleHiDPIScaler.entitlements "$APP"
echo "Built $APP"
if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/SimpleHiDPIScaler.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to ~/Applications/SimpleHiDPIScaler.app"
fi
