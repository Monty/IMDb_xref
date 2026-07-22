# Changelog

## [Unreleased] — 2026-07-18

### Added

- **`augment_tconstFiles.sh`** — Persistent `.xref_cache/augmented` cache for consolidated title lookups across all `.tconst` files. Batch-processes cached vs. uncached tconsts using `comm` and `rg -f` for speed.
- **`augment_tconstFiles.sh`** — `.xlate` file integration: uses column 1→column 2 mappings to show English/Netflix titles as primary and foreign/IMDb titles as original.
- **`scraper/pages.py`** — `get_title_basics` now captures Original Title from IMDb title pages (`div.baseAlt`).

### Bugfixes

- **`generateXrefData.sh`** — `.xref_durations` file was not recorded and `.xref_history` was not saved after runs. Restored `SECONDS=0` tracking, `saveDurations`, `trimDurations`, `saveHistory`, and `trimHistory` calls from the original `.gz` script.
- **`generateXrefData.sh`** — Fixed operator precedence in `processDurations` early-exit check: `A || B && exit` evaluated as `A || (B && exit)`. Wrapped in parens: `(A || B) && exit`.
- **`findCastOf.sh`** — `saveHistory` was not called before the favorites prompt, so search results were never saved to `.xref_history`. Restored the original `printHistory` + `diff` + `saveHistory` pattern.
- **`augment_tconstFiles.sh`** — Loop variables (`title`, `orig_title`, `year`, `types`) were not reset between iterations, causing all entries to show the first tconst's data.
- **`augment_tconstFiles.sh`** — Unindexed tconsts were silently skipped; now fetches `title-basics` from IMDb automatically.
- **`augment_tconstFiles.sh`** — Original Title column was never populated; now captured from IMDb and supplemented by `.xlate` files.
- **`scraper/pages.py`** — "TV Mini Series" (with space) was not recognized as a type — only "TV Mini-Series" (with hyphen) matched. Now handles both.
- **`scraper/pages.py`** — `get_title_basics` had no fallback for year when h2 subtitle didn't contain one; now extracts from page title.
- **`scraper/pages.py`** — Movies without "Movie" in page title had empty type; now defaults to "movie" when no TV type found.
- **`scraper/cli.py`** — `title-basics` command didn't save to cache; now saves like `full-credits`.
- **`scraper/index.py`** — `titles.jsonl` didn't include `original_title` field.
- **`findCastOf.sh`**, **`findOtherShows.sh`**, **`generateXrefData.sh`** — Checked `title-info` to decide whether to scrape full credits, but `title-basics` populates the index without cast data. Now also checks `cast-for-show` before skipping.
- **`saveFilmography.sh`** — `jq` error ("Cannot index string with string 'job'") when grouping filmography roles by job — `.job` was `null` in some roles. Now uses `.roles[].job // empty` to filter out null jobs.

### Changed

- **`augment_tconstFiles.sh`** — Rewritten to use `.xref_cache/augmented` for fast lookups. Xlate transformations applied at display time, stored in cache for consolidated reference.
- **`iQuery.sh`** — Added search term management: dynamic action menu with remove/delete terms, full vs duplicates-only search, "List all shows", duplicate detection, and running search from within the loop without exiting. Fixed menu index bounds when "Keep typing" option shifts array offset. Fixed `_incremental_search` capturing menu display output in result variable — redirected display to stderr so only JSON is captured. Fixed "List all shows" to extract titles and use `$PAGER` with `-l` flag. Fixed `q` not quitting in main menu. Added `-l` pager support to search results.
- **`scraper/index.py`** — `rebuild_index` now generates `characters.jsonl` with unique character entries (character name, actor, show, episodes). Filters to actor jobs only, excludes parenthetical credits.
- **`iQuery.sh`** — Added "Add a character to search for" category. Searches `characters.jsonl` for unique character names (deduplicated), adds the character name as a search term passed to `xrefCast.sh`, which returns all actors who portrayed it across shows. Updated help text to match current string-based search behavior.
- **`saveFilmography.sh`** — Generates GitHub-flavored `.md` file alongside `.json`. Groups roles by job (actor, director, etc.), consolidates multiple characters per title, links to IMDb, filters noise (self, special thanks, title type misparse, crew roles in character field). Strips IMDb disambiguation suffixes like "(I)" from filenames. Uses filmography name for accurate file naming.
- **`scraper/pages.py`** — Filmography scraper missed "TV Mini Series" (with space, not hyphen), "Short", "Completed" as title types, causing them to be captured as character names. Now handled.
- **`scraper/index.py`** — Merged `cast-by-person.jsonl` and `cast-by-show.jsonl` into single `cast.jsonl` (same data, different sort). Saved ~592K.
- **`findCastOf.sh`**, **`findOtherShows.sh`**, **`findShowsWith.sh`** — Added `-l` flag to pipe results through `${PAGER:-less}`.

---

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

### Bugfixes

- **`findCastOf.sh`** — Fixed `tsvPrint` receiving piped data instead of filename in disambiguation menu. Removed redundant TSV cache file creation (scraper `.json` cache is the single source of truth). Added scraper error validation — shows clear message if Playwright/chromium is not installed.
- **`findOtherShows.sh`** — Fixed `printf "---\t..."` where `---` was interpreted as an option flag. Fixed `tsvPrint` piped data issue.
- **`findShowsWith.sh`** — Fixed `tsvPrint` piped data issue. Fixed `jq` error ("Cannot index number with string 'episodes'") when `.episodes` was `null` — use `// 0` default and `\(. )` interpolation instead of re-indexing `.episodes` inside the conditional.
- **`saveFilmography.sh`** — Fixed `tsvPrint` piped data issue.
- **`iQuery.sh`** — Fixed `tsvPrint` piped data issue.
- **`ensurePrerequisites.function`** — Fixed Playwright chromium browser detection to work on both macOS (`~/Library/Caches/`) and Linux (`~/.cache/`). Loops through `chromium-*/` directories for robustness.
- **`generateXrefData.sh`**, **`augment_tconstFiles.sh`** — Updated help examples from `Contrib/OPB.tconst` (doesn't exist) to `Contrib/Acorn.tconst`.

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
