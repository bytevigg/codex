from __future__ import annotations

import base64
from pathlib import Path

from openai import OpenAI

from youtube_buddy.config import Settings


SYSTEM_PROMPT = """You are a playful character companion for young kids.
Follow these rules strictly:
- Keep response kid-safe and warm.
- Avoid blocked topics and redirect gently.
- Never mention violence, fear, medical, politics, religion, or adult content.
- Keep to 1-2 short sentences and around 10 seconds spoken.
- End naturally (no trailing unfinished phrase).
"""


class AIClient:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.client = OpenAI()

    def transcribe(self, audio_path: Path) -> str:
        with audio_path.open("rb") as f:
            out = self.client.audio.transcriptions.create(model="gpt-4o-mini-transcribe", file=f)
        return out.text.strip()

    def generate_reply(self, user_text: str, screenshot_png: bytes) -> str:
        image_data = base64.b64encode(screenshot_png).decode("ascii")
        prompt = (
            f"Child said: {user_text!r}\n"
            f"Blocked topics: {', '.join(self.settings.blocked_topics)}\n"
            "Respond in-character with what is likely on a YouTube kids screen."
        )

        resp = self.client.responses.create(
            model="gpt-4.1-mini",
            input=[
                {
                    "role": "system",
                    "content": [{"type": "input_text", "text": SYSTEM_PROMPT}],
                },
                {
                    "role": "user",
                    "content": [
                        {"type": "input_text", "text": prompt},
                        {"type": "input_image", "image_url": f"data:image/png;base64,{image_data}"},
                    ],
                },
            ],
            max_output_tokens=90,
        )
        return (resp.output_text or "Let's keep having fun and learning together!").strip()

    def speak(self, text: str) -> None:
        speech = self.client.audio.speech.create(
            model="gpt-4o-mini-tts",
            voice=self.settings.voice,
            input=text,
        )
        wav_bytes = speech.read()

        try:
            import sounddevice as sd
            import soundfile as sf
        except ImportError as exc:
            raise RuntimeError("Install youtube-buddy[audio] to enable audio playback") from exc

        import io

        data, samplerate = sf.read(io.BytesIO(wav_bytes), dtype="float32")
        sd.play(data, samplerate)
        sd.wait()
