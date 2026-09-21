#!/usr/bin/env bash
set -euo pipefail
PREFIX="${1:-$HOME/.local}"
BUILD_DIR="${2:-.build/release}"
INSTALL_DIR="$PREFIX/lib/livekeet"
mkdir -p "$INSTALL_DIR" "$PREFIX/bin"
# Copy to a temporary file before replacing the running executable during update.
cp "$BUILD_DIR/livekeet" "$INSTALL_DIR/livekeet.new"
chmod +x "$INSTALL_DIR/livekeet.new"
mv -f "$INSTALL_DIR/livekeet.new" "$INSTALL_DIR/livekeet"
for resource in "$BUILD_DIR"/*.bundle; do
  [[ -d "$resource" ]] || continue
  ditto "$resource" "$INSTALL_DIR/$(basename "$resource")"
done
ditto .build/metallib/mlx-swift_Cmlx.bundle "$INSTALL_DIR/mlx-swift_Cmlx.bundle"
python3 - "$INSTALL_DIR/install.json" "$PWD" "$PREFIX" <<'PY'
import json, pathlib, sys
pathlib.Path(sys.argv[1]).write_text(json.dumps({"source": sys.argv[2], "prefix": str(pathlib.Path(sys.argv[3]).expanduser().resolve())}) + "\n")
PY
ln -sfn "$INSTALL_DIR/livekeet" "$PREFIX/bin/livekeet"
printf 'Installed %s/bin/livekeet\nEnsure %s/bin is on PATH.\n' "$PREFIX" "$PREFIX"
