"""Scrape IMDb pages for show titles, cast, and filmography data."""

from __future__ import annotations

import json
import re
from typing import Optional

from playwright.sync_api import Page

from browser import close_manager, get_manager
from models import (
    CastMember,
    Filmography,
    FilmographyRole,
    Person,
    SearchResult,
    Show,
)


# ---------------------------------------------------------------------------
# Title search
# ---------------------------------------------------------------------------

def search_title(query: str, limit: int = 25) -> list[SearchResult]:
    """Search IMDb for titles matching *query*.

    Returns a list of SearchResult, each with tconst, title, year, types.
    """
    manager = get_manager()
    page = manager.goto(f"https://www.imdb.com/find/?q={query}&sattytt")

    results: list[SearchResult] = []
    items = page.query_selector_all('li.ipc-metadata-list-summary-item')

    for item in items[:limit]:
        # tconst from the first link href="/title/tt1234567/..."
        link_el = item.query_selector("a[href*='/title/tt']")
        if not link_el:
            continue
        href = link_el.get_attribute("href") or ""
        m = re.search(r"tt\d{7,8}", href)
        if not m:
            continue
        tconst = m.group()

        # Title from h4
        title = ""
        h4 = item.query_selector("h4")
        if h4:
            title = h4.inner_text().strip()

        # Year and type from the full text of the item
        full_text = item.inner_text()

        year = None
        year_m = re.search(r"\b(19\d{2}|20\d{2})\b", full_text)
        if year_m:
            year = int(year_m.group())

        # Types — match common IMDb type strings
        type_map = {
            "TV Series": "tvSeries",
            "TV Mini-Series": "tvMiniSeries",
            "TV Movie": "tvMovie",
            "TV Special": "tvSpecial",
            "TV Pilot": "tvPilot",
            "TV Short": "tvShort",
            "TV Episode": "tvEpisode",
            "Video Game": "videoGame",
            "Video": "video",
            "Documentary": "documentary",
            "Feature Film": "movie",
        }
        types = []
        for display_name, canonical in type_map.items():
            if display_name in full_text:
                types.append(canonical)
                break

        results.append(SearchResult(
            tconst=tconst,
            title=title,
            year=year,
            types=types,
        ))

    page.close()
    return results


# ---------------------------------------------------------------------------
# Person search
# ---------------------------------------------------------------------------

def search_person(query: str, limit: int = 25) -> list[Person]:
    """Search IMDb for people matching *query*."""
    manager = get_manager()
    page = manager.goto(f"https://www.imdb.com/find/?q={query}&sact")

    results: list[Person] = []
    items = page.query_selector_all('li.ipc-metadata-list-summary-item')

    for item in items[:limit]:
        link_el = item.query_selector("a[href*='/name/nm']")
        if not link_el:
            continue
        href = link_el.get_attribute("href") or ""
        m = re.search(r"nm\d{7,8}", href)
        if not m:
            continue
        nconst = m.group()

        h4 = item.query_selector("h4")
        name = h4.inner_text().strip() if h4 else ""

        results.append(Person(nconst=nconst, name=name))

        if len(results) >= limit:
            break

    page.close()
    return results


# ---------------------------------------------------------------------------
# Full credits for a title
# ---------------------------------------------------------------------------

def _extract_int(text: str) -> int:
    """Pull the first integer from a string, defaulting to 0."""
    if not text:
        return 0
    m = re.search(r"\d+", text)
    return int(m.group()) if m else 0


def _parse_cast_section(
    section: "playwright.sync_api.ElementHandle",
    job: str,
) -> list[CastMember]:
    """Parse one category section (Cast, Directors, Writers, …).

    The current IMDb fullcredits format (2025) uses:
        section > li.ipc-metadata-list-summary-item
    where each item's inner_text is like:
        "Úrsula Corberó\nTokio\n41 episodes • 2017–2021"
    """
    members: list[CastMember] = []
    rank = 0

    rows = section.query_selector_all("li.ipc-metadata-list-summary-item")
    if not rows:
        return members

    for row in rows:
        # nconst from the first /name/nm... link
        name_link = row.query_selector('a[href*="/name/nm"]')
        if not name_link:
            continue
        href = name_link.get_attribute("href") or ""
        nm = re.search(r"nm\d{7,8}", href)
        if not nm:
            continue
        nconst = nm.group()

        # Parse from full text: "Name\nCharacter\n41 episodes • 2017–2021"
        full_text = row.inner_text()
        lines = [l.strip() for l in full_text.split("\n") if l.strip()]

        # First non-empty line is the name
        name = lines[0] if len(lines) >= 1 else ""

        # Remaining lines: character + episode info
        character = ""
        episodes = 0
        for line in lines[1:]:
            ep_m = re.search(r"(\d+)\s+episode", line)
            if ep_m:
                episodes = int(ep_m.group(1))
            elif not re.search(r"episode|\d{4}", line):
                # Not an episode count or year line — it's the character name
                if not character:
                    character = line
                else:
                    character = character + "; " + line

        if job == "actor" and episodes > 0:
            rank += 1
        elif job != "actor":
            rank += 1

        members.append(CastMember(
            nconst=nconst,
            name=name,
            job=job,
            character=character,
            episodes=episodes,
            rank=rank,
        ))

    return members


def get_full_credits(tconst: str) -> Show:
    """Scrape the fullcredits page for a title.

    Returns a Show populated with cast, directors, writers, producers.
    """
    manager = get_manager()
    page = manager.goto(f"https://www.imdb.com/title/{tconst}/fullcredits")

    # Grab title info — h1 on fullcredits is "Full cast & crew", so use:
    # h2 for the title, page title for year/types
    title = ""
    subtitle = page.query_selector("h2")
    if subtitle:
        title = subtitle.inner_text().strip()

    # Year and types from page title:
    # "Money Heist (TV Series 2017–2021) - Full cast & crew - IMDb"
    year = None
    types = []
    page_title = page.title()
    ym = re.search(r"\b(19\d{2}|20\d{2})\b", page_title)
    if ym:
        year = int(ym.group())
    if "TV Series" in page_title:
        types.append("tvSeries")
    elif "TV Mini-Series" in page_title:
        types.append("tvMiniSeries")
    elif "TV Movie" in page_title:
        types.append("tvMovie")
    elif "Movie" in page_title or "Feature Film" in page_title:
        types.append("movie")

    all_cast: list[CastMember] = []

    heading_to_job = {
        "directors": "director",
        "writers": "writer",
        "cast": "actor",
        "producers": "producer",
        "cinematographers": "cinematographer",
        "editors": "editor",
        "composers": "composer",
    }

    # All sections on the page
    sections = page.query_selector_all("section")

    for section in sections:
        heading = section.query_selector("h3")
        if not heading:
            continue
        heading_text = heading.inner_text().strip().lower()

        # Skip wrapper sections that contain nested <section> elements —
        # the first section on IMDb fullcredits wraps all 900+ items under
        # a single "Directors" heading, misclassifying everyone.
        nested = section.query_selector_all("section")
        if nested:
            continue

        job = None
        for key, val in heading_to_job.items():
            if key in heading_text:
                job = val
                break
        if job is None:
            continue

        members = _parse_cast_section(section, job)
        all_cast.extend(members)

    page.close()

    return Show(
        tconst=tconst,
        title=title,
        original_title="",
        year=year,
        types=types,
        cast=all_cast,
    )


# ---------------------------------------------------------------------------
# Title basics (no cast — just metadata)
# ---------------------------------------------------------------------------

def get_title_basics(tconst: str) -> Show:
    """Scrape just the title page for basic metadata, no cast."""
    manager = get_manager()
    page = manager.goto(f"https://www.imdb.com/title/{tconst}/")

    title = ""
    title_el = page.query_selector("h1")
    if title_el:
        title = title_el.inner_text().strip()

    year = None
    subtitle = page.query_selector("h2")
    if subtitle:
        ym = re.search(r"\b(19\d{2}|20\d{2})\b", subtitle.inner_text())
        if ym:
            year = int(ym.group())

    genres = []
    genre_els = page.query_selector_all('[data-testid="genres"] a')
    if genre_els:
        genres = [e.inner_text().strip() for e in genre_els]

    page.close()

    return Show(tconst=tconst, title=title, year=year, genres=genres)


# ---------------------------------------------------------------------------
# Filmography for a person
# ---------------------------------------------------------------------------

def get_filmography(nconst: str) -> Filmography:
    """Scrape a person's full credits page to build their filmography.

    The filmography page has sections with h4 headings like "Actress", "Actor",
    each containing li.ipc-metadata-list-summary-item rows. Each row's text is
    like: "The Day of the Jackal\n8.1\nTV Series\nNuria\n2024\n10 episodes"
    """
    manager = get_manager()
    page = manager.goto(f"https://www.imdb.com/name/{nconst}/fullcredits")

    # Person name from the page heading
    name = ""
    name_el = page.query_selector("h1")
    if name_el:
        name = name_el.inner_text().strip()

    roles: list[FilmographyRole] = []

    # All sections on the page
    sections = page.query_selector_all("section")

    for section in sections:
        # Job heading is in h4, not h3
        heading = section.query_selector("h4")
        if not heading:
            continue
        job = heading.inner_text().strip().lower()

        # Skip non-filmography sections
        if job in ("sponsored", "awards", "trivia", "biography"):
            continue

        rows = section.query_selector_all("li.ipc-metadata-list-summary-item")
        for row in rows:
            link = row.query_selector('a[href*="/title/tt"]')
            if not link:
                continue
            href = link.get_attribute("href") or ""
            tm = re.search(r"tt\d{7,8}", href)
            if not tm:
                continue
            tconst = tm.group()

            # Parse from full text:
            # "The Day of the Jackal\n8.1\nTV Series\nNuria\n2024\n10 episodes"
            full_text = row.inner_text()
            lines = [l.strip() for l in full_text.split("\n") if l.strip()]

            # First line is the title
            title = lines[0] if len(lines) >= 1 else ""

            year = None
            character = ""
            episodes = 0
            title_type = ""

            for line in lines[1:]:
                ym = re.search(r"^\b(19\d{2}|20\d{2})\b$", line)
                if ym:
                    year = int(ym.group())
                elif re.search(r"episode", line, re.IGNORECASE):
                    ep_m = re.search(r"(\d+)", line)
                    if ep_m:
                        episodes = int(ep_m.group(1))
                elif line in ("TV Series", "TV Mini-Series", "TV Movie",
                              "TV Episode", "Movie", "Documentary",
                              "TV Special", "TV Pilot"):
                    title_type = line
                elif not re.search(r"^\d", line):
                    # Not a number — likely character name
                    if not character:
                        character = line

            roles.append(FilmographyRole(
                tconst=tconst,
                title=title,
                year=year,
                title_type=title_type,
                job=job,
                character=character,
                episodes=episodes,
            ))

    page.close()

    return Filmography(nconst=nconst, name=name, roles=roles)

    page.close()

    return Filmography(nconst=nconst, name=name, roles=roles)
