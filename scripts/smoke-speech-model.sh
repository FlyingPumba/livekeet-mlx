#!/usr/bin/env bash
# Explicit opt-in: downloads one model and transcribes a supplied audio file.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 HUGGING_FACE_MODEL_ID AUDIO_FILE" >&2
  exit 2
fi
export LIVEKEET_SMOKE_MODEL="$1"
export LIVEKEET_SMOKE_WAV="$2"
# Set LIVEKEET_SMOKE_PYTHON for models using the optional Python helper.
./scripts/swift.sh build --build-tests
bash scripts/build-metallib.sh .build/metallib
TEST_RESOURCES=.build/debug/livekeet-mlxPackageTests.xctest/Contents/Resources
mkdir -p "$TEST_RESOURCES"
ditto .build/metallib/mlx-swift_Cmlx.bundle "$TEST_RESOURCES/mlx-swift_Cmlx.bundle"
./scripts/swift.sh test --skip-build --filter SpeechModelTests/testSelectedModelSmoke
