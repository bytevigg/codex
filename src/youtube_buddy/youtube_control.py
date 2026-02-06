from __future__ import annotations

import subprocess


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


class YouTubeController:
    def pause(self) -> bool:
        return self._run("pause")

    def resume(self) -> bool:
        return self._run("play")

    def _run(self, action: str) -> bool:
        scripts = [
            _CHROME_SCRIPT_TEMPLATE % action,
            _SAFARI_SCRIPT_TEMPLATE % action,
        ]
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
