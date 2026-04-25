from __future__ import annotations

from collections import defaultdict, deque
from collections.abc import Callable
from dataclasses import dataclass
from threading import Lock
from time import time

from redis import Redis
from redis.exceptions import RedisError

from app.core.config import settings


@dataclass
class LimitDecision:
    allowed: bool
    retry_after_seconds: int


class RateLimitBackend:
    def check(self, key: str, max_attempts: int, window_seconds: int) -> LimitDecision:
        raise NotImplementedError

    def reset(self) -> None:
        return None


class MemoryRateLimitBackend(RateLimitBackend):
    def __init__(self, now_fn: Callable[[], float] | None = None) -> None:
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()
        self._now_fn = now_fn or time

    def check(self, key: str, max_attempts: int, window_seconds: int) -> LimitDecision:
        with self._lock:
            now = self._now_fn()
            events = self._events[key]
            while events and now - events[0] >= window_seconds:
                events.popleft()

            if len(events) >= max_attempts:
                retry_after = int(window_seconds - (now - events[0]))
                return LimitDecision(allowed=False, retry_after_seconds=max(retry_after, 1))

            events.append(now)
            return LimitDecision(allowed=True, retry_after_seconds=0)

    def reset(self) -> None:
        with self._lock:
            self._events.clear()


class RedisRateLimitBackend(RateLimitBackend):
    def __init__(self, redis_url: str) -> None:
        self._redis = Redis.from_url(redis_url, decode_responses=True)

    def check(self, key: str, max_attempts: int, window_seconds: int) -> LimitDecision:
        bucket_key = f"rate-limit:{key}"
        try:
            current = self._redis.incr(bucket_key)
            if current == 1:
                self._redis.expire(bucket_key, window_seconds)
            if current > max_attempts:
                ttl = self._redis.ttl(bucket_key)
                return LimitDecision(allowed=False, retry_after_seconds=max(ttl, 1))
            return LimitDecision(allowed=True, retry_after_seconds=0)
        except RedisError:
            return LimitDecision(allowed=True, retry_after_seconds=0)


class RateLimitService:
    def __init__(self) -> None:
        self._memory_backend = MemoryRateLimitBackend()
        self._redis_backend: RedisRateLimitBackend | None = None

    def check(self, key: str, max_attempts: int, window_seconds: int) -> LimitDecision:
        return self._backend().check(key=key, max_attempts=max_attempts, window_seconds=window_seconds)

    def _backend(self) -> RateLimitBackend:
        if settings.rate_limit_backend == "redis":
            if self._redis_backend is None:
                self._redis_backend = RedisRateLimitBackend(settings.redis_url)
            return self._redis_backend
        return self._memory_backend

    def reset_for_tests(self) -> None:
        self._memory_backend.reset()


rate_limit_service = RateLimitService()


def default_auth_limits() -> tuple[int, int]:
    return settings.auth_rate_limit_attempts, settings.auth_rate_limit_window_seconds
