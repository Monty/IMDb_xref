# Changelog

## [Unreleased] — 2025-07-16

### Added

- **Playwright-based IMDb scraper** (`scraper/` directory)
  - `search-title` — search IMDb for show/movie titles; returns tconst, title, year, type
  - `search-person` — search IMDb for people; returns nconst, name
  - `full-credits` — scrape full cast & crew for any title; includes episode counts per actor
  - `title-basics` — grab basic title metadata without full cast
  - `filmography` — scrape a person's complete filmography with roles, characters, episode counts
  - `cast-rankings` — list cast sorted by episode count (descending)
  - `list-cache` / `clear-cache` — manage local cache
- **File-based JSON cache** (`.xref_cache/`) — one file per tconst/nconst, human-readable
- **Browser cookie persistence** — AWS WAF challenge cookies saved between runs
- **AWS WAF challenge handling** — headless Chromium resolves IMDb's JavaScript bot check automatically
- **Rate limiting** — configurable 1.5s default delay between page navigations

### Changed

- Replaced `.gz` database file dependency with Playwright web scraping

### Removed

- `name.basics.tsv.gz` symlink
- `title.basics.tsv.gz` symlink
- `title.episode.tsv.gz` symlink
- `title.principals.tsv.gz` symlink

## [Unreleased] — Phase 2: Index Layer

### Added

- **JSONL index files** (`.xref_index/`)
  - `titles.jsonl` — one line per title: tconst, title, year, types, genres
  - `persons.jsonl` — one line per person: nconst, name
  - `cast-by-person.jsonl` — one line per (person, show) pairing with role details
  - `cast-by-show.jsonl` — same data sorted by show then person
- **`scraper/index.py`** — build and query functions:
  - `rebuild_index()` — aggregates all cached JSON into flat JSONL index
  - `search_index()` — case-insensitive substring search across any index file
  - `get_cast_for_show()` — all cast/crew for a given tconst
  - `get_shows_for_person()` — all shows for a given nconst
  - `find_common_cast()` — people who appear in all given shows
  - `get_title_info()` / `get_person_info()` — lookup by ID
  - `index_stats()` — report on index file sizes
- **New CLI commands** (no browser needed — instant):
  - `rebuild-index` — rebuild index from cache
  - `index-stats` — show index file line counts
  - `query <term>` — search any index file by substring
  - `cast-for-show <tconst>` — get cast for a show, with `--actors-only`, `--min-episodes`, `--limit`
  - `shows-for-person <nconst>` — get shows for a person
  - `common-cast <tconst>...` — find shared cast between two or more shows
  - `title-info <tconst>` / `person-info <nconst>` — lookup by ID
  - `list-titles` / `list-persons-index` — list all indexed entries
- **Cast deduplication** — same person in same show is collapsed to one entry, preferring "actor" job
- **Job filtering** — `rebuild-index` reads `rg_jobs.rgx` and only indexes jobs listed there (actor, actress, cinematographer, director, editor, producer, writer). Edit `rg_jobs.rgx` to add/remove jobs.
