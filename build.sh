#!/bin/bash
# NeuraBar build script
# Kullanim: ./build.sh        → build + NeuraBar.app olusturur
#          ./build.sh install → /Applications'a kopyalar ve acar

set -e
cd "$(dirname "$0")"

APP_NAME="NeuraBar"
APP_BUNDLE="$APP_NAME.app"
BUILD_DIR=".build/release"

# --- Onkosul kontrolleri ---
if ! command -v swift >/dev/null 2>&1; then
    echo "✗ Swift bulunamadi."
    echo ""
    echo "Xcode Command Line Tools'u kur:"
    echo "  xcode-select --install"
    echo ""
    echo "Kurulum bittikten sonra bu scripti tekrar calistir."
    exit 1
fi

SWIFT_VER=$(swift --version 2>/dev/null | head -1)
echo "✓ $SWIFT_VER"

# --- Build ---
echo "▶ Derleniyor (release)..."
# Prefer universal binary if both toolchains are available, otherwise host arch only.
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
    echo "✓ Universal binary (arm64 + x86_64)"
else
    swift build -c release
    HOST_ARCH=$(uname -m)
    echo "✓ Host binary ($HOST_ARCH)"
fi

if [ ! -f "$BUILD_DIR/$APP_NAME" ]; then
    echo "✗ Derleme hatasi. Hata cikisi:"
    swift build -c release 2>&1 | tail -30
    exit 1
fi

# --- .app bundle ---
echo "▶ .app bundle olusturuluyor..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Copy pre-built bundle icon
if [ -f "NeuraBar.icns" ]; then
    cp NeuraBar.icns "$APP_BUNDLE/Contents/Resources/NeuraBar.icns"
fi

# Adhoc imza — Gatekeeper'i sakin tutar
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "✓ $APP_BUNDLE hazir"
echo ""

# --- Install / Open ---
if [ "$1" = "install" ]; then
    echo "▶ /Applications altina kopyalaniyor..."
    # Eski versiyonu calisiyorsa oldur
    killall NeuraBar 2>/dev/null || true
    sleep 0.3
    rm -rf "/Applications/$APP_BUNDLE"
    cp -R "$APP_BUNDLE" /Applications/
    echo "✓ /Applications/$APP_BUNDLE"
    echo ""
    echo "▶ Aciliyor..."
    open "/Applications/$APP_BUNDLE"
    echo ""
    echo "Menu cubugunda ✨ simgesine tikla."
else
    echo "Tek seferlik acmak icin:   open $APP_BUNDLE"
    echo "/Applications'a kurmak icin: ./build.sh install"
fi
