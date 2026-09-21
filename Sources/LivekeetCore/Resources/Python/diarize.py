#!/usr/bin/env python3
"""Optional local speaker engines. JSON-lines on stdout; diagnostics on stderr.

WeSpeaker implementation is ported from LucaDeLeo/livekeet (see LICENSE).
No audio is sent to a service. Models download from Hugging Face on first use.
"""
import contextlib
import json
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
    if name != "pyannote":
        raise ValueError("Unknown engine: " + name)
    token = os.environ.get("HF_TOKEN")
    if not token:
        raise ValueError("pyannote needs HF_TOKEN or [pyannote] token in config; accept the speaker-diarization-3.1 and segmentation-3.0 model terms on Hugging Face.")
    import torch
    from pyannote.audio import Pipeline
    pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1", token=token)
    if pipeline is None:
        raise ValueError("Cannot access pyannote models. Accept the speaker-diarization-3.1 and segmentation-3.0 terms on Hugging Face and check HF_TOKEN.")

    def diarize(request):
        channels = {}
        for channel, source in request["channels"].items():
            samples = np.fromfile(source["path"], dtype="<f4", count=source["count"])
            if len(samples) < 8000:
                channels[channel] = []
                continue
            # Pass an in-memory waveform to avoid a torchcodec/FFmpeg dependency.
            result = pipeline({"waveform": torch.from_numpy(samples.copy()).unsqueeze(0), "sample_rate": 16000})
            annotation = getattr(result, "exclusive_speaker_diarization", result)
            labels, turns = {}, []
            for turn, _, label in annotation.itertracks(yield_label=True):
                index = labels.setdefault(label, len(labels))
                turns.append({"start": turn.start, "end": turn.end, "speaker": index})
            channels[channel] = turns
        return {"channels": channels}
    return diarize


def serve(input_stream=sys.stdin, output_stream=sys.stdout, factory=create_engine):
    def reply(payload):
        output_stream.write(json.dumps(payload, ensure_ascii=False) + "\n")
        output_stream.flush()

    try:
        with contextlib.redirect_stdout(sys.stderr):
            engine = factory(sys.argv[1])
        reply({"ok": True})
    except Exception as exc:
        reply({"error": f"{type(exc).__name__}: {exc}. Install the optional helper with scripts/setup-python.sh."})
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
