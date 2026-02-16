from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from urllib.parse import parse_qs, urlparse


_CHROME_SCRIPT_TEMPLATE = r'''
tell application "Google Chrome"
  if (count of windows) = 0 then return "no-window"
  set theTab to active tab of front window
  set tabUrl to URL of theTab
  if tabUrl does not contain "youtube.com" then return "not-youtube"
  execute theTab javascript "var v=document.querySelector('video'); if (v){v.%s(); 'ok'} else {'no-video'};"
end tell
'''

_SAFARI_SCRIPT_TEMPLATE = r'''
tell application "Safari"
  if (count of windows) = 0 then return "no-window"
  tell front document
    set tabUrl to URL
    if tabUrl does not contain "youtube.com" then return "not-youtube"
    do JavaScript "var v=document.querySelector('video'); if (v){v.%s(); 'ok'} else {'no-video'};" in current tab of front window
  end tell
end tell
'''

_CHROME_CONTEXT_SCRIPT = r'''
tell application "Google Chrome"
  if (count of windows) = 0 then return ""
  set theTab to active tab of front window
  set tabUrl to URL of theTab
  if tabUrl does not contain "youtube.com" then return ""
  set payload to execute theTab javascript "JSON.stringify({url: location.href, title: document.title || '', channel: (document.querySelector('#channel-name a')?.textContent || document.querySelector('ytd-channel-name a')?.textContent || '').trim(), description: (document.querySelector('meta[name=description]')?.content || '').trim()});"
  return payload
end tell
'''

_SAFARI_CONTEXT_SCRIPT = r'''
tell application "Safari"
  if (count of windows) = 0 then return ""
  tell front document
    set tabUrl to URL
    if tabUrl does not contain "youtube.com" then return ""
    set payload to do JavaScript "JSON.stringify({url: location.href, title: document.title || '', channel: (document.querySelector('#channel-name a')?.textContent || document.querySelector('ytd-channel-name a')?.textContent || '').trim(), description: (document.querySelector('meta[name=description]')?.content || '').trim()});" in current tab of front window
    return payload
  end tell
end tell
'''


@dataclass(slots=True)
class ActiveVideoContext:
    video_id: str
    channel_id: str
    title: str
    description: str
    series_hint: str


def _series_hint_from_title(title: str) -> str:
    clean = (title or "").strip()
    if " - " in clean:
        return clean.split(" - ", 1)[0].strip()
    if "|" in clean:
        return clean.split("|", 1)[0].strip()
    return " ".join(clean.split()[:4]).strip() or "unknown-series"


def _video_id_from_url(url: str) -> str:
    query = parse_qs(urlparse(url).query)
    value = query.get("v", [""])[0]
    return value or "unknown-video"


class YouTubeController:
    def pause(self) -> bool:
        return self._run_action("pause")

    def resume(self) -> bool:
        return self._run_action("play")

    def get_active_video_context(self) -> ActiveVideoContext | None:
        for script in (_CHROME_CONTEXT_SCRIPT, _SAFARI_CONTEXT_SCRIPT):
            result = subprocess.run(
                ["osascript", "-e", script],
                check=False,
                text=True,
                capture_output=True,
            )
            payload = result.stdout.strip()
            if result.returncode != 0 or not payload:
                continue
            try:
                data = json.loads(payload)
            except json.JSONDecodeError:
                continue

            url = str(data.get("url", ""))
            title = str(data.get("title", ""))
            channel = str(data.get("channel", "")).strip() or "unknown-channel"
            description = str(data.get("description", ""))
            return ActiveVideoContext(
                video_id=_video_id_from_url(url),
                channel_id=channel,
                title=title,
                description=description,
                series_hint=_series_hint_from_title(title),
            )
        return None

    def _run_action(self, action: str) -> bool:
        scripts = [_CHROME_SCRIPT_TEMPLATE % action, _SAFARI_SCRIPT_TEMPLATE % action]
        for script in scripts:
            result = subprocess.run(
                ["osascript", "-e", script],
                check=False,
                text=True,
                capture_output=True,
            )
            if result.returncode == 0 and "not-youtube" not in result.stdout:
                return True
        return False
