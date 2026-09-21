#!/usr/bin/env python3
"""Optional local speaker engines. JSON-lines on stdout; diagnostics on stderr.

WeSpeaker implementation is ported from LucaDeLeo/livekeet (see LICENSE).
No audio is sent to a service. Models download from Hugging Face on first use.
"""
import contextlib
import json
import math
from io import BytesIO
import os
import sys
import wave


def create_engine(name):
    import numpy as np
    if name == "wespeaker":
        from wespeaker import SpeakerEmbedder, SpeakerTracker
        embedder = SpeakerEmbedder()
        trackers = {
            channel: SpeakerTracker("0", "unused", secondary_names=[str(i) for i in range(1, 5)])
            for channel in ("mic", "system")
        }

        def identify(request):
            with wave.open(request["path"], "rb") as audio:
                if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) != (1, 2, 16000):
                    raise ValueError("Expected mono 16-bit 16 kHz WAV")
                samples = np.frombuffer(audio.readframes(audio.getnframes()), dtype="<i2").astype(np.float32) / 32768
            embedding = embedder.extract_embedding(samples)
            speaker = int(trackers[request["channel"]].identify(embedding)) if embedding is not None else 0
            return {"speaker": speaker}
        return identify
    model_ids = {
        "pyannote": "pyannote/speaker-diarization-3.1",
        "community-1": "pyannote/speaker-diarization-community-1",
        "diarizen": "BUT-FIT/diarizen-wavlm-large-s80-md-v2",
        "suplime": "rewayai/suplime",
        "suplime-large": "rewayai/suplime-large",
    }
    if name not in model_ids:
        raise ValueError("Unknown engine: " + name)
    token = os.environ.get("HF_TOKEN")
    if name in ("pyannote", "community-1") and not token:
        terms = model_ids[name] + (" and pyannote/segmentation-3.0" if name == "pyannote" else "")
        raise ValueError("Accept " + terms + " model access on Hugging Face and set HF_TOKEN or [pyannote] token in the CLI config.")
    import torch
    # CPU is portable across the supported Macs. Do not silently switch to CUDA/MPS
    # or enable unsafe deserialization globally to work around incompatible models.
    if name == "diarizen":
        from diarizen.pipelines.inference import DiariZenPipeline
        pipeline = DiariZenPipeline.from_pretrained(model_ids[name])
    else:
        from pyannote.audio import Pipeline
        pipeline = Pipeline.from_pretrained(model_ids[name], token=token)
    if pipeline is None:
        raise ValueError("Cannot access " + model_ids[name] + ". Check model access conditions and HF_TOKEN.")

    def diarize(request):
        channels = {}
        for channel, source in request["channels"].items():
            samples = np.fromfile(source["path"], dtype="<f4", count=source["count"])
            if len(samples) < 8000:
                channels[channel] = []
                continue
            if name == "diarizen":
                # The upstream DiariZen wrapper accepts a WAV stream, not a tensor dict.
                stream = BytesIO()
                with wave.open(stream, "wb") as audio:
                    audio.setnchannels(1)
                    audio.setsampwidth(2)
                    audio.setframerate(16000)
                    audio.writeframes((np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())
                stream.seek(0)
                result = pipeline(stream)
            else:
                # Tensor input avoids torchcodec/FFmpeg for pyannote and SUPlime.
                result = pipeline({"waveform": torch.from_numpy(samples.copy()).unsqueeze(0), "sample_rate": 16000})
            channels[channel] = serialize_turns(result, len(samples) / 16000)
        return {"channels": channels}
    return diarize


def serialize_turns(result, duration):
    """Normalize both legacy Annotation and pyannote 4.x DiarizeOutput."""
    annotation = getattr(result, "exclusive_speaker_diarization", None)
    if annotation is None:
        annotation = getattr(result, "speaker_diarization", result)
    labels, turns = {}, []
    for turn, _, label in sorted(annotation.itertracks(yield_label=True), key=lambda item: item[0].start):
        if not math.isfinite(turn.start) or not math.isfinite(turn.end):
            raise ValueError("Speaker model returned non-finite timestamps")
        start, end = max(0, turn.start), min(duration, turn.end)
        if end <= start:
            continue
        index = labels.setdefault(label, len(labels))
        turns.append({"start": start, "end": end, "speaker": index})
    return turns


def serve(input_stream=sys.stdin, output_stream=sys.stdout, factory=create_engine):
    def reply(payload):
        output_stream.write(json.dumps(payload, ensure_ascii=False) + "\n")
        output_stream.flush()

    try:
        with contextlib.redirect_stdout(sys.stderr):
            engine = factory(sys.argv[1])
        reply({"ok": True})
    except Exception as exc:
        reply({"error": f"{type(exc).__name__}: {exc}. Install this engine from Settings → Models → Speaker identification, or run scripts/setup-python.sh speakers."})
        return 1
    for line in input_stream:
        try:
            request = json.loads(line)
            if request.get("op") == "quit":
                return 0
            with contextlib.redirect_stdout(sys.stderr):
                response = engine(request)
            reply(response)
        except Exception as exc:
            reply({"error": f"{type(exc).__name__}: {exc}"})
    return 0


if __name__ == "__main__":
    sys.exit(serve())
