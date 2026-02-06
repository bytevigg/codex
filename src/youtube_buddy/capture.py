from __future__ import annotations

from io import BytesIO

import mss
from PIL import Image


def capture_screen_png() -> bytes:
    with mss.mss() as sct:
        monitor = sct.monitors[1]
        raw = sct.grab(monitor)
        image = Image.frombytes("RGB", raw.size, raw.bgra, "raw", "BGRX")
        out = BytesIO()
        image.save(out, format="PNG")
        return out.getvalue()
