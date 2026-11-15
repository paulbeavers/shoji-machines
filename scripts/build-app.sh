#!/usr/bin/env bash
# Build "Shoji Machines.app" into ./build
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"

./scripts/sync-themes.sh   # the Lucent Hyprland config's themes, when ../lucent exists
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/shoji-machines"

APP="build/Shoji Machines.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Shoji Machines"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Themes "$APP/Contents/Resources/Themes"

COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then COMMIT="$COMMIT (modified)"; fi
/usr/libexec/PlistBuddy -c "Add :ShojiGitCommit string $COMMIT" "$APP/Contents/Info.plist"

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
"$BIN" --render-icon build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" build/icon-1024.png

# Virtualization entitlement (VMs can't start without it) and a designated requirement on the
# bundle id, so macOS keeps recognising it across rebuilds.
codesign --force --sign - --entitlements Resources/Machines.entitlements \
  -r='designated => identifier "dev.shoji.Machines"' "$APP"

# Register with Launch Services, so Shoji's Mod+M finds it by bundle id.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true
echo "Built $APP"
