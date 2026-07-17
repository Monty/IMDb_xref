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
- **JSONL index files** (`.xref_index/`)
  - `titles.jsonl` — one line per title: tconst, title, year, types, genres
  - `persons.jsonl` — one line per person: nconst, name
  - `cast-by-person.jsonl` — one line per (person, show) pairing with role details
  - `cast-by-show.jsonl` — same data sorted by show then person
- **Index CLI commands** (no browser needed — instant):
  - `rebuild-index` — rebuild index from cache
  - `index-stats` — show index file line counts
  - `query <term>` — search any index file by substring
  - `cast-for-show <tconst>` — get cast with `--actors-only`, `--min-episodes`, `--limit`
  - `shows-for-person <nconst>` — get shows for a person
  - `common-cast <tconst>...` — find shared cast between two or more shows
  - `title-info <tconst>` / `person-info <nconst>` — lookup by ID
  - `list-titles` / `list-persons-index` — list all indexed entries
- **File-based JSON cache** (`.xref_cache/`) — one file per tconst/nconst, human-readable
- **Browser cookie persistence** — AWS WAF challenge cookies saved between runs
- **AWS WAF challenge handling** — headless Chromium resolves IMDb's JavaScript bot check automatically
- **Rate limiting** — configurable 1.5s default delay between page navigations
- **Cast deduplication** — same person in same show collapsed to one entry, preferring "actor" job
- **Job filtering** — `rebuild-index` reads `rg_jobs.rgx` and only indexes jobs listed there
- **Non-acting filter** — index filters out Cast section entries that are actually crew positions (casting director, assistant director, sound mixer, etc.)

### Changed

- **`findCastOf.sh`** — Rewritten to use scraper. Searches IMDb, disambiguation menu, cast with episode counts. New `-e NNN` flag filters by minimum episodes.
- **`findShowsWith.sh`** — Rewritten to use scraper. Searches IMDb for persons, filmography grouped by job.
- **`findOtherShows.sh`** — Rewritten to use scraper. Finds cast from a show who appear in other cached shows. New `-e` flag for minimum episodes in source show.
- **`xrefCast.sh`** — Rewritten to use scraper index. Falls back to file-based search with `-f` flag.
- **`iQuery.sh`** — Rewritten to use scraper index. Incremental search over titles and persons.
- **`saveFilmography.sh`** — Rewritten to use scraper. Saves JSON to `secondary/filmographies/`.
- **`generateXrefData.sh`** — Simplified. Reads `.tconst` files, scrapes full credits for each, rebuilds index.
- **`augment_tconstFiles.sh`** — Uses scraper `title-info` for metadata. New `-f` flag fetches missing titles.
- **`start.command`** — Removed `FULLCAST` variable. Updated menu text for episode counts.
- **`functions/ensurePrerequisites.function`** — Checks for rg, jq, uv, playwright, chromium browser, scraper .venv.
- **`functions/define_files`** — Removed .gz file references.
- **`README.md`** — Rewritten for scraper-based approach.
- **`tests/test-pickOptions.sh`** — Removed stale comment.
- **`functions/NOTES.md`** — Fixed path typo.
- All Python files formatted with `ruff`.
- Replaced `.gz` database file dependency with Playwright web scraping

### Removed

- `name.basics.tsv.gz`, `title.basics.tsv.gz`, `title.episode.tsv.gz`, `title.principals.tsv.gz` symlinks

### Moved

- `downloadIMDbFiles.sh`, `printIMDbFileHeaders.sh`, `countIMDbInstances.sh`, `listIMDbInstances.sh` → `hidden/`
