#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/Tierminal.app"
RES="$APP/Contents/Resources"
DATA="$HOME/Library/Application Support/Tierminal"
VERSION="$(cat VERSION)"
LAUNCH=1
[ "${1:-}" = "--no-launch" ] && LAUNCH=0

echo "[1/5] build $VERSION"
swift build -c release 2>&1 | tail -2

echo "[2/5] bundle"
pkill -x Tierminal 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES" "$HOME/Applications" "$DATA/emblems"
cp .build/release/Tierminal "$APP/Contents/MacOS/"
cp tierminal.py tierminal.zsh tierminal.bash "$RES/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$RES/"
for f in emblems/logo.png emblems/wordmark.png; do [ -f "$f" ] && cp "$f" "$RES/"; done
for f in emblems/*.png; do [ -f "$DATA/emblems/$(basename "$f")" ] || cp "$f" "$DATA/emblems/"; done
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Tierminal</string>
    <key>CFBundleDisplayName</key><string>Tierminal</string>
    <key>CFBundleIdentifier</key><string>com.ezrakruger.tierminal</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleExecutable</key><string>Tierminal</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$APP" 2>/dev/null
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP" >/dev/null 2>&1 || true

if [ "$LAUNCH" = "1" ]; then
    echo "[3/5] hooks"
    /usr/bin/python3 "$RES/tierminal.py" setup shell >/dev/null
    /usr/bin/python3 "$RES/tierminal.py" setup claude >/dev/null
    echo "[4/5] backfill"
    /usr/bin/python3 "$RES/tierminal.py" backfill
    echo "[5/5] launch"
    open "$APP"
fi
echo "installed: $APP"
