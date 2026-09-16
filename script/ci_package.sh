#!/usr/bin/env bash
set -euo pipefail

# Called only by trusted packaging workflows. Never echo credentials or enable xtrace.
: "${MACOS_CERTIFICATE_BASE64:?Missing MACOS_CERTIFICATE_BASE64}"
: "${MACOS_CERTIFICATE_PASSWORD:?Missing MACOS_CERTIFICATE_PASSWORD}"
: "${FUND_PULSE_SIGN_IDENTITY:?Missing FUND_PULSE_SIGN_IDENTITY}"
: "${APPLE_ID:?Missing APPLE_ID}"
: "${APPLE_TEAM_ID:?Missing APPLE_TEAM_ID}"
: "${APPLE_APP_PASSWORD:?Missing APPLE_APP_PASSWORD}"
: "${RUNNER_TEMP:?Missing RUNNER_TEMP}"
[[ "$FUND_PULSE_SIGN_IDENTITY" == 'Developer ID Application:'* ]] || {
  echo 'CI requires a Developer ID Application certificate.' >&2
  exit 1
}

SIGNING_DIR="$(mktemp -d "$RUNNER_TEMP/fund-pulse-signing.XXXXXX")"
KEYCHAIN_PATH="$SIGNING_DIR/signing.keychain-db"
CERTIFICATE_PATH="$SIGNING_DIR/signing.p12"
KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
ORIGINAL_KEYCHAINS=()
while IFS= read -r keychain; do
  ORIGINAL_KEYCHAINS+=("$keychain")
done < <(security list-keychains -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')

cleanup() {
  result=$?
  trap - EXIT
  security list-keychains -d user -s ${ORIGINAL_KEYCHAINS[@]+"${ORIGINAL_KEYCHAINS[@]}"} || result=1
  security delete-keychain "$KEYCHAIN_PATH" || result=1
  rm -rf "$SIGNING_DIR"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
umask 077
printf '%s' "$MACOS_CERTIFICATE_BASE64" | base64 --decode > "$CERTIFICATE_PATH"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" ${ORIGINAL_KEYCHAINS[@]+"${ORIGINAL_KEYCHAINS[@]}"}
security import "$CERTIFICATE_PATH" -k "$KEYCHAIN_PATH" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
rm -f "$CERTIFICATE_PATH"

export FUND_PULSE_NOTARY_PROFILE="fund-pulse-ci"
export FUND_PULSE_NOTARY_KEYCHAIN="$KEYCHAIN_PATH"
export FUND_PULSE_SKIP_NOTARY=0
xcrun notarytool store-credentials "$FUND_PULSE_NOTARY_PROFILE" --keychain "$KEYCHAIN_PATH" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" >/dev/null
npm run package
