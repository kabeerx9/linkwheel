#!/bin/sh
# Builds LinkWheel.app and installs it to ~/Applications.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
bin="$(swift build -c release --show-bin-path)/LinkWheel"

app="build/LinkWheel.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/LinkWheel"
cp Support/Info.plist "$app/Contents/Info.plist"
# Ad-hoc signature: enough for local use and Apple Events permission.
codesign --force --sign - "$app"

dest="$HOME/Applications/LinkWheel.app"
pkill -x LinkWheel 2>/dev/null || true
rm -rf "$dest"
mkdir -p "$HOME/Applications"
cp -R "$app" "$dest"
# Tell Launch Services the app exists so it can handle http/https.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$dest"
echo "Installed $dest"
