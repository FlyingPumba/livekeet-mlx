#!/usr/bin/env bash
# Optional helper dependencies. No models are downloaded until an engine is selected.
set -euo pipefail
VENV="${LIVEKEET_PYTHON_ENV:-$HOME/.local/share/livekeet/python}"
ENGINE="${1:-all}"
case "$ENGINE" in
  all|wespeaker|pyannote|cleanup) ;;
  *) echo 'Usage: scripts/setup-python.sh [all|wespeaker|pyannote|cleanup]' >&2; exit 2 ;;
esac
command -v uv >/dev/null || { echo 'Install uv first: https://docs.astral.sh/uv/' >&2; exit 1; }
if [[ ! -x "$VENV/bin/python" ]]; then uv venv --python 3.12 "$VENV"; fi
PACKAGES=()
if [[ "$ENGINE" == all || "$ENGINE" == wespeaker ]]; then PACKAGES+=("numpy<2.5" 'mlx>=0.25' 'huggingface-hub>=0.30'); fi
if [[ "$ENGINE" == all || "$ENGINE" == pyannote ]]; then PACKAGES+=("numpy<2.5" 'pyannote-audio>=4,<5' 'torch>=2' 'torchaudio>=2'); fi
if [[ "$ENGINE" == all || "$ENGINE" == cleanup ]]; then PACKAGES+=('claude-runner>=0.1.1'); fi
uv pip install --python "$VENV/bin/python" "${PACKAGES[@]}"
printf '\nSet [python] executable = "%s/bin/python" in your CLI config,\nor select that executable in Mac app Settings → Advanced.\n' "$VENV"
