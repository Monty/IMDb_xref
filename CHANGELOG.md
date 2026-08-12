# Changelog

## [Unreleased] — 2026-08-11

### Added

- **`functions/tsvPrint.function`**, **`xrefCast.sh`** — Highlight matched search terms in results, restoring the coloring `big_IMDb_xref` has. `xrefCast.sh` called `tsvPrint -n` (no highlighting) at both display points, so results printed entirely plain. The existing `-c` mode highlights one fixed column, which is the wrong shape here: a search term lands in the Character Name column for "Princess Diana" but the Person column for "Olivia Colman". Added `tsvPrint -p PATTERNS_FILE`, which highlights caller-supplied terms wherever they appear, and pointed both call sites at `$SEARCH_TERMS`. `-p` uses `rg --passthru` so non-matching lines survive — without it the column-header rows this branch adds would be silently filtered out, which is why `big_IMDb_xref` shows no headers in its colored output.

### Changed

- **`functions/saveHistory.function`**, **`functions/trimHistory.function`** — Drop the `.sh` extension from history filenames (`240620.112822-generateXrefData.sh` → `240620.112822-generateXrefData`). These are data files, and the extension made them turn up in searches for shell scripts. Both functions had to change together: `trimHistory` globs `*-"$appendName"`, so stripping in only one place would have left the trim silently matching nothing and history growing without bound. Callers that pass an explicit `appendName` (`$favoritesFile`) are unaffected.

- **`xrefCast.sh`** — The `-f SEARCH_FILE` branch no longer passes `--color always` when selecting matching rows. It was embedding ANSI escapes into the data *before* `sort` and before the table was rendered, so the invisible bytes threw off `xsv`'s column-width calculation and would have defeated the new `-F` literal matching in `tsvPrint -p`. The `rg` call still filters rows as before; coloring now happens once, at display time, for both the index and file paths.

### Fixed

- **`findCastOf.sh`**, **`findOtherShows.sh`**, **`findShowsWith.sh`**, **`saveFilmography.sh`**, **`functions/reportSearchError.function`** — Stop searching after the first WAF CAPTCHA. Each script's search loop reported the failure and then `continue`d to the next term, but a CAPTCHA blocks every subsequent request too — so `./findCastOf.sh -d "The Night Manager" "The Crown"` printed the identical four-line error twice before giving up, and a longer term list would repeat it once per term while continuing to hit IMDb (which is itself part of what escalates a silent challenge into a CAPTCHA). Added `isWAFChallenge` alongside `reportSearchError`, sharing the marker list with it so detection and wording stay in step, and used it in all four loops to `break` with a short "Skipping any remaining search terms." note. `generateXrefData.sh`'s equivalent check now calls the shared predicate instead of its own inline `rg`.

- **`demo.command`**, **`Contrib/demo_cache/`** — Ship the demo's example shows with the repo and seed `.xref_cache` from them at startup, instead of relying on data the user may not have. Every question in the demo queries the local index, which is built from `.xref_cache`; in a fresh clone that is empty, so the demo answered "I didn't find any matching records" five times and looked broken. Scraping the shows live at demo time was rejected as the fix: it is slow, and a new user has no cookies in `~/.config/IMDb_xref/browser_state.json` — precisely the state in which IMDb's WAF is most likely to serve a CAPTCHA, which would land in the first thirty seconds of someone's first run. The committed cache files make the demo offline, instant, and identical for everyone. `Contrib/` was chosen because `cleanupEverything.sh` deletes `.xref_*` but does not touch `Contrib/`, so the demo still works after a full cleanup. Seeding never overwrites an existing cache entry, so a user who has already scraped these shows keeps their fresher copy, and `rebuild-index` runs only if something was actually copied.

- **`generateXrefData.sh`** — Stop discarding scraper stderr. The fetch loop ran `full-credits ... 2>/dev/null` and tested only whether the result was non-empty, so any failure — above all a WAF CAPTCHA, which `browser.py` raises as `WAFChallengeError` precisely so it can't be mistaken for an empty result — was swallowed: the loop continued, `fetched` stayed at 0, and the script printed a cheerful `==> Done.` before rebuilding an empty index. A blocked scrape was therefore indistinguishable from an unseeded repo or a genuine no-results run, and the only visible symptom appeared much later as `xrefCast.sh`/`demo.command` reporting "I didn't find any matching records". Now: stderr is captured to a tempfile, the result is validated as JSON, and failures are reported through `reportSearchError` (the same handler `findCastOf.sh` already used), which recognizes a WAF challenge and points at `scraper/tools/solve_challenge.py`. Errors print even under `-q`, since silence is the bug. A CAPTCHA additionally breaks out of the loop rather than continuing — every later fetch would fail too, and repeated automated hits are part of what escalates a silent challenge into a CAPTCHA (per `waf_check.py`). Added a `Failed:` line to the summary, suppressed the "Ready to query" sign-off when anything failed, and made the script exit non-zero in that case so a caller (e.g. a demo seeding step) can distinguish a partial scrape from a clean one.
- **`generateXrefData.sh`** — `processDurations` now takes an optional exit status (`processDurations 1`) and passes it to both its `exit` calls. It previously always exited 0 from inside the function, which would have made the new failure path's `exit 1` unreachable dead code.

## [Unreleased] — 2026-08-10

### Changed

- **`README.md`** — Compatibility section dropped Linux/Windows claims per Monty — macOS only now. Added a **Branches** section: this repo never mentioned the `bulk-download` sibling exists, how to switch to it, or the offline/principal-cast-only/re-download-for-freshness tradeoff on that branch. Clone instructions now include `git checkout live-fetch` directly (not just mentioned later in prose), and picked up the Xcode command-line-tools pop-up note that only `big_IMDb_xref`'s README had — not branch-specific, applies here too. `-h` help text across `findCastOf.sh`, `findOtherShows.sh`, `findShowsWith.sh`, `saveFilmography.sh`, `xrefCast.sh`, `iQuery.sh`, and `generateXrefData.sh` audited against `big_IMDb_xref`'s for cross-branch contamination; none found — each already describes only its own branch's mechanism.

## [Unreleased] — 2026-08-09

### Bugfixes

- **`scraper/pages.py` (`search_title`)** — Resolve the missing year (`n/a`) on feature-film and video-game title-search results. IMDb's find rows concatenate the inline metadata in `inner_text` with no separators, so the year abuts the runtime (`19921h 39m`, `20064h`); the extractor's trailing `\b` then failed whenever a digit-leading runtime followed — so exactly the rows carrying a runtime (movies, games) lost their year, while episode/podcast rows (year followed by `–` or a newline) and title-embedded years happened to survive. Changed `\b(19\d{2}|20\d{2})\b` to `(?<!\d)(19\d{2}|20\d{2})` (non-digit lookbehind, no trailing boundary). Diagnosed and verified against the five live `Reservoir Dogs` rows via `probe_find_year.py` + an offline `verify_find_year.py` regex check in the `Systems/Claude/IMDb/` scratch dir.

- **`scraper/pages.py` (`search_title`)** — Filter podcast results out of title search. IMDb podcast rows (`Podcast Episode`, `Podcast Series`) weren't in `type_map`, so they were never tagged and the `skip_types` filter never dropped them — a podcast episode surfaced as a pickable "show". Worse, a podcast whose title contains "Video" (e.g. "Tiempos de Videoclub") was mis-tagged `video` by the loose substring match and shown as a video. Added both podcast keys — positioned before the `Video`/`Video Game` keys so they win the first-match, since the substring test also scans the title — and added `podcastSeries` to `skip_types`. Verified against the live `Reservoir Dogs` rows via `verify_podcast_filter.py`.

- **`scraper/cli.py` (`cmd_query`)** — Sort cast results by prominence (most episodes, then best billing) before applying `--limit`, so a capped query keeps the billed principals instead of whoever sorts first alphabetically. With `FULLCAST=50` set, `xrefCast` was returning each show's first 50 cast *by name*, which dropped leads like Olivia Colman and made `-d` cross-referencing miss obvious overlaps. Only affects rows carrying a `rank` field (`cast.jsonl`).

### Changed

- **`findCastOf.sh`** — Show `n/a` instead of `0 episodes` in the cast listing for titles with no episode counts (movies, where every member is 0). Both jq blocks (actors-only and full cast) now emit `\(if .episodes > 0 then "\(.episodes) episodes" else "n/a" end)`; series output is unchanged.

- **`findCastOf.sh`, `findShowsWith.sh`, `findOtherShows.sh`** — Add a column-header row to the cast/show listings and drop the now-redundant `(Name|Job|…)` column descriptions from the `==>` lines, mirroring the header `findOtherShows.sh` already carried. `findCastOf` gains a `Person  Job  Character Name  Episodes` header (both `-a` and full-cast paths); `findShowsWith` gains a `Show Title  Episodes  Character Name  Link` header, and its last column is now `imdb.com/title/<tconst>` to match `findOtherShows`' Link column (was a bare tconst); `findOtherShows` drops its own `(Name|Job|Show|Episodes|Role|Link)` description now that the header labels the columns. Each header is prepended into the `tsvPrint` file so it inherits the column alignment.

- **`findCastOf.sh`, `findShowsWith.sh`, `findOtherShows.sh`** — Tidy the confirm-gate spacing. Drop the search-echo's trailing blank so exactly one blank line — the confirm's own leading `\n` — precedes `These are the results I can process:` (was two). In `findShowsWith`, also drop the dedicated blank after `Does that look correct?` and gate the `==> I found …` separator on a `firstGroup` flag, so the first job group sits flush against the prompt (matching the other two scripts) while later groups keep their separating blank.

- **`findCastOf.sh`** — Add a `Link` column (`imdb.com/name/<nconst>`) to the cast/crew listing, matching the Link columns now in `findShowsWith.sh` and `findOtherShows.sh`. Both blocks (`-a` and full cast) gain it; the per-row link falls back to empty for any member without an nconst.

- **`saveFilmography.sh`** — Drop the search-echo's trailing blank after the term list, matching the confirm-gate spacing fix applied to the other three search scripts (its per-term confirm already owns the single blank before `These are the results`).

- **`xrefCast.sh`** — Better cross-reference (`-d`) output. Restrict it to credited acting roles — drop crew (non-actor jobs) and `(uncredited)` parts, which overlap coincidentally and bury the recognizable cast. Order the cross-show list by prominence (each person by their most-episodes / best-billed role, rows grouped) instead of alphabetically, so the leads lead; `episodes`/`rank` are now carried through the query to drive that ordering. Also dropped the search-echo's trailing blank for confirm-gate spacing consistency with the other scripts, and replaced the `(Name|Job|Show|Role)` descriptions on both listing headers with a `Person / Job / Show Title / Character Name` header row.

---

## [Unreleased] — 2026-08-08

### Bugfixes

- **Person picker** (`findShowsWith.sh`, `saveFilmography.sh`, and the scraper) — Show profession and "known for" columns in the name-match menu so same-named people can be told apart; `$XR` previously showed only `nconst` + name, unlike `$XRM`. `search_person` now lifts the raw profession line (e.g. `Sound Department · Writer · Editorial Department`) and the known-for title (e.g. `Money Heist (2017–2021)`) out of each find-page result — told apart by the year-in-parens, either may be absent — into new `Person.professions` / `Person.known_for_title` fields, and both pickers display them. Professions are shown raw (not normalized to `rg_jobs.rgx`), since the verbose labels disambiguate best. Near-name matches like `Pedro C. Alonso` are intentionally kept.

- **`findOtherShows.sh`** — Fix the `ShowsWithActorsFrom-*.csv` layout to match `big_IMDb_xref`: add the header row, anchor each person on the searched show (their source-show row first, linked to the person via `imdb.com/name/<nconst>`, then their other shows linked to each title), and drop the stray blank line. The `.csv` and the on-screen listing are now built from one table so they always agree.

### Changed

- **`findOtherShows.sh`** — Group the three per-person result writes (source-show row, other-show rows, `---` separator) under a single `{ …; } >>"$RESULTS"` redirect instead of three individual appends (SC2129). No behavior change.

- **`saveFilmography.sh`** — Enrich the per-term `Does that look correct?` confirm line to match the picker: it now shows `nconst  name  professions  known_for` instead of just `imdb.com/name/<nconst>  name`. The single-match path captures `professions`/`known_for_title` from `searchResults`, the multi-match menu's `tabbedOptions` is widened to the same four fields (captured on selection), and both are reset per term so the nconst-ID path — where `person-info` carries neither — confirms with those two columns blank. Mirrors the enrichment already in `findShowsWith.sh`. (`saveFilmography.sh` confirms per-term from a scratch file, not from `PERSON_RESULTS`, which stays write-only/vestigial here.)

---

## [Unreleased] — 2026-08-07

### Added

- **`findCastOf.sh`** — A `Does that look correct? [Y/n]` confirmation before a resolved title is used, mirroring the gate in `big_IMDb_xref`. It fires on the two paths that resolve a tconst with no user interaction — a typed tconst ID (`tt…`) and a show name that matches exactly one title — printing the resolved `imdb.com/title/<tconst>  <type>  <title>  <original-title>  <year>` line, so a mistyped ID that silently lands on the wrong show is caught before the cast is listed or saved to favorites. Answering "no" skips that term. The multi-match name path already confirms through its selection menu and is exempt (tracked via a per-term `needConfirm` flag). The prompt runs *after* the full-credits fetch, so a brand-new, un-indexed ID is fetched once before it can be rejected; anything already in the index confirms instantly. The `original-title` column comes from `title-info` and is blank when the scraper didn't capture one (e.g. Magellan), so it won't always match `big_IMDb_xref`'s bulk-dataset original title.

- **`findShowsWith.sh`** — Same gate in batch form: after all search terms resolve, it prints `These are the results I can process:` with the resolved people and asks `Does that look correct?` before listing their shows; "no" restarts. Mirrors the twin's confirmation in `big_IMDb_xref`.

- **`saveFilmography.sh`** — Same gate per-term: a person resolved from an nconst ID or a single name match is shown as `imdb.com/name/<nconst>  <name>` and confirmed before the filmography is fetched; "no" skips that person. The multi-match menu is exempt (it already confirmed via selection).

- **`findOtherShows.sh`** — Same per-term title confirmation as `findCastOf.sh` (ID and single-match paths; multi-match menu exempt), shown before the show enters the cross-reference set.

### Bugfixes

- **`findCastOf.sh`** — Reset `tconst` at the top of each search-term loop. A menu "Skip" broke out of the `select` without setting `tconst`, leaving the previous term's value in place; the following `[[ -z $tconst ]] && continue` guard then passed and processed a stale tconst. The per-term reset closes that.
- **`findOtherShows.sh`** — Same per-term `tconst` reset as `findCastOf.sh`, closing the identical stale-tconst-after-menu-`Skip` path.

---

## [Unreleased] — 2026-07-26

### Bugfixes

- **`saveFilmography.sh`** — A failed person search (e.g. a WAF challenge) was silently reported as "No matches found": the `search-person` call used `2>/dev/null` and ignored the exit code, so an empty result from a blocked fetch looked identical to a genuine no-match. It now captures stderr, checks the exit code, and on failure prints "Couldn't search IMDb" with the underlying error — the same masking fix applied to the other search scripts last week, which had reached this script's *filmography* fetch but not its *person-search*. Surfaced by running `saveFilmography.sh "Jacques Spiesser"` against a live WAF block, which reported "No matches" while `waf_check.py` confirmed the CAPTCHA was up.
- **`findCastOf.sh`** — The full-credits fetch failure message was misleading: any scrape failure printed "Scraper failed. Make sure Playwright is installed: playwright install chromium", a diagnosis left over from when that was the common failure. The common failure is now a WAF CAPTCHA, so the message sent you to reinstall Playwright when the actual fix is `solve_challenge.py`. It now routes through `reportSearchError`, which detects a WAF challenge and says so (with the correct remedy) or otherwise prints the specific error. Surfaced by `./findCastOf.sh tt32868688` reporting the Playwright message during a live WAF block.
- **`functions/reportSearchError.function`** — Generalized to also handle non-search failures: it now accepts an optional header template (defaulting to the search wording) and accepts the captured output as either a file path or a string, so the full-credits fetch path can reuse the same WAF-aware reporting.

### Added

- **`functions/reportSearchError.function`** — Shared helper for reporting a failed IMDb search, used by `findCastOf.sh`, `findShowsWith.sh`, `findOtherShows.sh`, and `saveFilmography.sh`. Replaces the duplicated `tail -n 2 ... sed` blocks, which dumped two raw traceback lines (including a stray `)` from the multi-line `raise` and a long URL). For a WAF challenge it now prints the same concise wording as `waf_check.py` ("IMDb is serving a WAF CAPTCHA. Run solve_challenge.py..."); for any other error it prints just the final, most-specific line. Consolidating into one function also means future wording changes happen in one place.

- **`findCastOf.sh`** — New `-a` (actors only) switch. Lists only acting roles (`actor`/`actress`), omitting crew such as directors and writers. Crew rows can carry long stacked "(as ...)" credit variants that wrap the terminal display, and actor is the predominant lookup (character names are more memorable than actor names, especially foreign ones). The header reads "Cast for" with `-a` and "Cast & crew for" without. Display-only: the cross-show duplicates check and favorites saving still operate on the full cast. The acting-role match (`^act(or|ress)$`) is hardcoded rather than read from `rg_jobs.rgx`, since that file is the general jobs whitelist, not an actors list, and "actors only" has a fixed meaning.
- **`scraper/tools/waf_check.py`** — Probe that forces a live IMDb fetch (via `goto` on an uncached title, The Shawshank Redemption) to detect a WAF CAPTCHA independent of the cache; a cached-title probe would report "clear" even while the WAF is up. Exits 0 (clear) / 1 (blocked) / 2 (error); `--quiet` for scripting. Run before an interactive session; if blocked, solve via `solve_challenge.py` and re-check.

### Notes

- Investigated the recurring WAF CAPTCHA on the interactive path. Evidence points to cold-session re-initialization as the trigger, not request volume or browser fingerprint: two long continuous batch runs (560 shows 7/19, full rebuild 7/26) sailed through hundreds of sequential fetches with no challenge, while single interactive lookups get challenged even 45 minutes after activity. A diagnostic (`scraper/tools/waf_experiment.py`) confirmed that real Chrome via `channel="chrome"` still gets challenged on a cold start, ruling out the cheap fingerprint fix. The durable fix would be a persistent-browser daemon keeping one warm session across commands — deferred, as the current workaround (run `waf_check.py`, solve if needed) is adequate for weekly interactive use.
- Known, not yet fixed: `findOtherShows.sh` (line ~198) fetches full-credits with `>/dev/null 2>&1` and never checks the result, so a WAF failure there fails *silently* — the show ends up with no cast and no explanation. Same class as the `findCastOf` misleading-message bug but the opposite symptom (silent vs. wrong). Fixing it means capturing and checking the result like `findCastOf` does, then routing through `reportSearchError`. Deferred.

---

## [Unreleased] — 2026-07-25

### Bugfixes

- **`augment_tconstFiles.sh`** — A failed title lookup silently dropped the tconst: `[[ -n $title ]] && printf ...` wrote nothing when the fetch returned empty. With a WAF challenge failing every uncached fetch, augmenting a 15-line file kept only the 3 already-cached entries and, in `-i` mode, overwrote the input — destroying the other 12. A failed lookup now falls back to the tconst's existing line from the input (the full row if the file carried one, otherwise the bare tconst), warns per line, and prints a summary pointing at `solve_challenge.py`. No line is ever dropped.
- **`augment_tconstFiles.sh`** — A tconst preserved after a failed fetch is no longer written to the `augmented` cache, so a title-less fallback entry can't poison it. Only complete (tab-bearing) rows are cached.
- **`augment_tconstFiles.sh`** — An option placed after the filename (`file -i`) was left in `"$@"` by `getopts` and treated as a filename, producing an obscure `basename: illegal option` error and pulling in unintended files. A guard after `getopts` now catches a leftover `-`-prefixed operand and prints a clear message ("Option '-i' must come before the filename(s). Put options first, or use -- to end option parsing."). Standard POSIX getopts parsing is unchanged; only the error is improved, and `--` still works as the escape hatch.

### Changed

- **`augment_tconstFiles.sh`** — When IMDb reports no separate original title (i.e. it equals the primary), the original-title column is now filled with the primary rather than left empty, matching the bulk-dataset convention the older files and the `_episode_count.csv` files use. Applied after any `.xlate` step, so foreign originals filled from an xlate file (e.g. `Money Heist` → `La casa de papel`) and genuinely different originals are preserved; only still-empty columns on English-language entries are filled. This stops re-augmenting from blanking that column on every English title, leaving real IMDb changes (e.g. type reclassifications) as the only diff.

### Notes

- Re-augmenting an existing file now surfaces genuine IMDb changes accumulated over time — e.g. titles reclassified from `short` or `tvSpecial` to `movie`. These are correct current data from IMDb, not scraper errors; the original-title fix above keeps them from being buried under spurious blank-original diffs.

---

## [Unreleased] — 2026-07-24

### Added

- **`scraper/browser.py`** — `WAFChallengeError`, raised by `goto()` when a navigation lands on an AWS WAF interstitial rather than real content. Checks `#challenge-container` and `#captcha-container`, then the page title, and runs after the `#root` wait so a silent JS challenge that clears itself is unaffected. Applies to every navigation, so `search_title` and `search_person` now fail loudly on a challenge too.
- **`saveFilmography.sh`** — Scraper stderr is captured to a `SCRAPER_ERR` temp file and reported when a fetch fails, showing the last two lines of the traceback. Registered in `terminate()` for cleanup alongside the other temp files.
- **`scraper/tools/solve_challenge.py`** — Opens IMDb in a non-headless browser sharing the scraper's `browser_state.json`, so a WAF CAPTCHA solved by hand carries over to subsequent headless runs. Reuses `browser._CHALLENGE_TITLES` so it stays in step with what `goto()` treats as a challenge. Run directly (`./scraper/tools/solve_challenge.py`).
- **`scraper/tools/probe_groups.py`** — Diagnostic that dumps the fullcredits heading/row layout in document order, for checking what changed when IMDb reshuffles the DOM and `get_filmography` starts misattributing jobs. Run directly (`./scraper/tools/probe_groups.py [nconst]`).
- Both tools use a PEP 723 `uv run --script` shebang (inline `playwright`/`pydantic` deps, no active venv needed) and resolve the scraper package via `Path(__file__).resolve().parents[1]`, so they work from any checkout. Mark executable with `chmod +x scraper/tools/*.py`.
- **`findShowsWith.sh`** — Job tables now include the show's tconst as a final column, so each row links to a unique IMDb title. `cast.jsonl` already carried the field; only the display jq needed it.
- **`findCastOf.sh`, `findShowsWith.sh`, `findOtherShows.sh`** — Each captures scraper stderr to a `SCRAPER_ERR` temp file (same pattern as `saveFilmography.sh`), registered in `terminate()` for cleanup.

### Bugfixes

- **`scraper/cache.py`** — `save_filmography` refuses to write a `Filmography` with no roles. An unsolved CAPTCHA was being cached as a valid empty result — `{"name": "Let's confirm you are human", "roles": []}` — and nothing distinguished that from a person with no credits, so the failure would have been served from cache indefinitely.
- **`saveFilmography.sh`** — A person whose fetch failed triggered three scrapes: the initial cache-miss fetch, a `--delay 1` warm-up call, and a re-read. Four names cost twelve requests in roughly fifteen seconds, which plausibly contributed to IMDb escalating from a silent challenge to a CAPTCHA. The retry block is removed — the scraper already serves from `.xref_cache` and scrapes on a miss, so one call suffices.
- **`saveFilmography.sh`** — Both scraper invocations discarded stderr, so `WAFChallengeError` was invisible and every failure surfaced as "No filmography found", conflating a failed scrape with a person who genuinely has no credits.
- **`saveFilmography.sh`** — The progress message used `$nconstName`, which is not assigned until after the role-count check, so failures reported a stale name — two different people both printed as "George Clooney". Uses the nconst instead.
- **`findCastOf.sh`, `findShowsWith.sh`, `findOtherShows.sh`** — A title/person search that failed (most often a WAF challenge) discarded stderr and produced empty output, which the scripts reported as "No matches found" — telling the user a show or person didn't exist when the scraper simply couldn't reach IMDb. Each now checks the scraper's exit status: a genuine empty result still says "No matches", but a failure prints the actual error (e.g. `WAFChallengeError`) and skips.
- **`tsvPrint.function`** — A highlight request on a column with empty cells built a pattern file containing blank lines; a blank line matches every row, so the whole table was highlighted. Blank (and duplicate) patterns are now dropped.
- **`tsvPrint.function`** — When the highlight column was empty or absent (e.g. the two-column `nconst\tname` results), the pattern file was empty and `rg -f` matched nothing, so the table printed as blank. It now falls back to printing the table unhighlighted.
- **`augment_tconstFiles.sh`** — The augmented-cache eviction anchored each tconst with `^` alone (`sed 's/^/^/'`), treating it as a prefix, so re-augmenting `tt123` would also drop `tt1234` and any other tconst sharing its leading digits. Now matches the exact first field (`^tconst` plus the trailing tab) via `awk`. Latent — IMDb assigns IDs sequentially and yours span 7–8 digits, so the collision grows more likely as the cache fills; no current entry was affected.

### Changed

- **`saveFilmography.sh`** — "No filmography found" now means only what it says: the scrape succeeded and returned no credits. Fetch failures are reported separately.
- **`saveFilmography.sh`** — `roleCount` defaults to `0` when `jq` receives empty input, rather than leaving an empty string to be coerced by the arithmetic test.
- **`findShowsWith.sh`** — Now a purely local (index) query. The two fallbacks that scraped a person's filmography and rebuilt the index on a cache miss are removed; a person not in the index yields a clear message pointing to `findCastOf.sh` (to add a show) or `saveFilmography.sh` (for a full filmography). Name search is kept — IMDb is still queried to resolve a name to candidate nconsts — but show data is read only from the index. Help text, comments, and menu wording updated to match; examples changed to people in the cache.
- **`start.command`** — Menu option 4's help and label rewritten from "list all shows having them as cast or crew" to "list which of your cached shows they appear in", matching the localized `findShowsWith.sh`. Example changed from a global Tarantino listing to Pedro Alonso, with output reflecting the new tconst column.
- **`tsvPrint.function`** — Column highlighting now matches literally (`rg -F`) instead of building a regex, so titles containing metacharacters (`S.W.A.T.`, `Bill & Ted`, bracketed names) match as written. Replaces a partial `sed` escaping hack that only handled `(`, `)`, `?`.
- **Modern CLI tooling consistency** — `type -p` → `command -v` (`checkForExecutable.function`); `grep -c`/`grep -cF` → `rg -c`/`rg -cF` in three counting call sites (`explain_functions.sh`, `explain_scripts.sh`, `define_files`); the disambiguation-suffix `sed` → `sd` (`saveFilmography.sh`). Load-bearing `grep -f`/`sed` sites in data pipelines were left unchanged.
- **`generateXrefData.sh`** — `(..)` subshell guard in `processDurations` changed to `{ ..; }` (SC2235).
- **`tests/`** — Refreshed to match current behaviour. `test-xrefCast.sh` drops the removed `-i` flag (`-pi` → `-p`). `test-findShowsWith.sh` rewritten around cached people, with two deliberately-uncached names retained to exercise the new local "not indexed" pointer path. `test-findCastOf.sh` points `-f` at an existing list (`Contrib/Acorn.tconst`, was the missing `Dramas.tconst`) and quotes `rm -f "$favoritesFile"`. The remaining tests were verified unchanged: `saveFilmography` is global so its examples stand, and the function/menu tests were unaffected. These are interactive eyeball harnesses, not automated assertions; the sample shows they use (The Crown, The Durrells, etc.) are expected to be in the local cache.

### Removed

- **`xrefCast.sh`** — The `-i`/`INFO` flag, which was accepted and documented but read nowhere. In `big_IMDb_xref` it printed per-file provenance; index-based queries have no such files. Removed the option, its help line, and the getopts entry.
- **`iQuery.sh`** — `jqIdFormat`, assigned in both branches and never read (a refactor orphan).
- **`generateXrefData.sh`** — The dead `TEST_MODE="yes"` assignment. The `-t` flag's real effect (using `tconst.example`) is unchanged; a comment notes the `big_IMDb_xref` test-diff behaviour it once drove was not carried over.

### Notes

- The scraper cannot clear a WAF CAPTCHA. Solve it once in a non-headless browser sharing `~/.config/IMDb_xref/browser_state.json`, then resume normally. That file is disposable — deleting it forces a clean context and is the first thing to try for unexplained scraping behaviour. The `aws-waf-token` cookie in it has roughly a four-day life; the other `.imdb.com` cookies run considerably longer.
- Because `save_state()` is only called from `close()`, a run interrupted with Ctrl-C or killed by an unhandled exception discards any freshly issued token, and the next run re-solves the challenge.
- Two SC2034 warnings are suppressed rather than fixed, with explanatory comments: `pickMenu` in `iQuery.sh` (the `select` matches on `$REPLY` and a parallel array, so the bound label is unused but syntactically required) and SC2094 in `findCastOf.sh` (a false positive — `printHistory` reads from `$histDirectory`, not its argument). The `findCastOf.sh` comment also flags a latent concern for later review: `printHistory` there is passed a path where it expects a basename suffix.
- Deferred to a later session: restoring `skipEpisodes` handling (still unread by the current pipeline), the `channel="chrome"` launch option to reduce WAF CAPTCHAs, and refreshing the `Contrib/` example lists.

---

## [Unreleased] — 2026-07-22

### Added

- **`scraper/models.py`** — `status` field on `FilmographyRole` ("Pre-production", "Completed", "Released", …). Production status was previously overwritten by title type and lost, which made unreleased titles indistinguishable from undated ones.
- **`saveFilmography.sh`** — `SKIP_UNRELEASED=yes` omits titles that have not been released.

### Bugfixes

- **`scraper/pages.py`** — `get_filmography` stamped every credit on a page with a single job category. All categories share one `<section>` on IMDb's fullcredits page, separated only by `<h4>` headings, so `query_selector("h4")` returned the first heading and `query_selector_all(ROW)` returned every row: 660 "actor" roles for one person, 572 "writer" for another, with the remaining categories absent. Now walks headings and rows in document order, switching job at each `<h4>`. The same guard already existed in `get_full_credits` and was never applied here.
- **`scraper/pages.py`** — Row fields were parsed out of `row.inner_text()`. Adjacent inline spans carry no whitespace between them, so values ran together: "a play bybased on the film by", "ReleasedTV Series", "executive producerproducer". Each field is now read from its own element, with credits taken as separate `<li>` items.
- **`scraper/pages.py`** — Only one row layout was handled. Released titles carry a rating and put credits in `ul[data-testid="credit-roles-list"]`; unreleased titles have no rating, use a plain `<ul>`, and render production status as an `<a>`. Both are now parsed.
- **`scraper/pages.py`** — Title type was located by position, but IMDb moves the marker depending on whether the row carries a rating. Now matched by value, taking a sample person from 2 of 99 rows typed to 73 of 99.
- **`saveFilmography.sh`** — The `_generate_filmography_md` job whitelist was a no-op. `map(select(. as $j | $allowed | any(test(.; "i"))))` tested each allowed string against itself inside `any()` and always matched, leaving `$j` unused, so every category passed through including Self, Thanks and Archive Footage. Now matched whole-string against the job.
- **`saveFilmography.sh`** — `select(.character != "" and .character != null)` dropped every non-acting section. Directors and writers have no character, so `filteredRoles` came back empty and the loop hit `continue`; there was no way to emit a Director table.
- **`saveFilmography.sh`** — `tonumber // 0` cannot catch a jq error, as `//` only handles `null` and `false`. An ongoing series year such as "2024– " split to " ", and `" " | tonumber` threw, aborting the whole jq call. Replaced with `scan()`.
- **`saveFilmography.sh`** — Acting table separator row was missing its trailing pipe.
- **`saveFilmography.sh`** — `${DIRNAME}/rg_sections.rgx` was evaluated after the script had already run `cd "$DIRNAME"`, making the path double-relative. Uses the bare filename.

### Changed

- **`saveFilmography.sh`** — No longer writes JSON to `secondary/filmographies/`. The same data is already cached in `.xref_cache/nm*.json`; Markdown is now the only saved output.
- **`saveFilmography.sh`** — Unreleased titles sort to the top of each section in IMDb's own order, with the Year cell showing production status ("Post-production", "Pre-production (2026)"). A title counts as unreleased when it carries a status other than "Released" — IMDb marks some released titles with an explicit "Released". Released titles sort newest first, ties broken by position on the page rather than title.
- **`saveFilmography.sh`** — Episodes column now appears in any section with episode counts, not just acting ones.
- **`saveFilmography.sh`** — Removed the `startswith()` noise filter. It existed to strip credit text that leaked into the character field because every role was labelled "actor"; the parser fix removes the cause.
- **`saveFilmography.sh`** — Emits a single H1 (name as IMDb link) instead of `# Filmography` followed by the name.
- **`rg_sections.rgx`** — Now has effect for the first time, and matches whole-string, so `editor` no longer selects `editorial department`.
- **`scraper/pages.py`** — Filmography extraction runs in a single `page.evaluate()` rather than per-row round trips, which matters on people with 700+ credits.

### Notes

- Cached `nm*.json` files written before this change carry a single bogus job category throughout and will not self-correct. Delete them and re-scrape, then rebuild the index. Cached `tt*.json` show files are unaffected — `get_full_credits` was never involved.

---

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
- **`saveFilmography.sh`** — Generates GitHub-flavored `.md` file alongside `.json`. Groups roles by job (whitelisted via `rg_sections.rgx`), consolidates characters per title, name is H1 link to IMDb (strips "(I)" from display), sorts by last year of range. Non-acting sections include Credit column. Filters noise (self, performer, crew roles).
- **`rg_sections.rgx`** — New file: whitelist of job categories to include in markdown output (actor, actress, director, writer, producer).
- **`scraper/pages.py`** — Filmography scraper: year stored as full range string ("2017–2021"), missed "TV Mini Series"/"Short"/"Completed" as title types, duplicate entries for same (tconst, job). Now deduplicates with unique character merge.
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
