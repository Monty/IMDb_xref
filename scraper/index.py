"""Build and query flat JSONL index files from cached JSON data.

Index files live in .xref_index/:
  titles.jsonl         — one line per title (tconst, title, year, types)
  persons.jsonl        — one line per person (nconst, name)
  cast-by-person.jsonl — one line per (person, show) pairing with role details
  cast-by-show.jsonl   — same data, sorted by show then person
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Optional

from models import CastMember

CACHE_DIR = Path(__file__).resolve().parent.parent / ".xref_cache"
INDEX_DIR = Path(__file__).resolve().parent.parent / ".xref_index"
JOBS_FILE = Path(__file__).resolve().parent.parent / "rg_jobs.rgx"


def _ensure_index_dir() -> None:
    INDEX_DIR.mkdir(parents=True, exist_ok=True)


def _load_allowed_jobs() -> set[str]:
    """Load allowed job names from rg_jobs.rgx.

    Each non-empty, non-comment line is a job name. Returns a set of lowercase job names.
    """
    if not JOBS_FILE.exists():
        return set()
    lines = JOBS_FILE.read_text(encoding="utf-8").strip().split("\n")
    jobs = set()
    for line in lines:
        line = line.strip()
        if line and not line.startswith("#"):
            jobs.add(line.lower())
    # Normalize: treat "actress" and "actor" as the same
    if "actress" in jobs:
        jobs.add("actor")
    if "actor" in jobs:
        jobs.add("actress")
    return jobs


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def rebuild_index() -> dict[str, int]:
    """Read all cached JSON files and produce flat JSONL index files.

    Returns a dict of {filename: line_count} for each index file built.
    """
    _ensure_index_dir()

    allowed_jobs = _load_allowed_jobs()

    titles: dict[str, dict] = {}  # tconst -> {title, year, types, ...}
    persons: dict[str, dict] = {}  # nconst -> {name}
    cast_rows: list[dict] = []

    # Process all cached title files
    for path in sorted(CACHE_DIR.glob("tt*.json")):
        with open(path, encoding="utf-8") as f:
            show = json.load(f)

        tconst = show["tconst"]
        title = show.get("title", "")
        titles[tconst] = {
            "tconst": tconst,
            "title": title,
            "year": show.get("year"),
            "types": show.get("types", []),
            "genres": show.get("genres", []),
        }

        # Process cast members — deduplicate by (nconst, tconst),
        # preferring "actor" job and highest episode count
        seen: dict[tuple[str, str], dict] = {}
        for member in show.get("cast", []):
            nconst = member.get("nconst", "")
            name = member.get("name", "")
            job = member.get("job", "").lower()
            if not nconst or not name:
                continue

            # Skip jobs not in rg_jobs.rgx
            if allowed_jobs and job not in allowed_jobs:
                continue

            persons[nconst] = {"nconst": nconst, "name": name}

            row = {
                "nconst": nconst,
                "name": name,
                "tconst": tconst,
                "title": title,
                "job": job,
                "character": member.get("character", ""),
                "episodes": member.get("episodes", 0),
                "rank": member.get("rank", 0),
            }
            key = (nconst, tconst)
            if key not in seen:
                seen[key] = row
            else:
                existing = seen[key]
                # Prefer "actor" job
                if row["job"] == "actor" and existing["job"] != "actor":
                    seen[key] = row
                # Merge characters if both have them
                elif row["character"] and existing["character"] and row["character"] != existing["character"]:
                    existing["character"] = existing["character"] + "; " + row["character"]

        cast_rows.extend(seen.values())

    # Also gather persons from cached filmography files
    for path in sorted(CACHE_DIR.glob("nm*.json")):
        with open(path, encoding="utf-8") as f:
            fg = json.load(f)
        nconst = fg.get("nconst", "")
        name = fg.get("name", "")
        if nconst and name and nconst not in persons:
            persons[nconst] = {"nconst": nconst, "name": name}

    # Write titles.jsonl
    titles_path = INDEX_DIR / "titles.jsonl"
    titles_path.write_text(
        "\n".join(json.dumps(t, ensure_ascii=False) for t in sorted(titles.values(), key=lambda x: x["title"])) + ("\n" if titles else ""),
        encoding="utf-8",
    )

    # Write persons.jsonl
    persons_path = INDEX_DIR / "persons.jsonl"
    persons_path.write_text(
        "\n".join(json.dumps(p, ensure_ascii=False) for p in sorted(persons.values(), key=lambda x: x["name"])) + ("\n" if persons else ""),
        encoding="utf-8",
    )

    # Write cast-by-person.jsonl (sorted by person name, then title)
    cbp_path = INDEX_DIR / "cast-by-person.jsonl"
    cast_by_person = sorted(cast_rows, key=lambda r: (r["name"].lower(), r["title"].lower(), r["rank"]))
    cbp_path.write_text(
        "\n".join(json.dumps(r, ensure_ascii=False) for r in cast_by_person) + ("\n" if cast_by_person else ""),
        encoding="utf-8",
    )

    # Write cast-by-show.jsonl (sorted by title, then person name)
    cbs_path = INDEX_DIR / "cast-by-show.jsonl"
    cast_by_show = sorted(cast_rows, key=lambda r: (r["title"].lower(), r["name"].lower(), r["rank"]))
    cbs_path.write_text(
        "\n".join(json.dumps(r, ensure_ascii=False) for r in cast_by_show) + ("\n" if cast_by_show else ""),
        encoding="utf-8",
    )

    return {
        "titles.jsonl": len(titles),
        "persons.jsonl": len(persons),
        "cast-by-person.jsonl": len(cast_by_person),
        "cast-by-show.jsonl": len(cast_by_show),
    }


# ---------------------------------------------------------------------------
# Query
# ---------------------------------------------------------------------------

def _read_jsonl(name: str) -> list[dict]:
    """Read a JSONL index file into a list of dicts."""
    path = INDEX_DIR / name
    if not path.exists():
        return []
    lines = [l for l in path.read_text(encoding="utf-8").strip().split("\n") if l]
    return [json.loads(l) for l in lines]


def search_index(query: str, index_file: str) -> list[dict]:
    """Case-insensitive substring search across string fields in an index file."""
    q = query.lower()
    results = []
    for row in _read_jsonl(index_file):
        for val in row.values():
            if isinstance(val, str) and q in val.lower():
                results.append(row)
                break
    return results


def get_cast_for_show(tconst: str) -> list[dict]:
    """Get all cast/crew for a specific tconst from the index."""
    return [r for r in _read_jsonl("cast-by-show.jsonl") if r["tconst"] == tconst]


def get_shows_for_person(nconst: str) -> list[dict]:
    """Get all shows a specific person appears in from the index."""
    return [r for r in _read_jsonl("cast-by-person.jsonl") if r["nconst"] == nconst]


def find_common_cast(tconsts: list[str]) -> list[dict]:
    """Find cast/crew members who appear in all given shows.

    Returns list of {nconst, name, job, shows: [{title, character, episodes}]}
    """
    if len(tconsts) < 2:
        return []

    # Build: nconst -> {name, job, shows: {tconst: {title, character, episodes}}}
    from collections import defaultdict
    person_shows: dict[str, dict] = {}

    for row in _read_jsonl("cast-by-person.jsonl"):
        if row["tconst"] not in tconsts:
            continue
        nconst = row["nconst"]
        if nconst not in person_shows:
            person_shows[nconst] = {
                "nconst": nconst,
                "name": row["name"],
                "shows": {},
            }
        person_shows[nconst]["shows"][row["tconst"]] = {
            "title": row["title"],
            "tconst": row["tconst"],
            "job": row["job"],
            "character": row["character"],
            "episodes": row["episodes"],
        }

    # Filter to persons in ALL given shows
    results = []
    for nconst, data in person_shows.items():
        if len(data["shows"]) >= len(tconsts):
            results.append({
                "nconst": nconst,
                "name": data["name"],
                "shows": sorted(data["shows"].values(), key=lambda s: s["title"]),
            })

    return sorted(results, key=lambda r: r["name"].lower())


def get_title_info(tconst: str) -> Optional[dict]:
    """Look up a title by tconst from the index."""
    for row in _read_jsonl("titles.jsonl"):
        if row["tconst"] == tconst:
            return row
    return None


def get_person_info(nconst: str) -> Optional[dict]:
    """Look up a person by nconst from the index."""
    for row in _read_jsonl("persons.jsonl"):
        if row["nconst"] == nconst:
            return row
    return None


def list_titles() -> list[dict]:
    """Return all indexed titles."""
    return _read_jsonl("titles.jsonl")


def list_persons() -> list[dict]:
    """Return all indexed persons."""
    return _read_jsonl("persons.jsonl")


def index_stats() -> dict:
    """Return stats about the index."""
    if not INDEX_DIR.exists():
        return {"exists": False}
    stats = {"exists": True}
    for name in ["titles.jsonl", "persons.jsonl", "cast-by-person.jsonl", "cast-by-show.jsonl"]:
        path = INDEX_DIR / name
        if path.exists():
            lines = [l for l in path.read_text(encoding="utf-8").strip().split("\n") if l]
            stats[name] = len(lines)
        else:
            stats[name] = 0
    return stats
