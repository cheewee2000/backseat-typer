#!/bin/bash
# Build, bundle, sign and install Omnikeys to ~/Applications. Usage: ./build.sh [--run]
set -e
cd "$(dirname "$0")"
V=$(cat VERSION)
SCRATCH="$HOME/Library/Caches/omnikeys/.build"   # outside Dropbox: conflicted copies break codesign
APP="$HOME/Applications/Omnikeys.app"
swift build -c release --scratch-path "$SCRATCH" 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" | tail -5
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp "$SCRATCH/release/Omnikeys" "$APP/Contents/MacOS/"
cp Resources/Fonts/*.ttf "$APP/Contents/Resources/Fonts/"
sed "s/__VERSION__/$V/g" Resources/Info.plist > "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
[ -f Resources/Assets.car ] && cp Resources/Assets.car "$APP/Contents/Resources/"
codesign --force --deep --sign "Apple Development: cwwang@gmail.com (66B4FE4L32)" "$APP" 2>&1 | grep -v "replacing existing" || true
echo "built $APP v$V"
if [ "$1" = "--run" ]; then pkill -x Omnikeys 2>/dev/null; sleep 0.3; open "$APP"; fi
