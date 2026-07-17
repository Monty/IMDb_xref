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
