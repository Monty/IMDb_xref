"""File-based JSON cache for scraped IMDb data.

Cache files live in .xref_cache/ in the project root, one JSON file per ID:
  .xref_cache/tt6468322.json   — show data
  .xref_cache/nm1234567.json   — person/filmography data
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Optional

from models import Filmography, Show

CACHE_DIR = Path(__file__).resolve().parent.parent / ".xref_cache"


def _ensure_dir() -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)


def _cache_path(key: str) -> Path:
    """Return the cache file path for a tconst or nconst."""
    _ensure_dir()
    return CACHE_DIR / f"{key}.json"


def get_show(tconst: str) -> Optional[Show]:
    """Load a Show from cache, or None if not found."""
    path = _cache_path(tconst)
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return Show(**data)
    except (json.JSONDecodeError, TypeError, KeyError):
        return None


def save_show(show: Show) -> Path:
    """Write a Show to cache. Returns the cache file path."""
    path = _cache_path(show.tconst)
    path.write_text(show.model_dump_json(indent=2), encoding="utf-8")
    return path


def get_filmography(nconst: str) -> Optional[Filmography]:
    """Load a Filmography from cache, or None if not found."""
    path = _cache_path(nconst)
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return Filmography(**data)
    except (json.JSONDecodeError, TypeError, KeyError):
        return None


def save_filmography(fg: Filmography) -> Path:
    """Write a Filmography to cache. Returns the cache file path.

    Refuses to cache a filmography with no roles. Everyone IMDb has a page
    for has at least one credit, so an empty result means the scrape failed
    -- a WAF challenge, a layout change, a truncated page -- and caching it
    would make that failure permanent and invisible.
    """
    if not fg.roles:
        raise ValueError(
            f"refusing to cache empty filmography for {fg.nconst} "
            f"(name: {fg.name!r}) -- the scrape did not return credits"
        )
    path = _cache_path(fg.nconst)
    path.write_text(fg.model_dump_json(indent=2), encoding="utf-8")
    return path


def list_cached_titles() -> list[str]:
    """Return all cached tconst IDs."""
    _ensure_dir()
    return sorted(str(p.stem) for p in CACHE_DIR.glob("tt*.json"))


def list_cached_persons() -> list[str]:
    """Return all cached nconst IDs."""
    _ensure_dir()
    return sorted(str(p.stem) for p in CACHE_DIR.glob("nm*.json"))


def clear_cache() -> int:
    """Remove all cache files. Returns number of files removed."""
    _ensure_dir()
    count = 0
    for p in CACHE_DIR.glob("*.json"):
        p.unlink()
        count += 1
    return count
