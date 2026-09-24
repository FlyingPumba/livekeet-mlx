#!/usr/bin/env bash
# Local Mac app workflow, matching ~/src/set: build, install, open.
set -euo pipefail
cd "$(dirname "$0")"
DESTINATION="${LIVEKEET_APP_DESTINATION:-/Applications/Livekeet.app}"

if pgrep -x LivekeetApp >/dev/null; then
  echo 'Quit Livekeet before installing so an active recording cannot be interrupted.' >&2
  exit 1
fi
make build-app SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
mkdir -p "$(dirname "$DESTINATION")"
STAGING=$(mktemp -d "$(dirname "$DESTINATION")/.livekeet-install.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto .build/debug/Livekeet.app "$STAGING/Livekeet.app"
codesign --verify --deep --strict "$STAGING/Livekeet.app"
if [[ -e "$DESTINATION" ]]; then
  mv "$DESTINATION" "$STAGING/previous.app"
fi
if ! mv "$STAGING/Livekeet.app" "$DESTINATION"; then
  [[ ! -e "$STAGING/previous.app" ]] || mv "$STAGING/previous.app" "$DESTINATION"
  exit 1
fi
printf 'Installed %s\n' "$DESTINATION"
if [[ "${LIVEKEET_OPEN:-1}" != 0 ]]; then open "$DESTINATION"; fi
