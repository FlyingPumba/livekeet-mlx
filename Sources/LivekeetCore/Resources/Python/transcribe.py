#!/usr/bin/env python3
"""Persistent local ASR for architectures not yet supported by our Swift runtime."""
import contextlib
import json
import os
import sys
import wave


def reply(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


def load(model_id):
    import torch
    from transformers import AutoProcessor, MoonshineStreamingForConditionalGeneration, VoxtralForConditionalGeneration

    processor = AutoProcessor.from_pretrained(model_id)
    if "moonshine-streaming" in model_id.lower():
        # Small enough for CPU; avoids unsupported Metal operators in this architecture.
        model = MoonshineStreamingForConditionalGeneration.from_pretrained(model_id).eval()
        kind, device = "moonshine", "cpu"
    elif "voxtral-mini-3b" in model_id.lower():
        device = "mps" if torch.backends.mps.is_available() else "cpu"
        dtype = torch.float16 if device == "mps" else torch.float32
        model = VoxtralForConditionalGeneration.from_pretrained(model_id, torch_dtype=dtype).to(device).eval()
        kind = "voxtral"
    else:
        raise ValueError(f"Unsupported Python speech model: {model_id}")
    return processor, model, kind, device


def transcribe(loaded, path):
    import numpy as np
    import torch
    processor, model, kind, device = loaded
    with wave.open(path) as wav:
        if (wav.getnchannels(), wav.getframerate(), wav.getsampwidth()) != (1, 16000, 2):
            raise ValueError("Expected mono 16 kHz PCM16 WAV")
        audio = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2").astype(np.float32) / 32768.0
    if not len(audio):
        return ""
    if kind == "moonshine":
        inputs = processor(audio, sampling_rate=16000, return_tensors="pt")
        # Preserve attention_mask: it controls the streaming encoder's sliding window.
        max_tokens = min(512, int(len(audio) / 16000 * 6.5) + 2)
        with torch.inference_mode():
            output = model.generate(**inputs, max_new_tokens=max_tokens, do_sample=False)
        return processor.batch_decode(output, skip_special_tokens=True)[0].strip()
    # The transcription-specific prompt avoids turning audio into a chat request.
    inputs = processor.apply_transcription_request(audio=path, model_id=model.config._name_or_path, return_tensors="pt")
    inputs = inputs.to(device, dtype=model.dtype)
    with torch.inference_mode():
        output = model.generate(**inputs, max_new_tokens=512, do_sample=False)
    output = output[:, inputs.input_ids.shape[1]:]
    return processor.batch_decode(output, skip_special_tokens=True)[0].strip()


def main():
    os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
    try:
        with contextlib.redirect_stdout(sys.stderr):
            loaded = load(sys.argv[1])
        reply({"ok": True})
    except Exception as error:
        reply({"error": f"Speech helper could not load the model: {error}. Install support with scripts/setup-python.sh speech and select that Python executable in Advanced settings."})
        return 1
    for line in sys.stdin:
        try:
            request = json.loads(line)
            if request.get("op") != "transcribe":
                raise ValueError("Expected a transcribe request")
            with contextlib.redirect_stdout(sys.stderr):
                text = transcribe(loaded, request["path"])
            reply({"text": text})
        except Exception as error:
            reply({"error": f"Local speech recognition failed: {error}"})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
