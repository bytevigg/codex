from datetime import datetime, timedelta

from youtube_buddy.rate_limit import InteractionLimiter


def test_cooldown_enforced():
    limiter = InteractionLimiter(max_per_hour=3, cooldown_seconds=45)
    now = datetime(2025, 1, 1, 10, 0, 0)
    assert limiter.can_interact(now)
    limiter.record(now)
    assert not limiter.can_interact(now + timedelta(seconds=10))
    assert limiter.can_interact(now + timedelta(seconds=46))


def test_hourly_cap_enforced():
    limiter = InteractionLimiter(max_per_hour=2, cooldown_seconds=0)
    now = datetime(2025, 1, 1, 10, 0, 0)
    limiter.record(now)
    limiter.record(now + timedelta(minutes=5))
    assert not limiter.can_interact(now + timedelta(minutes=10))
    assert limiter.can_interact(now + timedelta(hours=1, minutes=1))
