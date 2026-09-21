#!/usr/bin/env python3
"""Install one local speaker engine in an isolated environment; never download weights."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

DIARIZEN_REV = "844f5555b0a98acd0931511fc641a8c5b8ba92c7"
DIARIZEN_URL = "git+https://github.com/BUTSpeechFIT/DiariZen.git@" + DIARIZEN_REV
PACKAGES = {
    "wespeaker": ["numpy<2.5", "mlx>=0.25", "huggingface-hub>=0.30"],
    "pyannote": ["pyannote-audio>=4.0.7,<5"],
    "community-1": ["pyannote-audio>=4.0.7,<5"],
    "suplime": ["suplime==0.2.0"],
    "suplime-large": ["suplime==0.2.0"],
    "diarizen": [
        "numpy<2", "torch==2.5.1", "torchaudio==2.5.1", "huggingface-hub<1",
        "pyannote.core<6", "pyannote.database<6", "pyannote.metrics<4",
        "pyannote.audio @ " + DIARIZEN_URL + "#subdirectory=pyannote-audio",
        "diarizen @ " + DIARIZEN_URL,
        "einops", "toml", "soundfile", "librosa", "torchinfo", "thop", "accelerate==1.6.0",
    ],
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", choices=PACKAGES)
    parser.add_argument("--environment", type=Path)
    args = parser.parse_args()
    uv = shutil.which("uv") or next((str(p) for p in [Path("/opt/homebrew/bin/uv"), Path("/usr/local/bin/uv"), Path.home()/".local/bin/uv"] if p.is_file()), None)
    if uv is None:
        parser.error("Install uv from https://docs.astral.sh/uv/ and try again.")
    environment = args.environment or Path.home()/".local/share/livekeet/diarization"/args.engine
    python = environment/"bin/python"
    if not python.exists():
        subprocess.run([uv, "venv", "--python", "3.11" if args.engine == "diarizen" else "3.12", str(environment)], check=True)
    subprocess.run([uv, "pip", "install", "--python", str(python), *PACKAGES[args.engine]], check=True)
    print(str(python), flush=True)


if __name__ == "__main__":
    main()
