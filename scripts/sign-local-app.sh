#!/usr/bin/env bash
# Keep local updates on the same certificate so macOS can retain privacy grants.
set -euo pipefail
APP=${1:?Usage: sign-local-app.sh APP ENTITLEMENTS}
ENTITLEMENTS=${2:?Usage: sign-local-app.sh APP ENTITLEMENTS}
IDENTITY_FILE=${LIVEKEET_SIGNING_IDENTITY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/livekeet/signing-identity}
REQUESTED_IDENTITY=${SIGNING_IDENTITY:-}

if [[ "$REQUESTED_IDENTITY" == - ]]; then
  echo 'Warning: ad-hoc signing was explicitly requested; privacy permissions may reset after rebuilding.' >&2
  codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP"
  codesign --verify --deep --strict "$APP"
  exit 0
fi

if [[ -z "$REQUESTED_IDENTITY" && -f "$IDENTITY_FILE" ]]; then
  REQUESTED_IDENTITY=$(cat "$IDENTITY_FILE")
  if [[ ! "$REQUESTED_IDENTITY" =~ ^[[:xdigit:]]{40}$ ]]; then
    echo "Invalid saved signing identity: $IDENTITY_FILE. Set SIGNING_IDENTITY to a certificate name or SHA-1." >&2
    exit 1
  fi
fi

IDENTITIES=$(security find-identity -v -p codesigning)
HASHES=()
NAMES=()
IDENTITY_PATTERN='^[[:space:]]*[0-9]+\)[[:space:]]+([[:xdigit:]]{40})[[:space:]]+"(.*)"$'
while IFS= read -r line; do
  if [[ "$line" =~ $IDENTITY_PATTERN ]]; then
    HASHES+=("${BASH_REMATCH[1]}")
    NAMES+=("${BASH_REMATCH[2]}")
  fi
done <<< "$IDENTITIES"

SELECTED_IDENTITY=
SELECTED_NAME=
for ((i = 0; i < ${#HASHES[@]}; i++)); do
  if [[ "$REQUESTED_IDENTITY" == "${HASHES[$i]}" || "$REQUESTED_IDENTITY" == "${NAMES[$i]}" ||
        ( -z "$REQUESTED_IDENTITY" && ${#HASHES[@]} == 1 ) ]]; then
    if [[ -n "$SELECTED_IDENTITY" ]]; then
      echo 'More than one certificate matches. Set SIGNING_IDENTITY to its exact SHA-1.' >&2
      exit 1
    fi
    SELECTED_IDENTITY=${HASHES[$i]}
    SELECTED_NAME=${NAMES[$i]}
  fi
done

if [[ -z "$SELECTED_IDENTITY" ]]; then
  if [[ -n "$REQUESTED_IDENTITY" ]]; then
    echo "The saved/requested signing certificate is unavailable: $REQUESTED_IDENTITY" >&2
    echo 'Unlock its keychain or explicitly select another SIGNING_IDENTITY. Keeping the identity prevents permission resets.' >&2
  else
    echo 'Select a stable signing certificate with SIGNING_IDENTITY (name or SHA-1).' >&2
    echo 'List certificates with: security find-identity -v -p codesigning' >&2
    echo 'Use an Apple Development certificate or a local Code Signing certificate created in Keychain Access.' >&2
    echo 'For disposable builds only, explicitly set SIGNING_IDENTITY=- to use ad-hoc signing.' >&2
  fi
  exit 1
fi

# Local self-signed certificates do not have an Apple team identifier. Keep the
# existing local runtime mode; the release target separately enables hardening.
echo "Signing local app with $SELECTED_NAME ($SELECTED_IDENTITY)"
codesign --force --deep --sign "$SELECTED_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"

# Pin only after a successful signature. Never silently replace a missing identity
# with ad-hoc signing or another available certificate on a future build.
umask 077
mkdir -p "$(dirname "$IDENTITY_FILE")"
IDENTITY_TEMP=$(mktemp "${IDENTITY_FILE}.XXXXXX")
trap 'rm -f "$IDENTITY_TEMP"' EXIT
printf '%s\n' "$SELECTED_IDENTITY" > "$IDENTITY_TEMP"
mv "$IDENTITY_TEMP" "$IDENTITY_FILE"
