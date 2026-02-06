from __future__ import annotations

import tempfile
from pathlib import Path


def record_child_speech(seconds: int = 3, sample_rate: int = 16000) -> Path:
    try:
        import sounddevice as sd
        import soundfile as sf
    except ImportError as exc:
        raise RuntimeError("Install youtube-buddy[audio] to enable microphone capture") from exc

    frames = int(seconds * sample_rate)
    data = sd.rec(frames, samplerate=sample_rate, channels=1, dtype="float32")
    sd.wait()

    tmp = tempfile.NamedTemporaryFile(prefix="youtube-buddy-", suffix=".wav", delete=False)
    tmp.close()
    sf.write(tmp.name, data, sample_rate)
    return Path(tmp.name)
