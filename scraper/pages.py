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
    Filters out tvEpisode and podcastEpisode results.
    """
    manager = get_manager()
    page = manager.goto(f"https://www.imdb.com/find/?q={query}&s=tt&exact=true")

    results: list[SearchResult] = []
    items = page.query_selector_all("li.ipc-metadata-list-summary-item")

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

        # IMDb's find rows concatenate the inline metadata with no separators
        # in inner_text, so the year runs straight into the runtime ("19921h
        # 39m", "20064h"). A trailing \b then fails whenever a runtime follows,
        # which is why feature films and video games came back n/a while rows
        # whose year is followed by "-" or a newline (episodes, podcasts) or
        # sits in the title resolved. Anchor on a non-digit lookbehind and drop
        # the trailing boundary so the year is claimed regardless of what abuts
        # it.
        year = None
        year_m = re.search(r"(?<!\d)(19\d{2}|20\d{2})", full_text)
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
            # Podcast rows must be matched before the loose "Video" key below:
            # a title like "Tiempos de Videoclub" contains "Video", which would
            # otherwise mis-tag a podcast episode as a video and let it through
            # the skip filter.
            "Podcast Series": "podcastSeries",
            "Podcast Episode": "podcastEpisode",
            "Short": "tvShort",
            "Video Game": "videoGame",
            "Video": "video",
            "Documentary": "documentary",
            "Feature Film": "movie",
            "Movie": "movie",
        }
        types = []
        for display_name, canonical in type_map.items():
            if display_name in full_text:
                types.append(canonical)
                break

        results.append(
            SearchResult(
                tconst=tconst,
                title=title,
                year=year,
                types=types,
            )
        )

    page.close()

    # Filter out low-interest types — episodes and shorts
    skip_types = {"tvEpisode", "podcastEpisode", "podcastSeries", "tvShort"}
    results = [r for r in results if not r.types or not (r.types[0] in skip_types)]

    return results


# ---------------------------------------------------------------------------
# Person search
# ---------------------------------------------------------------------------


def search_person(query: str, limit: int = 25) -> list[Person]:
    """Search IMDb for people matching *query*."""
    manager = get_manager()
    page = manager.goto(f"https://www.imdb.com/find/?q={query}&s=nm&exact=true")

    results: list[Person] = []
    items = page.query_selector_all("li.ipc-metadata-list-summary-item")

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

        # The result also shows a raw profession line ("Actor · Writer ·
        # Director") and a "known for" title carrying a year ("Money Heist
        # (2017–2021)"). Both help disambiguate same-named people in the
        # picker, and neither is always present. Tell them apart by the
        # year-in-parens: the known-for line has one, professions don't.
        professions = ""
        known_for_title = ""
        for line in item.inner_text().split("\n"):
            line = line.strip()
            if not line or line == name:
                continue
            if re.search(r"\(\d{4}", line):
                if not known_for_title:
                    known_for_title = line
            elif not professions:
                professions = line

        results.append(
            Person(
                nconst=nconst,
                name=name,
                professions=professions,
                known_for_title=known_for_title,
            )
        )

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

        members.append(
            CastMember(
                nconst=nconst,
                name=name,
                job=job,
                character=character,
                episodes=episodes,
                rank=rank,
            )
        )

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
    # Check Mini-Series first (before Series, since "Mini Series" contains "Series")
    if "TV Mini Series" in page_title or "TV Mini-Series" in page_title:
        types.append("tvMiniSeries")
    elif "TV Series" in page_title:
        types.append("tvSeries")
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

    # Original title is in a div with class "baseAlt" right after h1:
    # <div class="... baseAlt">Original title: La casa de papel</div>
    original_title = ""
    orig_el = page.query_selector("div.baseAlt")
    if orig_el:
        orig_text = orig_el.inner_text().strip()
        m = re.match(r"Original title:\s*(.+)", orig_text)
        if m:
            original_title = m.group(1).strip()

    year = None
    subtitle = page.query_selector("h2")
    if subtitle:
        ym = re.search(r"\b(19\d{2}|20\d{2})\b", subtitle.inner_text())
        if ym:
            year = int(ym.group())

    # Types and year fallback from page title:
    # "Berlin and the Jewels of Paris (TV Mini Series 2023) - IMDb"
    # "Money Heist (TV Series 2017–2021) - Full cast & crew - IMDb"
    types = []
    page_title = page.title()

    # Check Mini-Series first (before Series, since "Mini Series" contains "Series")
    if "TV Mini Series" in page_title or "TV Mini-Series" in page_title:
        types.append("tvMiniSeries")
    elif "TV Series" in page_title:
        types.append("tvSeries")
    elif "TV Movie" in page_title:
        types.append("tvMovie")
    elif "Movie" in page_title or "Feature Film" in page_title:
        types.append("movie")
    else:
        # No TV type found — default to movie
        types.append("movie")

    # Extract year from page title if not found in subtitle
    if year is None:
        ym = re.search(r"\b(19\d{2}|20\d{2})\b", page_title)
        if ym:
            year = int(ym.group())

    genres = []
    genre_els = page.query_selector_all('[data-testid="genres"] a')
    if genre_els:
        genres = [e.inner_text().strip() for e in genre_els]

    page.close()

    return Show(
        tconst=tconst,
        title=title,
        original_title=original_title,
        year=year,
        types=types,
        genres=genres,
    )


# ---------------------------------------------------------------------------
# Filmography for a person
# ---------------------------------------------------------------------------

ROW_SEL = "li.ipc-metadata-list-summary-item"

# Headings inside the credits area that are not job categories.
SKIP_HEADINGS = {"sponsored", "awards", "trivia", "biography", "photos", "videos"}

# Production status is only kept if models.py has been given the matching
# field, so this patch can be applied to pages.py before or after that one:
#     status: str = ""   # "Pre-production", "Completed", ...
# Without it the status is dropped rather than silently overwriting the
# title type, which is what the previous version did.
_SUPPORTS_STATUS = "status" in FilmographyRole.model_fields

_EXTRACT_JS = r"""
(sec) => {
  const ROW = 'li.ipc-metadata-list-summary-item';
  const STATUS = ['development unknown', 'in development', 'pre-production',
                  'post-production', 'announced', 'filming', 'completed',
                  'released', 'unknown'];
  const TYPES = ['tv series', 'tv mini series', 'tv mini-series', 'tv movie',
                 'tv special', 'tv short', 'tv episode', 'tv pilot', 'movie',
                 'short', 'video', 'video game', 'podcast series',
                 'podcast episode', 'documentary', 'music video'];
  const YEAR = /^\d{4}(\s*[\u2013\u2014-]\s*(\d{4})?)?$/;

  const norm = (s) => (s || '').replace(/\s+/g, ' ').trim();
  const isStatus = (t) => STATUS.indexOf(t.toLowerCase()) !== -1;
  const isType = (t) => TYPES.indexOf(t.toLowerCase()) !== -1;

  const out = [];
  let job = '';

  for (const el of sec.querySelectorAll('h4, ' + ROW)) {
    if (el.tagName === 'H4') {
      job = norm(el.innerText.split('\n')[0]).toLowerCase();
      continue;
    }
    if (!job) continue;

    const link = el.querySelector('a.ipc-metadata-list-summary-item__t')
              || el.querySelector('a[href*="/title/tt"]');
    if (!link) continue;
    const m = (link.getAttribute('href') || '').match(/tt\d{7,9}/);
    if (!m) continue;

    const tc = el.querySelector('.ipc-metadata-list-summary-item__tc');

    let year = null;
    let episodes = 0;
    let titleType = '';
    let status = '';
    const credits = [];

    // Claim a fragment as year / episode count / production status.
    // Returns true if it was consumed, so callers know not to treat it
    // as a credit.
    const takeMeta = (t) => {
      if (/episode/i.test(t)) {
        const e = t.match(/[\d,]+/);
        if (e) episodes = parseInt(e[0].replace(/,/g, ''), 10);
        return true;
      }
      if (YEAR.test(t)) { year = t.replace(/\s+/g, ''); return true; }
      if (isStatus(t)) { status = t; return true; }
      if (isType(t)) { titleType = t; return true; }
      return false;
    };

    // Trailing metadata column: year and episode count.
    el.querySelectorAll('.ipc-metadata-list-summary-item__cc li.ipc-inline-list__item')
      .forEach((li) => { takeMeta(norm(li.innerText)); });

    const tagged = el.querySelectorAll(
      '[data-testid="credit-roles-list"] li.ipc-inline-list__item');

    if (tagged.length) {
      tagged.forEach((li) => {
        const t = norm(li.innerText);
        if (t && credits.indexOf(t) === -1) credits.push(t);
      });
    } else if (tc) {
      // Unreleased layout: credits are plain <span> items, status is an <a>.
      tc.querySelectorAll('ul li.ipc-inline-list__item').forEach((li) => {
        const t = norm(li.innerText);
        if (!t || takeMeta(t)) return;
        if (li.querySelector('a')) return;
        if (credits.indexOf(t) === -1) credits.push(t);
      });
    }

    if (tc) {
      // Type, year and status can each appear in a list of their own,
      // alongside or instead of the tagged credit list.
      tc.querySelectorAll('ul li.ipc-inline-list__item').forEach((li) => {
        if (li.closest('[data-testid="credit-roles-list"]')) return;
        takeMeta(norm(li.innerText));
      });
      // IMDb moves the type marker around depending on whether the row
      // carries a rating, so match on value rather than position: sweep
      // every leaf node and let takeMeta claim what it recognises.
      tc.querySelectorAll('span, a, li').forEach((e) => {
        if (e.children.length) return;
        if (e === link) return;
        if (e.closest('.ipc-rating-star-group')) return;
        takeMeta(norm(e.innerText));
      });
    }

    out.push({
      tconst: m[0],
      title: norm(link.innerText),
      year: year,
      title_type: titleType,
      status: status,
      job: job,
      character: credits.join('; '),
      episodes: episodes,
    });
  }
  return out;
}
"""


def _scrape_rows(nconst: str) -> tuple[str, list[dict]]:
    """Fetch the page and return (name, raw row dicts) before model coercion."""
    manager = get_manager()
    page = manager.goto(f"https://www.imdb.com/name/{nconst}/fullcredits")

    name = ""
    name_el = page.query_selector("h1")
    if name_el:
        name = name_el.inner_text().strip().splitlines()[0].strip()

    # The credits section is the leaf <section> holding the rows; outer
    # sections wrap it and would double-count.
    section = None
    for sec in page.query_selector_all("section"):
        if sec.query_selector_all("section"):
            continue
        if sec.query_selector_all(ROW_SEL):
            section = sec
            break

    raw: list[dict] = section.evaluate(_EXTRACT_JS) if section is not None else []
    page.close()
    return name, raw


def get_filmography(nconst: str) -> Filmography:
    """Scrape a person's full credits page to build their filmography.

    Every category (Actor, Writer, Director, Soundtrack, Producer, Editorial
    Department, Voice Actor - Dubbing, Thanks, Self, Archive Footage, ...)
    sits inside a single <section>, separated only by <h4> headings, so
    section membership is positional and headings must be walked with rows.
    """
    name, raw = _scrape_rows(nconst)

    roles: list[FilmographyRole] = []
    for item in raw:
        if item["job"] in SKIP_HEADINGS:
            continue
        fields = {
            "tconst": item["tconst"],
            "title": item["title"],
            "year": item["year"],
            "title_type": item["title_type"],
            "job": item["job"],
            "character": item["character"],
            "episodes": item["episodes"],
        }
        if _SUPPORTS_STATUS:
            fields["status"] = item["status"]
        roles.append(FilmographyRole(**fields))

    # Deduplicate by (tconst, job): merge credits, keep the highest episode count.
    deduped: dict[tuple[str, str], FilmographyRole] = {}
    for role in roles:
        key = (role.tconst, role.job)
        existing = deduped.get(key)
        if existing is None:
            deduped[key] = role
            continue
        if role.character:
            merged = list(dict.fromkeys(
                [c.strip() for c in existing.character.split(";") if c.strip()]
                + [c.strip() for c in role.character.split(";") if c.strip()]
            ))
            if merged:
                existing.character = "; ".join(merged)
        if role.episodes > existing.episodes:
            existing.episodes = role.episodes
        if not existing.year and role.year:
            existing.year = role.year
        if not existing.title_type and role.title_type:
            existing.title_type = role.title_type
        if _SUPPORTS_STATUS and not existing.status and role.status:
            existing.status = role.status

    return Filmography(nconst=nconst, name=name, roles=list(deduped.values()))
