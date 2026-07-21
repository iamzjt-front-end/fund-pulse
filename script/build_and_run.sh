#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
EXECUTABLE_NAME="FundPulse"
APP_NAME="fund-pulse"
BUNDLE_ID="com.iamzjt.frontend.fund-pulse.swift"
MIN_SYSTEM_VERSION="14.0"
BUILD_CONFIGURATION="${FUND_PULSE_BUILD_CONFIGURATION:-debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_VERSION="$(node -p "require('./package.json').version")"
APP_ICON="$ROOT_DIR/build/icon.icns"
RESOURCE_BUNDLE_NAME="FundPulse_FundPulse.bundle"

cd "$ROOT_DIR"

case "$BUILD_CONFIGURATION" in
  debug)
    ;;
  release)
    ;;
  *)
    echo "error: FUND_PULSE_BUILD_CONFIGURATION must be debug or release" >&2
    exit 2
    ;;
esac

pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true

if [[ "$BUILD_CONFIGURATION" == "release" ]]; then
  swift build -c release
  BUILD_BIN_DIR="$(swift build -c release --show-bin-path)"
else
  swift build
  BUILD_BIN_DIR="$(swift build --show-bin-path)"
fi
BUILD_BINARY="$BUILD_BIN_DIR/$EXECUTABLE_NAME"
RESOURCE_BUNDLE="$BUILD_BIN_DIR/$RESOURCE_BUNDLE_NAME"

if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "error: SwiftPM resource bundle not found: $RESOURCE_BUNDLE" >&2
  exit 1
fi

rm -rf "$DIST_DIR/FundPulse.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME"
chmod +x "$APP_BINARY"
if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$APP_RESOURCES/FundPulse.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>fund-pulse</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>CFBundleIconFile</key>
  <string>FundPulse.icns</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${FUND_PULSE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$({
    security find-identity -p codesigning -v 2>/dev/null \
      | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p'
  } | head -n 1)"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  echo "warning: no stable code-signing identity found; using ad-hoc signing" >&2
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build|build)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    for resource in alipay-support.png wechat-support.png; do
      if ! find "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME" -type f -name "$resource" -print -quit | grep -q .; then
        echo "error: bundled support resource not found: $resource" >&2
        exit 1
      fi
    done
    open_app
    sleep 1
    pgrep -x "$EXECUTABLE_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
