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
NOTARY_ZIP_PATH="$OUT_DIR/fund-pulse-$VERSION-$ARCH-swift-notary.zip"
SIGN_IDENTITY="${FUND_PULSE_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${FUND_PULSE_NOTARY_PROFILE:-fund-pulse}"
SKIP_NOTARY="${FUND_PULSE_SKIP_NOTARY:-0}"
SIGNING_KIND="custom"

cd "$ROOT_DIR"

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

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(find_developer_id_identity || true)"
  if [[ -n "$SIGN_IDENTITY" ]]; then
    SIGNING_KIND="developer-id"
  else
    SIGN_IDENTITY="$(find_apple_development_identity || true)"
    if [[ -n "$SIGN_IDENTITY" ]]; then
      SIGNING_KIND="apple-development"
      SKIP_NOTARY="1"
    fi
  fi
elif [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
  SIGNING_KIND="developer-id"
elif [[ "$SIGN_IDENTITY" == Apple\ Development:* ]]; then
  SIGNING_KIND="apple-development"
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

"$ROOT_DIR/script/build_and_run.sh" --build

rm -rf "$WORK_DIR" "$NOTARY_ZIP_PATH"
mkdir -p "$OUT_DIR" "$WORK_DIR"

codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
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

hdiutil create \
  -volname "fund-pulse $VERSION" \
  -srcfolder "$WORK_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
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
