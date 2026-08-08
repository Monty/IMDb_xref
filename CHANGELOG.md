# Changelog

## [Unreleased] — 2026-07-27

### Changed

- **`findCastOf.sh`** — Cast is now read from the local IMDb `.gz` datasets instead of a live IMDb fetch. `FULLCAST` is now only a display cap (`maxCast`); the fetch path it used to drive is retired (see Removed). Each show's principals are shown in IMDb billing order — the `ordering` field from `title.principals.tsv.gz` — displayed as Name|Job|Show|Role and capped at `maxCast`. This matches the order the scraper-based `IMDb_xref` (Claude branch) shows, so side-by-side comparisons line up.
- **`findCastOf.sh`** — De-duplicate the billing-order list. The `.gz` cache holds one row per episode-appearance, so a person recurred once per episode (e.g. a series lead ×38). The display now folds identical Name|Job|Show|Role rows to a single row while preserving billing order, and intentionally leaves character-name variants (`Simon Magellan` / `SimonMagellan`) and a person's distinct roles as separate rows.

### Removed

- **`findCastOf.sh`** — The `FULLCAST` live-fetch block: a `curl` of `…/fullcredits` parsed by `getFullcredits.awk`. IMDb now returns `403` to a bot User-Agent and, past that, an AWS WAF `challenge` (HTTP 202, empty body) to a browser User-Agent; the current fullcredits page is also React-rendered, so `getFullcredits.awk` — which keys on the old `id="cast"` / `href="/name/"` markup — parsed nothing and wrote header-only cache files that then masked the real `.gz` data. `getFullcredits.awk` is now unused.

### Notes

- Delete any header-only cache files left by the old fetch path so they repopulate from the `.gz` data, e.g. `rm .xref_cache/tt32868688 .xref_cache/tt1548331`.
- This branch is a data-frozen UX/flow comparison baseline for `IMDb_xref`; it is only run against titles already present in the `.gz` datasets.
