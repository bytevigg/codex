from enum import Enum


class SessionState(str, Enum):
    IDLE = "idle"
    TRIGGERED = "triggered"
    PAUSED = "paused"
    CAPTURING = "capturing"
    RESPONDING = "responding"
    RESUMING = "resuming"
