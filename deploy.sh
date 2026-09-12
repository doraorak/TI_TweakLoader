#!/bin/bash
#
# Installs the payload from the app bundle into /Library/TweakInject.
#
# Building is no longer this script's job. The app's own build now builds every
# component and refreshes its Payload/ (see scripts/build-payload.sh in the app
# project, wired in as a pre-build phase), so there is exactly one way to
# produce a payload and it cannot be skipped by forgetting a command. This is
# only the privileged copy onto this machine, for when you want it without
# opening the app.
#
# Prefer the app: the payload station installs the same files through the
# helper, and it also knows how to tell you when what is installed is older than
# what the app ships.
#
#   ./deploy.sh            install from the built app bundle (asks for your password)
#   ./deploy.sh --verify   verify what is currently installed, install nothing
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/TI_TweakLoader.xcodeproj"
INSTALL_ROOT="/Library/TweakInject"
APP_PAYLOAD="/Users/doraorak/Desktop/programming/XCode-projects/APP/My apps/TweakInject/Payload"

# A canary per component: a string the CURRENT source produces and an older
# build does not. Update these whenever the thing they prove changes.
CANARY_TI_LaunchdHooks="SecurityAgent"
CANARY_TI_XpcProxyHooks="SecurityAgent"
CANARY_TI_TweakLoader="/Library/TweakInject/logs/tweakinject.log"

products_dir() {
    xcodebuild -project "$PROJECT" -scheme "$1" -configuration Release \
        -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}'
}

verify() {
    local file="$1" canary="$2" label="$3"
    if [ ! -f "$file" ]; then
        echo "  ✗ $label: missing at $file"; return 1
    fi
    if ! strings -a "$file" 2>/dev/null | grep -qF "$canary"; then
        echo "  ✗ $label: does not contain \"$canary\" — this is a stale build"
        return 1
    fi
    echo "  ✓ $label  ($(stat -f%z "$file") bytes, built $(stat -f%Sm -t '%H:%M' "$file"))"
}

if [ "${1:-}" = "--verify" ]; then
    echo "Installed payload:"
    verify "$INSTALL_ROOT/LaunchdHook/TI_LaunchdHooks.dylib"  "$CANARY_TI_LaunchdHooks"  "TI_LaunchdHooks" || true
    verify "$INSTALL_ROOT/LaunchdHook/TI_XpcProxyHooks.dylib" "$CANARY_TI_XpcProxyHooks" "TI_XpcProxyHooks" || true
    verify "$INSTALL_ROOT/TI_TweakLoader.dylib"               "$CANARY_TI_TweakLoader"    "TI_TweakLoader" || true
    exit 0
fi

APP="$(ls -d "$HOME/Library/Developer/Xcode/DerivedData/TweakInject-"*/Build/Products/Debug/TweakInject.app 2>/dev/null | head -1)"
[ -n "$APP" ] || { echo "No built TweakInject.app found. Build the app first."; exit 1; }
DD="$APP/Contents/Resources/Payload"
echo "Source: $DD"

echo "Verifying before install…"
verify "$DD/LaunchdHook/TI_LaunchdHooks.dylib"  "$CANARY_TI_LaunchdHooks"  "TI_LaunchdHooks"
verify "$DD/LaunchdHook/TI_XpcProxyHooks.dylib" "$CANARY_TI_XpcProxyHooks" "TI_XpcProxyHooks"
verify "$DD/TI_TweakLoader.dylib"               "$CANARY_TI_TweakLoader"    "TI_TweakLoader"

# PID 1 is arm64e. A slice-less or arm64-only build silently fails to inject.
for d in TI_LaunchdHooks TI_XpcProxyHooks; do
    lipo -archs "$DD/LaunchdHook/$d.dylib" | grep -q arm64e \
        || { echo "  ✗ $d.dylib has no arm64e slice — launchd will not load it"; exit 1; }
done
echo "  ✓ arm64e slices present"

echo "Installing (sudo)…"
sudo cp "$DD/LaunchdHook/TI_LaunchdHooks.dylib"  "$INSTALL_ROOT/LaunchdHook/TI_LaunchdHooks.dylib"
sudo cp "$DD/LaunchdHook/TI_XpcProxyHooks.dylib" "$INSTALL_ROOT/LaunchdHook/TI_XpcProxyHooks.dylib"
sudo cp "$DD/TI_TweakLoader.dylib" "$INSTALL_ROOT/TI_TweakLoader.dylib"
# Linked by tweaks for PSPreferences / PSUserDefaults.
if [ -f "$DD/TI_PreferenceSupport.dylib" ]; then
    sudo cp "$DD/TI_PreferenceSupport.dylib" "$INSTALL_ROOT/TI_PreferenceSupport.dylib"
fi
if [ -f "$DD/TI_Ellekit.dylib" ]; then
    sudo cp "$DD/TI_Ellekit.dylib" "$INSTALL_ROOT/TI_Ellekit.dylib"
fi

# The pill lives beside the Safe Mode markers it advertises.
sudo cp "$DD/TI_SafeModePill.dylib" "$INSTALL_ROOT/SafeMode/TI_SafeModePill.dylib"
sudo cp "$DD/TI_SafeMode.dylib" "$INSTALL_ROOT/SafeMode/TI_SafeMode.dylib"

sudo chown -R root:wheel "$INSTALL_ROOT/SafeMode"
sudo chmod 755 "$INSTALL_ROOT/SafeMode"
[ -f "$INSTALL_ROOT/SafeMode/TI_SafeModePill.dylib" ] && sudo chmod 755 "$INSTALL_ROOT/SafeMode/TI_SafeModePill.dylib"
[ -f "$INSTALL_ROOT/SafeMode/TI_SafeMode.dylib" ] && sudo chmod 755 "$INSTALL_ROOT/SafeMode/TI_SafeMode.dylib"

echo "Verifying what is now installed…"
verify "$INSTALL_ROOT/LaunchdHook/TI_LaunchdHooks.dylib"  "$CANARY_TI_LaunchdHooks"  "TI_LaunchdHooks"
verify "$INSTALL_ROOT/LaunchdHook/TI_XpcProxyHooks.dylib" "$CANARY_TI_XpcProxyHooks" "TI_XpcProxyHooks"
verify "$INSTALL_ROOT/TI_TweakLoader.dylib"               "$CANARY_TI_TweakLoader"    "TI_TweakLoader"
echo "Done. Re-hook launchd for this to take effect."
