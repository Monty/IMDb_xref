# Changelog

## [Unreleased] — 2026-08-10

### Fixed

- **`README.md`** — Dropped Linux/Windows Compatibility claims per Monty — macOS only now. Screenshots left as-is pending a refresh with newer example shows. Added a **Branches** section: this repo never mentioned the `live-fetch` sibling exists, how to switch to it, or the offline/principal-cast-only/re-download-for-freshness tradeoff that defines `bulk-download`. Clone instructions now include `git checkout bulk-download` directly rather than mentioning the switch only in later prose. Fixed "top 50 cast & crew members": this is the `FULLCAST` env var, defaulting to 20 (`start.command`'s `${FULLCAST:-20}` fallback), not a fixed number — corrected all four occurrences to the actual default of 20 and added a note that it's configurable (`export FULLCAST=N`, or `0` for no cap). (First pass wrongly assumed "50" was correct because it matched Monty's own `~/.zshenv` export, which isn't representative of a fresh clone.) Added a note under "Run sample queries" that `findCastOf.sh`/`xrefCast.sh` run directly (bypassing `start.command`) don't get the 20 default at all — unset `FULLCAST` shows every principal cast & crew member with no cap.

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
