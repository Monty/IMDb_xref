"""Data models for IMDb entities."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class CastMember(BaseModel):
    """A single cast or crew member on a show's fullcredits page."""

    nconst: str  # "nm1234567"
    name: str
    job: str  # "actor", "director", "writer", "producer", etc.
    character: str = ""
    episodes: int = 0  # 0 means not specified (e.g. movies, series-level credits)
    rank: int = 0  # billing order within category, 1-based


class Show(BaseModel):
    """A title from IMDb with full cast data."""

    tconst: str  # "tt6468322"
    title: str
    original_title: str = ""
    year: Optional[int] = None
    types: list[str] = Field(default_factory=list)  # ["tvSeries", "tvMiniSeries"]
    genres: list[str] = Field(default_factory=list)
    runtime: str = ""  # e.g. "77 min" or "50m"
    rating: str = ""  # e.g. "8.2"
    cast: list[CastMember] = Field(default_factory=list)
    scraped: datetime = Field(default_factory=datetime.utcnow)


class Person(BaseModel):
    """A person (actor, director, etc.) from IMDb."""

    nconst: str  # "nm1234567"
    name: str
    known_for: list[str] = Field(default_factory=list)  # list of tconst IDs
    # Disambiguation hints lifted from the find-page result and shown in the
    # picker so same-named people can be told apart. Raw IMDb text; either may
    # be empty.
    professions: str = ""  # e.g. "Actor · Writer · Director"
    known_for_title: str = ""  # e.g. "Money Heist (2017–2021)"


class FilmographyRole(BaseModel):
    """One entry in a person's filmography."""

    tconst: str
    title: str
    year: Optional[str] = None  # e.g. "2024" or "2017–2021"
    title_type: str = ""  # "tvSeries", "movie", "tvEpisode", etc.
    job: str = ""  # "actor", "director", etc.
    character: str = ""
    episodes: int = 0
    status: str = ""   # "Pre-production", "Completed", "Released", ...


class Filmography(BaseModel):
    """Complete filmography for a person."""

    nconst: str
    name: str
    roles: list[FilmographyRole] = Field(default_factory=list)
    scraped: datetime = Field(default_factory=datetime.utcnow)


class SearchResult(BaseModel):
    """A single result from a title or person search."""

    tconst: str = ""  # for title searches
    nconst: str = ""  # for person searches
    title: str = ""
    name: str = ""
    year: Optional[int] = None
    types: list[str] = Field(default_factory=list)
    genres: list[str] = Field(default_factory=list)
