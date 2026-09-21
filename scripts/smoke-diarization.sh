#!/usr/bin/env bash
# Explicit opt-in: download a native speaker model and test chunked inference.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 2 || ( "$1" != sortformer && "$1" != ls-eend ) ]]; then
  echo "Usage: $0 {sortformer|ls-eend} MONO_16KHZ_PCM16_WAV" >&2
  exit 2
fi
PCM_FILE=$(mktemp "${TMPDIR:-/tmp}/livekeet-diarization.XXXXXX")
trap 'rm -f "$PCM_FILE"' EXIT
/usr/bin/python3 - "$2" "$PCM_FILE" <<'PY'
import struct, sys, wave
with wave.open(sys.argv[1]) as audio:
    if (audio.getnchannels(), audio.getframerate(), audio.getsampwidth()) != (1, 16000, 2):
        raise SystemExit('Use a mono 16 kHz 16-bit PCM WAV for this smoke test.')
    samples = [sample[0] / 32768 for sample in struct.iter_unpack('<h', audio.readframes(audio.getnframes()))]
with open(sys.argv[2], 'wb') as output:
    output.write(struct.pack('<%df' % len(samples), *samples))
PY
export LIVEKEET_SMOKE_DIARIZER="$1"
export LIVEKEET_DIARIZATION_PCM="$PCM_FILE"
./scripts/swift.sh test --filter DiarizationTests/testNativeStreamingSmoke
