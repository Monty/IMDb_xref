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
- **Fixed** wrapper section bug on fullcredits pages where nested `<section>` elements caused 900+ entries to be misclassified as "director"

## [Unreleased] — Phase 4: Shell Script Migration

### Changed

- **`findCastOf.sh`** — Rewritten to use scraper. Searches IMDb, shows disambiguation menu, displays cast with episode counts. New `-e NNN` flag filters by minimum episodes.
- **`findShowsWith.sh`** — Rewritten to use scraper. Searches IMDb for persons, displays filmography grouped by job.
- **`findOtherShows.sh`** — Rewritten to use scraper. Finds cast members from a show who appear in other cached shows, with episode counts. New `-e` flag for minimum episodes in source show.
- **`xrefCast.sh`** — Rewritten to use scraper index. Searches index instead of CSV files. Falls back to file-based search with `-f` flag for backward compatibility.
- **`iQuery.sh`** — Rewritten to use scraper index. Incremental search over titles and persons from the index.
- **`generateXrefData.sh`** — Simplified. Reads `.tconst` files, scrapes full credits for each, rebuilds index. No more .gz processing.
- **`augment_tconstFiles.sh`** — Uses scraper `title-info` for metadata. New `-f` flag fetches missing titles from IMDb.
- **`start.command`** — Removed `FULLCAST` variable. Updated menu text to reflect episode counts.
- **`functions/ensurePrerequisites.function`** — Checks for `rg`, `jq`, `uv`, scraper `.venv`, and Playwright browsers instead of .gz files.
- **`functions/define_files`** — Removed .gz file references.

### Removed

- `downloadIMDbFiles.sh` → moved to `.legacy/`
- `printIMDbFileHeaders.sh` → moved to `.legacy/`
- `countIMDbInstances.sh` → moved to `.legacy/`
- `listIMDbInstances.sh` → moved to `.legacy/`

### Added

- `.xref_cache/` directory — contains JSON cache files for titles and persons (gitignored)
- `.xref_index/` directory — contains JSONL index files (gitignored)
- `rg_jobs.rgx` — list of job categories to index (one per line; currently: actor, actress, cinematographer, director, editor, producer, writer)
- **Non-acting filter** — scraper index filters out entries in the Cast section that are actually crew positions (casting director, assistant director, sound mixer, etc.)

### Changed

- **`saveFilmography.sh`** — Rewritten to use scraper. Saves JSON filmographies to `secondary/filmographies/`.
- **`functions/ensurePrerequisites.function`** — Checks for `rg`, `jq`, `uv`, `playwright`, Playwright chromium browser, and scraper `.venv`.
- **`functions/define_files`** — Removed .gz file references.

### Moved

- Obsolete .gz-dependent scripts (`downloadIMDbFiles.sh`, `printIMDbFileHeaders.sh`, `countIMDbInstances.sh`, `listIMDbInstances.sh`) → `hidden/` directory
