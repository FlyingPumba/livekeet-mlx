#!/usr/bin/env bash
set -euo pipefail
TOOLCHAIN="$HOME/Library/Developer/Toolchains/swift-6.2.3-RELEASE.xctoolchain/usr/bin/swift"
if [[ -n "${LIVEKEET_SWIFT:-}" ]]; then
  exec "$LIVEKEET_SWIFT" "$@"
elif [[ -x "$TOOLCHAIN" ]]; then
  exec "$TOOLCHAIN" "$@"
else
  exec xcrun swift "$@"
fi
