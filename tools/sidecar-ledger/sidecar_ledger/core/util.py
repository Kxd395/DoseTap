from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def iso_utc(dt: datetime) -> str:
    # Always store a timezone-aware UTC timestamp.
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat()


def iso_local(dt: datetime) -> str:
    # Store local timestamp string; on macOS this will reflect system TZ.
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone().isoformat()
