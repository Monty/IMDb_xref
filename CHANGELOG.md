# Changelog

## [Unreleased] — 2026-08-11

### Changed

- **Branch-specific state files** — All `.xref_*` files and directories are now `.xref_bulk_*` on this branch (`.xref_live_*` on `live-fetch`): `.xref_cache` → `.xref_bulk_cache`, `.xref_history` → `.xref_bulk_history`, `.xref_durations` → `.xref_bulk_durations`, `.xref_numRecords` → `.xref_bulk_numRecords`. Both branches previously shared these names in a working directory that survives `git checkout`, because they are gitignored. The caches use the same tconst filenames for incompatible formats (TSV here, JSON there), so after a switch `xrefCast.sh`, `iQuery.sh`, and `findOtherShows.sh` parsed live-fetch's JSON as TSV and emitted garbage — `xrefCast.sh` printed raw JSON fragments as cast rows, and `findOtherShows.sh` matched nconsts inside JSON. Worse, this branch's `downloadIMDbFiles.sh` does an unconditional `rm -rf "$cacheDirectory"` as part of its ordinary refresh workflow, and `cleanupEverything.sh` globbed a bare `.xref_*` — either would silently destroy live-fetch's scraped cache, which costs hours and WAF exposure to rebuild where this branch's regenerates from local `.gz` in seconds. Distinct prefixes make that structurally impossible rather than merely unlikely, and make `ls -a .xref*` unambiguous about which branch's state is present. `downloadIMDbFiles.sh` needed no change: its `rm -rf` now resolves to this branch's cache only. Both `cleanupEverything.sh` globs were narrowed to `.xref_bulk_*`; a bare glob would have defeated the whole point. Everything else on this branch already went through the `define_files` variables. Migration is a rename: `mv .xref_cache .xref_bulk_cache` and so on. `.gitignore` needed no change, as `.xref*` still covers both prefixes.

- **`functions/saveHistory.function`**, **`functions/trimHistory.function`** — Drop the `.sh` extension from history filenames (`240620.112822-generateXrefData.sh` → `240620.112822-generateXrefData`). These are data files, and the extension made them turn up in searches for shell scripts. Both functions had to change together: `trimHistory` globs `*-"$appendName"`, so stripping in only one place would have left the trim silently matching nothing and history growing without bound. Callers that pass an explicit `appendName` (`$favoritesFile`) are unaffected. Same change applied to the `live-fetch` branch, where these two functions are identical.

## [Unreleased] — 2026-08-10

### Fixed

- **`findOtherShows.sh`** — Stop writing a header row into each show's cache file. This branch labels columns inline in the output line (e.g. `(Name|Job|Show|Rank|Role|Link)`); the header-row convention belongs to `live-fetch` only. Because `findCastOf.sh` displays a cached show's file directly, the header was read back as data and printed as a phantom cast member (`Person | Job | Show Title | Character Name`) at the top of the billing-order list, where it also consumed one of the `head -"$maxCast"` slots. The cast write changed from `>>` to `>` in the same edit — the removed `printf` was what truncated the file, so an append would otherwise have doubled cache contents on every rerun. `xrefCast.sh` was unaffected (it already stripped the header explicitly, and that strip is left in place for caches written before this fix); `findOtherShows.sh`'s own nconst extraction was unaffected (`cut -f 7 | rg "^nm"` never matched the header). Cache files written before this fix keep their stale header until the show is re-cached by rerunning `findOtherShows.sh` on it, or the file is deleted.

- **`README.md`** — Dropped Linux/Windows Compatibility claims per Monty — macOS only now. Screenshots left as-is pending a refresh with newer example shows. Added a **Branches** section: this repo never mentioned the `live-fetch` sibling exists, how to switch to it, or the offline/principal-cast-only/re-download-for-freshness tradeoff that defines `bulk-download`. Clone instructions now include `git checkout bulk-download` directly rather than mentioning the switch only in later prose. Fixed "top 50 cast & crew members": this is the `FULLCAST` env var, defaulting to 20 (`start.command`'s `${FULLCAST:-20}` fallback), not a fixed number — corrected all four occurrences to the actual default of 20 and added a note that it's configurable (`export FULLCAST=N`, or `0` for no cap). (First pass wrongly assumed "50" was correct because it matched Monty's own `~/.zshenv` export, which isn't representative of a fresh clone.) Added a note under "Run sample queries" explaining that `findCastOf.sh` and `xrefCast.sh` treat `FULLCAST` differently: `findCastOf.sh` applies it as a display cap (unset = no cap), while in `xrefCast.sh` it is a *data-source switch* — it searches `.xref_cache/tt*` instead of `Credits-Person.csv`, and is gated on the cache being non-empty, so in a fresh clone it is silently ignored. (An earlier draft of this note wrongly described both scripts as applying a simple cap.)

## [Unreleased] — 2026-08-07

### Changed

- **`findOtherShows.sh`** — Cast is now built from the local `.gz` datasets instead of a live fetch. Each show's cache is joined from `title.principals.tsv.gz` (ordering, nconst, category, characters) and `name.basics.tsv.gz` (nconst → name) into the same 8-column format the cross-show lookup already reads (Person, Show Title, Episode Title, Rank, Job, Character Name, nconst ID, tconst ID), so nothing downstream changed. Per the chosen scope, the cross-reference still runs against *cached* shows only (`.xref_cache/tt*`), not the whole `.gz`. Cast rows are labeled `actor` uniformly (matching the retired `getFullcredits.awk`, which hard-coded it) so the downstream `rg actor` cross-show filter keeps actresses; the join uses a `FILENAME`-keyed awk over real temp files, so a missing name can never blank the whole cache.

### Removed

- **`findShowsWith.sh`**, **`saveFilmography.sh`** — The `FULLCAST` live-fetch block (curl the person's `fullcredits` page, parse with `getFilmography.awk`) that overwrote the local `title.principals.tsv.gz` filmography as a debug detour. It's the same dead React/WAF path retired in `findCastOf.sh`; the `.gz` read these scripts already do is now the only source, and `getFilmography.awk` is unused by them.

- **`findOtherShows.sh`** — The `curl` + `getFullcredits.awk` fetch that had been its only cast source. `getFullcredits.awk` is now unused anywhere in the branch.

### Notes

- **Cross-show coupling.** `findOtherShows.sh` finds a person in another show by matching their nconst *inside that show's cache file*, so it only sees shows cached in the 8-column format — in practice, shows cached by `findOtherShows.sh` itself. `findCastOf.sh` writes a 6-column, name-only cache with no nconst IDs, so a show cached only by `findCastOf.sh` contributes nothing to the cross-reference. Run `findOtherShows.sh` on the shows you want in the corpus. Making `findCastOf.sh` also emit the 8-column cache would unify them if that ever becomes worthwhile.

---

## [Unreleased] — 2026-07-27

### Changed

- **`findCastOf.sh`** — Cast is now read from the local IMDb `.gz` datasets instead of a live IMDb fetch. `FULLCAST` is now only a display cap (`maxCast`); the fetch path it used to drive is retired (see Removed). Each show's principals are shown in IMDb billing order — the `ordering` field from `title.principals.tsv.gz` — displayed as Name|Job|Show|Role and capped at `maxCast`. This matches the order the scraper-based `IMDb_xref` (Claude branch) shows, so side-by-side comparisons line up.
- **`findCastOf.sh`** — De-duplicate the billing-order list. The `.gz` cache holds one row per episode-appearance, so a person recurred once per episode (e.g. a series lead ×38). The display now folds identical Name|Job|Show|Role rows to a single row while preserving billing order, and intentionally leaves character-name variants (`Simon Magellan` / `SimonMagellan`) and a person's distinct roles as separate rows.

### Removed

- **`findCastOf.sh`** — The `FULLCAST` live-fetch block: a `curl` of `…/fullcredits` parsed by `getFullcredits.awk`. IMDb now returns `403` to a bot User-Agent and, past that, an AWS WAF `challenge` (HTTP 202, empty body) to a browser User-Agent; the current fullcredits page is also React-rendered, so `getFullcredits.awk` — which keys on the old `id="cast"` / `href="/name/"` markup — parsed nothing and wrote header-only cache files that then masked the real `.gz` data. `getFullcredits.awk` is now unused.

### Notes

- Delete any header-only cache files left by the old fetch path so they repopulate from the `.gz` data, e.g. `rm .xref_cache/tt32868688 .xref_cache/tt1548331`.
- This branch is a data-frozen UX/flow comparison baseline for `IMDb_xref`; it is only run against titles already present in the `.gz` datasets.
