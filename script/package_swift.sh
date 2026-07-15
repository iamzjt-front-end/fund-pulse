#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(node -p "require('./package.json').version")"
ARCH="$(uname -m)"
APP_BUNDLE="$ROOT_DIR/dist/fund-pulse.app"
OUT_DIR="$ROOT_DIR/release/swift"
WORK_DIR="$OUT_DIR/dmg-root"
ZIP_PATH="$OUT_DIR/fund-pulse-$VERSION-$ARCH-swift.zip"
DMG_PATH="$OUT_DIR/fund-pulse-$VERSION-$ARCH-swift.dmg"
RW_DMG_PATH="$OUT_DIR/fund-pulse-$VERSION-$ARCH-swift-rw.dmg"
NOTARY_ZIP_PATH="$OUT_DIR/fund-pulse-$VERSION-$ARCH-swift-notary.zip"
VOLUME_NAME="Fund Pulse $VERSION-$ARCH"
APP_FILE_NAME="$(basename "$APP_BUNDLE")"
SIGN_IDENTITY="${FUND_PULSE_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${FUND_PULSE_NOTARY_PROFILE:-fund-pulse}"
SKIP_NOTARY="${FUND_PULSE_SKIP_NOTARY:-0}"
SKIP_DMG_LAYOUT="${FUND_PULSE_SKIP_DMG_LAYOUT:-0}"
SIGNING_KIND="custom"
SIGN_TIMESTAMP_OPTION="--timestamp"
MOUNT_DIR=""

cd "$ROOT_DIR"

detach_dmg_mount() {
  if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet || {
      sleep 2
      hdiutil detach "$MOUNT_DIR" -force -quiet || true
    }
    MOUNT_DIR=""
  fi
}

trap detach_dmg_mount EXIT

find_developer_id_identity() {
  security find-identity -p codesigning -v \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
    | head -n 1
}

find_apple_development_identity() {
  security find-identity -p codesigning -v \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
    | head -n 1
}

create_plain_dmg() {
  hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$WORK_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
}

style_mounted_dmg() {
  if ! osascript - "$VOLUME_NAME" "$APP_FILE_NAME" <<'APPLESCRIPT'
on run argv
  set volumeName to item 1 of argv
  set appBundleName to item 2 of argv

  tell application "Finder"
    set theDisk to disk volumeName
    open theDisk
    delay 1

    set theWindow to container window of theDisk
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set bounds of theWindow to {120, 120, 980, 640}

    set viewOptions to icon view options of theWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 16

    set position of item appBundleName of theWindow to {250, 305}
    set position of item "Applications" of theWindow to {625, 305}

    update theDisk without registering applications
    delay 1
    close theWindow
  end tell
end run
APPLESCRIPT
  then
    return 1
  fi

  if [[ -f "$ROOT_DIR/build/icon.icns" ]]; then
    cp "$ROOT_DIR/build/icon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
      SetFile -a C "$MOUNT_DIR" || true
      SetFile -a V "$MOUNT_DIR/.VolumeIcon.icns" || true
    fi
  fi
}

create_styled_dmg() {
  local image_size_mib
  local attach_output

  rm -f "$RW_DMG_PATH" "$DMG_PATH"
  image_size_mib="$(du -sm "$WORK_DIR" | awk '{ print $1 + 128 }')"

  if ! hdiutil create \
    -volname "$VOLUME_NAME" \
    -size "${image_size_mib}m" \
    -fs HFS+ \
    -type UDIF \
    -ov \
    "$RW_DMG_PATH"; then
    return 1
  fi

  if ! attach_output="$(hdiutil attach "$RW_DMG_PATH" -readwrite -noverify -noautoopen)"; then
    return 1
  fi

  MOUNT_DIR="$(awk '/\/Volumes\// { print substr($0, index($0, "/Volumes/")); exit }' <<<"$attach_output")"
  if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
    return 1
  fi

  if ! ditto "$WORK_DIR" "$MOUNT_DIR"; then
    return 1
  fi

  if ! style_mounted_dmg; then
    return 1
  fi

  sync
  detach_dmg_mount

  if ! hdiutil convert "$RW_DMG_PATH" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH"; then
    return 1
  fi

  rm -f "$RW_DMG_PATH"
}

create_dmg() {
  if [[ "$SKIP_DMG_LAYOUT" == "1" ]]; then
    create_plain_dmg
    return
  fi

  if create_styled_dmg; then
    return
  fi

  echo "warning: failed to create styled DMG; falling back to a plain DMG." >&2
  detach_dmg_mount
  rm -f "$RW_DMG_PATH" "$DMG_PATH"
  create_plain_dmg
}

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(find_developer_id_identity || true)"
  if [[ -n "$SIGN_IDENTITY" ]]; then
    SIGNING_KIND="developer-id"
  else
    SIGN_IDENTITY="$(find_apple_development_identity || true)"
    if [[ -n "$SIGN_IDENTITY" ]]; then
      SIGNING_KIND="apple-development"
      SIGN_TIMESTAMP_OPTION="--timestamp=none"
      SKIP_NOTARY="1"
    fi
  fi
elif [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
  SIGNING_KIND="developer-id"
elif [[ "$SIGN_IDENTITY" == Apple\ Development:* ]]; then
  SIGNING_KIND="apple-development"
  SIGN_TIMESTAMP_OPTION="--timestamp=none"
  SKIP_NOTARY="1"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  cat >&2 <<'EOF'
error: no usable macOS signing identity found.

Install an Apple Developer certificate, or set:
  FUND_PULSE_SIGN_IDENTITY="Developer ID Application: ..."
  FUND_PULSE_SIGN_IDENTITY="Apple Development: ..."

Unsigned/ad-hoc packages are intentionally refused because downloaded macOS
apps can be blocked by Gatekeeper as damaged or untrusted.
EOF
  exit 1
fi

if [[ "$SIGNING_KIND" == "custom" ]]; then
  cat >&2 <<EOF
error: unsupported signing identity "$SIGN_IDENTITY".

Use either a Developer ID Application identity for public distribution or an
Apple Development identity for local/test distribution.
EOF
  exit 1
fi

if [[ "$SIGNING_KIND" == "apple-development" ]]; then
  cat >&2 <<EOF
warning: using Apple Development signing identity:
  $SIGN_IDENTITY

This matches the older local/test release style. It is not notarized and is
not a public distribution signature, but it avoids the ad-hoc signature that
causes downloaded apps to be reported as damaged.
EOF
fi

if [[ "$SKIP_NOTARY" != "1" ]]; then
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    cat >&2 <<EOF
error: missing notarytool keychain profile "$NOTARY_PROFILE".

Create it once with one of these forms:
  xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>
  xcrun notarytool store-credentials "$NOTARY_PROFILE" --key <AuthKey.p8> --key-id <key-id> --issuer <issuer-id>

Set FUND_PULSE_NOTARY_PROFILE to use a different profile name.
EOF
    exit 1
  fi
fi

FUND_PULSE_BUILD_CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --build

rm -rf "$WORK_DIR" "$NOTARY_ZIP_PATH"
mkdir -p "$OUT_DIR" "$WORK_DIR"

codesign --force --deep --options runtime "$SIGN_TIMESTAMP_OPTION" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP_PATH"

if [[ "$SKIP_NOTARY" != "1" ]]; then
  xcrun notarytool submit "$NOTARY_ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
fi

ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
cp -R "$APP_BUNDLE" "$WORK_DIR/fund-pulse.app"
ln -s /Applications "$WORK_DIR/Applications"

create_dmg

codesign --force "$SIGN_TIMESTAMP_OPTION" --sign "$SIGN_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

if [[ "$SKIP_NOTARY" != "1" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  xcrun syspolicy_check distribution "$APP_BUNDLE"
fi

rm -rf "$WORK_DIR"

echo "Created $ZIP_PATH"
echo "Created $DMG_PATH"
