# Changelog

## [Unreleased] — 2026-08-27

### Added

- **`saveFilmography.sh`** — Filmographies are now written as Markdown,
  `Person_Name-nconst-Filmography.md` in the primary directory, matching
  `live-fetch` file for file. Sections are ordered acting first, then director,
  writer, producer, then the rest; titles link to IMDb; the Episodes column
  appears per section only when that section has counts.

  **The file opens with a note saying the data is incomplete, and that note is the point rather than a disclaimer.** `title.principals` lists roughly ten names per title, so this branch omits work *silently* — it does not truncate visibly. Elizabeth Debicki is the case that settled it: her Crown credits are absent from the bulk data entirely, and her Night Manager episode count comes in under the real one. A reader who does not know that reads a short filmography as a complete one. Pedro Alonso, checked first, matched `live-fetch` closely — but he is a lead, and leads clear the ten-name cut in nearly every episode. Testing one lead would have confirmed the wrong half of the hypothesis.

- **`saveFilmography.sh`** — Episode counts, derived from
  `title.episode.tsv.gz`. `title.principals` credits a person once per episode
  they were a principal in, so the count is the number of those rows whose
  parent series is the title being listed, keyed by nconst, series tconst and
  category — a person credited on one series as both actor and director gets a
  separate count in each section.

  Computed from the raw principals rows before the tvEpisode entries are filtered out, since they are unrecoverable afterwards. **This is not IMDb's credited-episode total** and will undercount anyone who did not make the principals cut in every episode; the file's header note covers it.

- **`augment_tconstFiles.sh`** — `-r` (reload) discards the augmented cache and
  re-reads every title from `title.basics.tsv.gz`.

### Changed

- **`augment_tconstFiles.sh`** — **The augmented cache now invalidates itself
  when `title.basics.tsv.gz` is newer than it.** A cached tconst was never
  looked up again, so when IMDb revised a title — an Original Title changing is
  the usual one — the stale row won permanently. Nothing in the script could
  ever have corrected it; the only remedy was deleting the cache by hand.

  Every row in the cache derives from that one local dataset, so a row older than it is strictly worse than re-reading — there is no fetch cost here to justify serving stale data, which is exactly why `live-fetch` cannot do the same thing and has no natural expiry. Same gz-is-newer test `generateXrefData.sh` already uses to decide `RELOAD`. The whole cache is discarded rather than matching rows, since a partial invalidation would leave you reasoning about which rows are trustworthy; rebuilding costs one scan of a local file. `[[ -nt ]]` follows symlinks, which matters here — the link's own timestamp is 2026-08-13 and the target's is 2026-08-18, so comparing against the link would give the wrong answer.

  **The check runs before the existing `touch "$cacheFile"`, and that ordering is load-bearing** — touching first sets the cache's mtime to now and makes the comparison permanently false.

- **`saveFilmography.sh`** — `augment_tconstFiles.sh -y` is no longer called
  from the job loop. It ran once per job category — six scans of the same
  `.gz` for George Clooney — and overwrote its argument, so the credit rows had
  to be copied aside before each call to keep the job category and `characters`
  field. Replaced by a single `title.basics` lookup per person, reproducing
  augment's three behaviours explicitly: `cut -f 1-4,6`, dropping tvEpisodes,
  and stripping `\N`. Per-category counts now come from an awk intersection
  against that lookup rather than from counting lines in the file augment had
  overwritten.

- **`saveFilmography.sh`** — The `.tconst` is written as bare IDs and then
  augmented in place with `-y`. On this branch that is a local lookup taking
  seconds, it matches every other `.tconst` in the corpus, and it seeds
  augment's own cache for later runs, so printing the command for the user to
  run — as `live-fetch` does, where it means one scrape per title — would be
  busywork dressed as choice.

- **`saveFilmography.sh`** — The `.md` and the `.tconst` get separate prompts,
  as on `live-fetch`; bundling them meant answering yes to both to get either.
  The `.csv` offer is nested under the `.tconst`, which `generateXrefData.sh`
  needs to exist. The decline path pages the Markdown rather than a different
  rendering of the same data.

- **`saveFilmography.sh`** — The save prompt is one question rather than two. It
  printed `==> Save to <file>?` and then asked `==> Save filmography?`;
  `waitUntil` takes the prompt string, so the `printf` was always redundant.

- **`generateXrefData.sh`** — **Filmography lists are excluded from the default
  `*.tconst` glob.** A filmography is a person's whole credit list, hundreds of
  titles mostly unrelated to the corpus, so picking one up implicitly turned a
  routine run into a very long one. Matched on the `-nm#######.tconst` suffix,
  which both branches now write. Naming one on the command line still works —
  only the bare default skips them, and the count is reported rather than
  silent. If a filmography list is the only `.tconst` present, the script now
  errors out with the explicit command instead of processing nothing.

  This is also the boundary between the two tools rather than only a runtime guard: with `findShowsWith.sh` going local, `saveFilmography.sh` becomes the deliberate global view, and its output staying out of the corpus glob is what keeps those separate.

- **`augment_tconstFiles.sh`** — Help text: `-y` is documented as implying `-i`,
  which it has always done, and the example uses `-y` alone rather than `-iy`.
  The old example suggested `-y` needed `-i` to work.

- **`cleanupEverything.sh`** — **Every question now lists the files it would
  delete before asking, and a question with nothing to delete is skipped
  entirely.**

  The listing is the substantive part. Nothing records which people you asked filmographies for, so "delete all saved filmographies?" was a question you had to answer from memory — with a dozen saved, the only honest answer was to decline. Skipping empty groups is what keeps this script truthful as the branches diverge: a prompt for something a branch never creates stops appearing rather than sitting there implying it might.

  **The filmography question was matching nothing.** `*-Filmography` matched the per-person subdirectories that today's flat-file move removed, so the protection added on 2026-08-15 was protecting nothing, while the `.tconst` and `.csv` were being swept up by the "manually maintained" question one prompt later — answering no to the first was silently undone by the second. Now `*-Filmography.md` has its own question and the other two sit deliberately with the manual files, since both regenerate by re-running `saveFilmography.sh` with the nconst already in the filename.

  **Filmographies are now asked last**, after the hand-maintained `.tconst` and `.xlate` files. Those look comparably precious but are generated by script from the shows Monty has watched; a filmography is the only thing here that a backup is the sole way to recover. That makes "clear everything above, keep these" the common case, and it should be the last decision rather than one made halfway down.

  Patterns are grouped into named arrays used by both the EVERYTHING sweep and the individual questions, so the two cannot drift — previously the same globs were written twice, which is how a pattern could reach one and miss the other.

  Prompt wording was rewritten to stop describing settled outcomes to someone who has not decided yet: the EVERYTHING warning says what each answer *will* do rather than asserting the deletion as fact, questions read `Delete the above ...` so the list above them is unambiguously theirs, and the decline message names its group — a bare `Skipping...` printed under a question reads as though it applies to the list that follows it.

### Fixed

- **`saveFilmography.sh`** — Titles with no `startYear` rendered a literal `\N`
  in the Year column and sorted to the bottom of their section. The inline
  `title.basics` lookup that replaced `augment_tconstFiles.sh` reproduced its
  `cut` and its tvEpisode filter but not its `perl -p -e 's+\\N++g;'`. With the
  marker stripped, the missing-year test works and those titles float to the
  top of their section, where `live-fetch` puts Post-production and
  Pre-production.

  **A missing year is a proxy for unreleased, not the same thing.** This branch has no status field, so an obscure old credit with no recorded year sorts up there too. Debicki's `Code Name Hélène` is the honest case — in development, and per IMDb only fully available on IMDbPro, which is also why `live-fetch` does not see it at all.

## [Unreleased] — 2026-08-26

### Fixed

- **`xrefCast.sh`** — Search now matches terms literally (`rg -F`) instead of as regexes. `SEARCH_PATTERNS` and the `sed 's+[()?]+\\&+g'` that fed it are deleted. That sed was a hand-rolled partial `-F`: its purpose was to stop regex interpretation, but it escaped only `(`, `)`, and `?`, leaving every other metacharacter live. The result was real false positives, not hypothetical ones — `./xrefCast.sh "D.S."` returned `Bertrand (DGSE)` and `DCSU Russell Cornish`, the dots matching `DGSE` and `DCSU`. Working around it meant typing `"D\.S\."`, hand-escaping regex inside a title search, which is the wrong interface. `-F` also makes search and highlight agree, since `tsvPrint -p` has always matched literally; previously a term could match the search but highlight nothing. Search terms here are show titles, person names, and character names — never patterns — so nothing is lost. Removes a tempfile and a pipeline stage.

### Changed

- **`xrefCast.sh`, `iQuery.sh`** — **`-c` is retired and replaced by `-u`, which is a union rather than a corpus swap.** `-c` searched the cross-reference cache *instead of* `Credits-Person.csv`, so reaching an uncurated show meant giving up episode-level credits on every curated one — the same trade `FULLCAST` made before it, under a name that promised the opposite. `-u` searches `Credits-Person.csv` **plus** the cache rows for shows in none of your `.tconst` lists, so it is a genuine superset and the name is honest.

  The letter changed because `-c` was ambiguous in the worst available way: cast and crew both begin with c, and the string the user reads most often is `Principal cast & crew members`, priming both readings at once. `-u` reads as union and was free across the family.

  **The union is computed at show level, which is what dissolves the deduplication problem.** For a show present in both stores the cache adds nothing — both derive series-level rows from `title.principals` for the same tconst, and the CSV additionally carries that show's episode rows — so filtering the cache down to tconsts the CSV lacks leaves nothing to deduplicate. No rank or character-format matching needed. Verified on Money Heist (`tt6468322`, present in both): 12 cache rows against 12 CSV series-level rows, identical in people, ranks, characters, and nconsts, differing only in `actor` vs `actress`, which the existing `perl s/actress/actor/` reconciles anyway.

  **Not the default, deliberately.** `Credits-Person.csv` means "shows I've committed to"; the cache means "everything I've ever looked at," which on a personal corpus includes shows considered and rejected. Folding those into "my shows" would break the question the tool exists to answer. They are two questions, not two coverage levels.

- **`xrefCast.sh`** — Results from `-u` now end with a footer naming which shows in that result came from the cache. Curated shows contribute episode-level depth while cached-only shows contribute ~10 series principals, and nothing in a four-column row distinguishes them — so a character search that misses on a cached-only show looks identical to a real absence. The CHEATSHEET's own gotcha is exactly this case: Elizabeth Debicki as Princess Diana is credited on The Crown's *episodes*, not the series. The footer makes such a miss read as inconclusive rather than negative. Chosen over a per-row marker, which would have touched the projection, the column widths, and `tsvPrint`, and over documenting it in `-h` alone, where nobody reads it at the moment the ambiguity bites. One extra line; four-column output undisturbed.

- **`xrefCast.sh`** — The header no longer names the source. It read `Principal cast & crew members from the cross-reference cache …` under `-c`, which described a whole-result property that no longer exists now that one result can mix both sources. The footer carries that per show instead.

- **`xrefCast.sh`** — The empty-result hint added 2026-08-18 follows suit: instead of `Retry with -c`, it counts matches among the cached-but-uncurated shows only and says `Retry with -u`. It stays silent when `-u` was already used, since there is nothing further to search.

- **`iQuery.sh`** — `-u` builds its three search lists from the same union. In union mode it hands `xrefCast.sh` a `-u` rather than `-f TEMPFILE`: the child builds the identical union itself, and `-f` would suppress not only that but the cache footer — the entire point of marking mixed-depth results. The default path still passes `-f Credits-Person.csv` as before.

## [Unreleased] — 2026-08-18

### Added

- **`xrefCast.sh`** — An empty result now says whether the *other* corpus would have answered, with a real count: `However, 13 matching records are in the cross-reference cache. Retry with -c.` The mirror case is covered too — searching with `-c` and finding nothing points back at `Credits-Person.csv`.

  The old message offered only `Check the "Searching for:" section above.`, which is a misspelling hint, and that was the single most misleading thing the script said. `Credits-Person.csv` is built from the `.tconst` lists, so it answers "shows I've committed to"; the cache accumulates everything ever looked up, including shows deliberately never added. An empty CSV result is therefore frequently the *correct* answer rather than a typo — but nothing distinguished "no such person" from "correct, that's outside your corpus, and here's where it lives."

  The count is deliberately computed through the same projection as the real search, via a new `countMatches`. Counting raw rows would have been easier and wrong: a `tt` or `nm` string appears in the source rows but not in the four searchable columns, so the message would have promised hits that switching corpora cannot produce. The second scan runs only on the empty path, so an ordinary search pays nothing, but a failed search now costs roughly two passes.

  The cache concatenation moved into `buildCacheFile`, shared by the `-c` path and the suggestion path, and its `ls` gained `2>/dev/null` — the suggestion can run before any cache directory exists, and a first-time user searching a typo should not get a stray error beneath the message.

### Changed

- **`xrefCast.sh`** — The search now runs on the projected columns rather than the source rows, making **what is searchable exactly what is displayed**: Name, Job, Show, Character. The `nconst`, `tconst`, `Episode Title`, and `Rank` columns are no longer searchable.

  This was previously inconsistent rather than restrictive. A gate (`rg` over the full 8-column rows) decided whether to run the query, and the query itself ran on the 4-column projection — so `./xrefCast.sh tt4786824` passed the gate, matched nothing downstream, and reported "I didn't find any matching records" about data sitting in column 8 of the file it had just searched. The fix is the gate's deletion: it was redundant with the empty-`TMPFILE` check that follows, so removing it settles the inconsistency *and* drops a full extra scan of the corpus from every search.

  Resolved toward the narrower reading deliberately. Making IDs searchable was the alternative, but characters have no IDs — shows have tconsts and people have nconsts — so ID search would work on two of this script's three axes and silently fail on the third, in a tool whose premise is that one search term treats shows, actors, and characters alike. Hidden-column matching also breaks highlighting: `rg --color always` marks matches in the *projected* text, so a row matched on `Episode Title` could not be highlighted even in principle, and would return with nothing marked and no visible reason for being in the results. Disambiguating five identically-titled shows — the need that prompted trying a tconst — belongs to `findCastOf.sh`, which talks to IMDb and offers a pick menu. Within your own corpus the title is already unambiguous.

- **`xrefCast.sh`** — Removed the `-n` flag. Suppressing menus is now `NO_MENUS` only. `-n` meant "no menu" here while meaning "number of cast members" in `findCastOf.sh` and `findOtherShows.sh` — the same letter taking an argument in one script and not in its siblings. Renaming it to `-N` would have kept both meanings in play and added a lowercase/uppercase pair that looks like two variants of one idea; deleting it retires the letter from this script entirely and leaves one mechanism instead of two.

  The two were not equivalent, which is the part that made this more than a rename. `loopOrExitP` checked `noLoop || NO_MENUS`, but the gate on the interactive "Should I only print those N?" prompt checked `noLoop` alone. Most call sites passed `-d` or `-p` as well, which set `MULTIPLE_NAMES_ONLY`/`PRINCIPAL_CAST_ONLY` and short-circuited that gate anyway — but `iQuery.sh`'s *full* action passed bare `-n`, where `noLoop` was the only thing holding the prompt back. A straight deletion would have reintroduced a blocking prompt there. That gate now reads `NO_MENUS`, which is what it meant all along: it asks whether we are interactive, and `NO_MENUS` is the variable that tracks that.

  Call sites updated to `NO_MENUS="yes" ./xrefCast.sh …`: `findCastOf.sh`, `iQuery.sh` (both actions), and `demo.command` (five questions). No test changes were needed — every test already exports `NO_MENUS` at the top, and none passed `-n`. Worth noting that this also means the tests would not have caught a mistake here: `test-findCastOf.sh` and `test-cache.sh` reach `xrefCast.sh` only as a child process, which inherits the exported variable and would have passed either way. The `demo.command` paths were checked by hand instead, since the demo runs with nothing exported.

### Fixed

- **`functions/tsvPrint.function`, `xrefCast.sh`** — Highlighting moved from search time to display time, fixing both sort order and column alignment.

  `xrefCast.sh` searched with `rg --color always`, so ANSI escapes were in the data before `sort -f -t$'\t' --key=2,2 --key=1,1 --key=3,3 -fu` and before the column-width arithmetic. Two visible symptoms. `ESC` (0x1b) collates ahead of letters, so a person matched *by name* sorted to the front of their job group while a person matched only via the show title sorted normally — `./xrefCast.sh -c "The Crown" "Olivia Colman"` put Olivia Colman ahead of Charles Edwards instead of between Marion Bailey and Matt Smith. And the width calculation counted the invisible bytes as visible characters, so highlighted and unhighlighted rows padded to different widths in the same table. Dedup and the "listed in more than one show" comparison were unaffected, since `rg` highlights every occurrence of a term and a name-matched person is therefore decorated identically in all their rows.

  The fix already existed on `live-fetch` and had never been ported: `tsvPrint` gains `-p PATTERNS_FILE`, which highlights caller-supplied terms wherever they appear using `rg --passthru --color always -F`. `--passthru` is the load-bearing part — a plain `rg` filter would drop every non-matching row, which is why the existing `-c`/default path could not serve as a display-time highlighter.

  `xrefCast.sh` needed the escaped and raw search terms separated to use it. `SEARCH_TERMS` was previously clobbered in place with a regex-escaped copy; the escaped form now lives in a new `SEARCH_PATTERNS` (used by `rg` for the search) while `SEARCH_TERMS` keeps the user's literal terms — which is both what "Searching for:" prints and what `-p` needs, since `-F` would hunt for a literal `\(`.

  Note this also changes `tsvPrint`'s **default** path, used by `findCastOf.sh`, `findOtherShows.sh`, `findShowsWith.sh`, `saveFilmography.sh`, and `generateXrefData.sh`. Three improvements come with the ported version: `-F` makes matching fully literal (the old `sed` escaped only `(`, `)`, and `?`, so a title containing `.`, `*`, or `[` was still read as a regex); blank column values are dropped rather than becoming empty patterns that match — and therefore highlight — every row; and a column with no values at all now prints plainly instead of being swallowed. The rendering logic, previously written out four times, is factored into `_renderTable`.

- **Eight scripts** — Standardized the `getopts` error handlers on `printf "==> Option -%s requires an argument.\n\n" "$OPTARG" >&2` and the matching `%s` form for invalid options.

  Three problems, one line each. Four scripts named the wrong option in the message: `findCastOf.sh` and `findOtherShows.sh` reported "requires a 'maximum menu size' argument" for `-f`, `-n`, and `-r` as well as `-m`, so the diagnostic misdirected on every option but one. All eight carried a stray apostrophe (`argument'.`) — including `generateXrefData.sh`, which was otherwise the cleanest of them. And six interpolated `$OPTARG` inside the format string, where a `%` in the offending option would be read as a conversion specifier.

  Also aligned the `==>` prefix and trailing blank line, which four scripts omitted.

- **`tests/test-xrefCast.sh`** — Stray quote in a prompt string (`""The Durrells"`). Display-only; the command below it was correct.

## [Unreleased] — 2026-08-16

### Fixed

- **`demo.command`** — The demo now builds and queries its own corpus in `./Demo/` instead of whatever data files happen to be in the working directory, so its five fixed questions are answerable for everyone. Yesterday's version only generated data when `Credits-Person.csv` was absent, which is the wrong test: an established user has that file built from their own `.tconst` lists, and those lists very likely don't include The Crown, The Durrells, or The Night Manager. Found in a clone containing every show Monty has watched — which doesn't include The Crown — where the demo asked five questions about a show it couldn't see and answered none of them.

  Uses `generateXrefData.sh -q -d Demo Contrib/demo.tconst`. Because `-d` sets `OUTPUT_DIR`, that run also skips populating the cross-reference cache, recording durations, and saving run history, so demonstrating the tool no longer perturbs a real installation — which the previous approach did, by rewriting the top-level `Credits-Person.csv` and `Shows-*.csv` from a three-show corpus. Each question then passes `-f "$demoCredits"` explicitly. The generated file is located by glob rather than by name so a `DEBUG` run, where `DATE_ID` appends a datestamp, still finds it.

  `/Demo/` added to `.gitignore`, and `Demo` added to `cleanupEverything.sh` — both to the EVERYTHING glob and to the working-files prompt, now worded "working files, test baselines, and the demo corpus."

  `ensureDataFiles -y [TCONST_FILE]` is left in place. Nothing calls `-y` now, but the option and its tconst-file argument are correct on their own terms and cost nothing to keep.

## [Unreleased] — 2026-08-15

### Added

- **`xrefCast.sh`, `iQuery.sh`** — New `-c` flag: search the cross-reference cache instead of `Credits-Person.csv`. This replaces the `FULLCAST` environment variable as the way to reach the cache on this branch, and `FULLCAST` no longer selects a data source here at all.

  `FULLCAST` was wrong for the job in three separate ways. It selected the *thinner* source while its name promised the fuller one — true on `live-fetch`, where the cache is a full-cast superset of the CSV, but inverted here, where the cache holds `title.principals`' ~10 names per show and the CSV carries episode-level credits (6,743 reachable show+person pairs versus 40,140). Its integer was inert: no `ordering` value above 10 exists in `title.principals`, so the `$4 <= FULLCAST` cap could never fire and `FULLCAST=50` and `FULLCAST=5` produced identical output. And it was reachable only by exporting an environment variable, so the behavior was undiscoverable to anyone who hadn't been told — while `start.command` exported a default of 20, meaning a brand-new user got the cache path without ever having heard of it. The inert cap is deleted rather than reimplemented.

  The flag exists because the two corpora differ on two axes at once, not one. The CSV is *deeper* — episode rows are where guest and supporting players live, which is why a half-remembered character usually isn't in the cache. The cache is *wider* — it accumulates every show added by `findCastOf.sh` or `findOtherShows.sh`, including shows in no `.tconst` file. So `-c` isn't a worse version of the default; it's the way to reach a show you looked up once and never curated. Both `-h` texts say so.

  Results now name their source: with `-c`, the two result headers read `Principal cast & crew members from the cross-reference cache …`. Previously a cache answer and a CSV answer arrived under identical headers despite differing by tens of thousands of reachable pairs, which made a short list and a long one look like they should have been the same list. `-c` with an empty cache warns and falls back to the default rather than silently searching it; `-c` combined with `-f` warns that `-c` is ignored, since `-f` wins.

- **`findCastOf.sh`** — New `-n` option: how many cast & crew members to list, `0` for all, defaulting to all. Replaces reading `FULLCAST` for the same purpose, and matches `findOtherShows.sh -n`, which has always meant exactly this. A non-numeric argument warns and lists all rather than being silently ignored. "All" here means all *principals* — the cast is joined from `title.principals.tsv.gz`, roughly ten names per title — so `-h` says so rather than leaving the reader to expect a fullcredits-sized list.

### Changed

- **`findCastOf.sh`** — The display cap now applies at any value. It previously took effect only at 10 or above (`if [[ $maxCast -ge 10 ]]`), so `FULLCAST=5` silently meant *no cap* here while `findOtherShows.sh -n 5` really did cap at 5 — the same number, two different meanings, in two scripts reached from adjacent menu items.

- **`start.command`** — No longer exports `FULLCAST`. This was the sharpest form of the collision: `start.command` set it to 20 for its own menu labels and exported it, which also flipped `xrefCast.sh` and `iQuery.sh` onto the cross-reference cache — so menu items 6 and 7 handed a brand-new user the thinnest available view of their data, with nothing exported and nothing to suggest a variable was involved. The design constraint that the default path must work unconfigured was being broken by the launcher itself, not by anyone's environment. The cap is now local (`castLimit`) and travels explicitly as `-n` to `findCastOf.sh` and `findOtherShows.sh`. `FULLCAST` is still read here as the default value, so existing muscle memory keeps setting the menu's cast limit, but it goes no further than this file.

  "All" is now sayable — but is deliberately not the word used. `FULLCAST=0` already meant no cap, and the labels interpolated an empty string, reading `list their top cast & crew members`. The menu and its help now switch whole phrases: `list their principal cast & crew members` versus `list their top 20 principal cast & crew members`. `all` was rejected in the uncapped case because it would promise something this branch cannot produce — the cast comes from `title.principals.tsv.gz`, about ten names per title, and the hundreds-long fullcredits list exists only on `live-fetch`. `findCastOf.sh`'s own result header changed for the same reason, from `All cast & crew members in IMDb billing order` to `Principal cast & crew members in IMDb billing order`. Also fixed `any any show` in item 3's help text.

- **`demo.command`** — Dropped the `FULLCAST` save/restore around the final question. It existed because `FULLCAST` switched `xrefCast.sh` onto the cache: the demo had to unset it so the character searches would find Princess Diana in the episode rows, then restore it so the last answer matched what the owner's environment would produce. With the cache reachable only via `-c`, all five questions read `Credits-Person.csv` and the demo gives every user the same answers — including the same answer to `Who was in The Crown?`, which previously differed depending on whether `FULLCAST` was exported.

- **`demo.command`** — Build its data files from the committed `Contrib/demo.tconst` when `Credits-Person.csv` is missing, instead of relying on `generateXrefData.sh`'s side effect of inventing `PBS.tconst` from a hardcoded `rg` over `tconst.example`. The demo's corpus is now data in a committed file that can be edited or swapped, rather than three show names embedded in a regex inside the populator (`generateXrefData.sh:300-302`) — the same "behavior lives in editable data files, not source" principle the rest of the toolkit follows. Contents are equivalent for now (The Crown, The Durrells, The Night Manager), so demo output is unchanged; the point is that changing the demo corpus no longer means editing the populator. The check only fires when `Credits-Person.csv` is genuinely absent, so running the demo against an existing corpus still queries that corpus and generates nothing. `PBS.tconst` is still auto-created if no `.tconst` file exists, which is deliberate — it leaves a first-time user with a starting corpus of their own after the demo ends.

- **`functions/ensureDataFiles.function`** — Added `-y` (generate without asking) and an optional `TCONST_FILE` argument passed through to `generateXrefData.sh`. `demo.command` uses `ensureDataFiles -y Contrib/demo.tconst`: the `Shall I generate that file for you?` prompt asks a question someone who has just launched the demo has no basis to answer, and the answer is always yes, since a demo with no data files can do nothing else. The prompt is kept for the other two callers (`xrefCast.sh`, `iQuery.sh`), where a rebuild may cover a full personal corpus rather than three shows and is worth confirming — measured at ~11s for four shows versus minutes for the `Contrib` lists. The existence check at each call site is untouched; what `-y` removes is the decision, not the check. `-y` also skips the trailing "Hit any key" pause, since `demo.command` clears the screen immediately afterward. A named `TCONST_FILE` that doesn't exist is now an error rather than a silent fall-through to every `*.tconst` in the directory.

### Fixed

- **`cleanupEverything.sh`** — The `.xref_bulk_*` prompt called them "user configuration" files, which they are not. They are the cross-reference cache, run history, durations, and record counts — all generated by scripts. The actual user configuration is `~/.config/IMDb_xref/config`, which this script never deletes, and shouldn't: it is shared by every clone, so removing it here would change the behavior of the others. Reworded to name what's being deleted, and noted the config file's exemption in `-h` — the help text claims the EVERYTHING option resets the directory to what a new user would see, which isn't quite true while a preferences file survives elsewhere.

  Reordered every prompt by increasing consequence, which the previous order didn't follow. The two spreadsheet questions were split by file size, and that split ran opposite to what matters: the "smaller files" group held `uniq*.txt`, which `iQuery.sh` searches and `start.command` lists saved shows from, while the "primary spreadsheets" group held six files — `AssociatedTitles`, `Credits-Show`, `Episode-Count`, `LinksToPersons`, `LinksToTitles`, `Persons-KnownFor`, `Shows-Episodes` — that no script reads at all. They're written for exploring the data in a spreadsheet, so deleting them costs space and nothing else. Regrouped as *research spreadsheets nothing reads* and *the credits and list files the scripts search* (`Credits-Person.csv`, `uniq*.txt`). The `.xref_bulk_*` question also moved up, out from under the `[Warning]` banner that applies only to hand-maintained files, so generated state no longer reads as manually created.

  `secondary` was described as generated during debugging; it isn't. `generateXrefData.sh` creates it on every run for ~30 intermediate files and empties it on exit unless `DEBUG` is set, so it's normally an empty directory. Prompt now says "working files and test baselines." Worth knowing that deleting `test_results` doesn't only free space: the next `-t` run takes `checkdiffs`' missing-basefile path, writes a fresh baseline, and reports no diffs — so the comparison passes without comparing anything.

  Dropped `baseline` from both globs. It's a `WhatsStreamingToday` artifact that arrived with the script — live there in `makeIMDbFromFiles.sh` and the `saveTodays*` scripts — and nothing in this project has ever created or read it.

  Added a prompt for saved filmographies, and added `*-Filmography` to the EVERYTHING glob, which previously left them behind despite claiming to reset the directory to a new user's state. They get their own question rather than joining `.tconst`/`.xlate`: `saveFilmography.sh` writes one directory per person you asked about, and while any single one can be rebuilt from the local datasets, nothing records which people you chose — with dozens saved, recovering the set means remembering it. The `[Warning]` banner above them now reads "created from your own input" rather than "usually manually created," which covers filmographies as well as the hand-edited lists.

- **`start.command`** — Menu item 8 ("Show me a list of my saved shows") was a bare `cat uniqTitles.txt`. Since `cleanupEverything.sh` can delete that file and `generateXrefData.sh` is what recreates it, the item printed a raw `No such file or directory` and returned to the menu. It now says what's missing and which script rebuilds it. Unlike `xrefCast.sh` and `iQuery.sh` it doesn't call `ensureDataFiles`, which exits the process when declined — wrong behavior for a menu item you can simply back out of.

- **`start.command`** — Converted the four remaining `[ ]` tests to `[[ ]]` (SC2292) for consistency with every other script here, and quoted `$FULLCAST` in the `findOtherShows.sh -n` call (SC2086) — unquoted and empty, `-n` would have swallowed the following argument.

  The integer test needed more than a bracket swap. `[ "$FULLCAST" -eq "$FULLCAST" ] 2>/dev/null` relies on `[ ]` failing on a non-numeric operand, but inside `[[ ]]` the `-eq` operands are evaluated arithmetically and a bare word is read as a *variable name*: an alphabetic value such as `FULLCAST=all` resolves to an unset variable, compares `0 -eq 0`, passes as "an integer," and shows up in the menu as `top all cast & crew members`. Now tested with `[[ $FULLCAST =~ ^[0-9]+$ ]]`, which is correct for any value and drops the `2>/dev/null` that was hiding the failure. Note `xrefCast.sh:151` carries the same `-eq` idiom inside `[[ ]]` and has the same hole; it's left for the `FULLCAST` work.

- **`functions/ensureDataFiles.function`** — Typo in the success message: `sucessfully` → `successfully`.

## [Unreleased] — 2026-08-14

### Added

- **`generateXrefData.sh`** — Populate the per-show cross-reference cache (`.xref_bulk_cache/<tconst>`) as the final step of a normal run, by splitting the finished `Credits-Person.csv` on its tconst field (field 8) into one headerless file per show. Until now that 8-column cache was written only by `findOtherShows.sh`, so cross-referencing a show found *nothing* unless you had already run `findOtherShows.sh` on every show you wanted compared — a plain bulk load left the cross-reference cache empty. Now the load every user already runs primes it. The rows are byte-compatible with `findOtherShows.sh`'s format (Person, Show Title, Episode Title, Rank, Job, Character Name, nconst ID, tconst ID), including the `actress`→`actor` normalization on field 5 — without it the cross-show filter (`rg 'actor'`, which does not match the substring "actress") would silently drop every actress, which on the OPB list alone is 423 credits. The `Credits-Person.csv` header is skipped by the `^tt` guard on field 8. Only series-level rows (empty Episode Title) are written: an episode credit carries the *episode's* tconst in field 8, so including episodes fans the cache out into one file per episode — measured on `Contrib/OPB.tconst` at 360K across 80 files versus 8.4M across 2,141, a 23× blowup on the smallest of the four `Contrib` lists. Rows are pre-sorted by tconst so each cache file is opened, filled, and closed exactly once, which keeps the open-file count at one however large the corpus grows.

  The leading `'` that this script prepends to every Show Title and Episode Title — present on all 29,894 rows of `Credits-Person.csv`, and there to stop spreadsheets reinterpreting a title as a number or date — is stripped on the way into the cache. It has no place there: `findOtherShows.sh` and `buildShowCache` write the bare title, so leaving it in split the cache into two dialects (`'The Durrells` from this script, `The Crown` from the other two) that compare unequal on any title match or grouping. `xrefCast.sh` strips a leading `\t'` from its own results, which masked the split in some views but not in `findCastOf.sh`'s billing display, which reads the cache directly.

  Shows are overwritten, never pruned: running this on one `.tconst` file refreshes those shows and leaves the rest of the cached corpus alone, so a cache covering all four `Contrib` lists builds up incrementally across separate runs rather than being reset to whichever list ran last. Any 6-column file `findCastOf.sh` had left behind is replaced in passing. Skipped when `-d` writes to an experiment subdirectory, so a scratch run can't clobber the real cache; also runs on the fast no-changes path, so a wiped cache is restored without `-r`. Together with the `findCastOf.sh` change below, this closes the cross-show coupling gap noted on 2026-08-07 — every cached show now carries nconst IDs, so all of them participate in cross-referencing.

- **`functions/buildShowCache.function`** (new) — Factored the local-dataset cast join out of `findOtherShows.sh` so `findCastOf.sh` can share it. Takes a tconst and a show title, joins `title.principals.tsv.gz` (ordering, nconst, category, characters) against `name.basics.tsv.gz` (nconst → name), and writes `$cacheDirectory/<tconst>` in the same 8-column headerless format `generateXrefData.sh` produces. Three cache writers, one format. Unlike the inline version it replaces, it uses its own temp files instead of the caller's — `findCastOf.sh` accumulates cache contents in `TMPFILE`, which the old `findOtherShows.sh` code would have overwritten mid-loop. It also returns 1 without creating a file when a show has no principals, rather than leaving a zero-length cache file that would mark the show as permanently cached and mask the real data on every later run.

### Changed

- **`findCastOf.sh`** — Build its cache with the shared `buildShowCache`, retiring the 6-column writer and the whole perl-translation pipeline that fed it (`SHOWS_PL`, `EPISODES_PL`, `EPISODE_NAMES_PL`, `NAMES_PL`, `CREDITS_CSV`, `EPISODES_CSV`, `EPISODES_LIST`, `NCONST_LIST` are all gone). The 6-column cache carried no nconst or tconst, so a show cached only by this script contributed nothing to `findOtherShows.sh`'s cross-reference — it matched people by nconst inside each cached show's file. Appending the two ID columns to the old pipeline was not viable: `SHOWS_PL` does a *global* tconst→title substitution, so a raw tconst sitting in column 8 would have been rewritten into the show title on its way through. Joining from the datasets directly sidesteps the translation entirely. Show titles are unaffected — both paths take IMDb's `primaryTitle`, and `.xlate` translations were never applied here.

  Two behavior changes fall out of this. Episode-level rows are no longer cached, so the billing-order display lists the series' own principals rather than principals plus every episode's guest cast; this also makes the display consistent for the first time, since a show cached by `generateXrefData.sh` or `findOtherShows.sh` was already series-only and one cached here was not. And the cast is now fetched per show rather than in one batch pass over `title.principals.tsv.gz` for all uncached shows, which costs one dataset scan per uncached show — unnoticeable for the one or two shows a typical search adds, slower if many shows are searched at once and none are cached.

- **`findOtherShows.sh`** — Use the shared `buildShowCache` in place of its inline join; no format change beyond the two below. Skips a show cleanly when it has no principals instead of failing on a missing cache file.

- **Cache format, both writers** — Multiple characters portrayed are now separated with `; ` rather than `, `, matching `generateXrefData.sh`. A comma is legitimate inside a single character name ("Smith, John"), which made a comma-separated list of characters ambiguous; the semicolon is applied only at the `","` boundary between characters, so internal commas survive. Rank is now zero-padded (`01`, not `1`), also matching `generateXrefData.sh` — `findOtherShows.sh` output previously mixed both forms, since it read its own cache files alongside ones written by `generateXrefData.sh`. Both are display-level; every consumer sorts rank numerically. Cache files written before this change keep the old forms until the show is re-cached.

### Fixed

- **`xrefCast.sh`** — An explicit `-f SEARCH_FILE` now wins over `FULLCAST`. The `FULLCAST` block assigned `SEARCH_FILE` unconditionally, *after* the `-f` handling, so whenever `FULLCAST` was set in the environment the file the caller asked for was silently replaced by the concatenated cache — `-f` appeared to work and quietly searched something else. This also hit `findCastOf.sh`, which calls `xrefCast.sh -f` internally with just the shows being examined: with `FULLCAST` set it cross-referenced every cached show instead. Easy to miss, because the search terms usually constrain the output to the same rows either way.

## [Unreleased] — 2026-08-13

### Fixed

- **`generateXrefData.sh`** — `"${SKIP_EPISODES[*]}"` → `"${SKIP_EPISODES[@]}"` when reading the skip list. `[*]` joins the array into a single word, so with two or more `.skipEpisodes` files `rg` was handed one bogus filename like `"PBS.skipEpisodes MHz.skipEpisodes"`, failed, and left `TEMP_SKIPS` empty — which silently restored every episode of every show meant to be skipped. The guard immediately above already used `[@]` correctly, so it could not catch the failure. Inert with a single skip file, which is why it went unnoticed; it would have bitten on the first day a second one existed. The other `[*]` uses in this script are deliberate (display strings on lines 336 and 479, emptiness tests on 341 and 355) and were left alone.

### Changed

- **`Contrib/*.xlate`** — Audited every translation against the re-augmented `.tconst` files and repaired the drift. IMDb had changed 37 primary titles since these were written, and because a translation is keyed on the primary title, each change silently disabled a rule with no error. Removed 18 lines that had become no-ops (IMDb's primary title now equals the translation): `Det som göms i snö`, `Innan vi dör`, the Millennium trilogy, `En man som heter Ove`, `Aanrijding in Moscou`, and 11 MHz titles including `Il commissario Montalbano` and `Les petits meurtres d'Agatha Christie`. Re-keyed 7 lines whose left-hand side no longer matched, restoring series grouping that had quietly broken apart: `Brandvägg`→`Firewall` (Wallander), `Schneewittchen muss sterben`→`Snow White Must Die` plus `Eine unbeliebte Frau`→`An Unpopular Woman` and `Tiefe Wunden`→`Deep Wounds` (Nele Neuhaus Mysteries), `Fallet G`→`The G File` (Van Veeteren), and both `Varg Veum` TV movies. Fixed 2 case-only mismatches that were failing silently because the generated perl substitution has no `/i`: `Arne Dahl: Europa blues` and `Les années perdues`. Changed 10 `Murder In...` right-hand sides to `Murder In` to match MHz's current series name, and dropped `Meurtres à...`, whose literal `...` could only ever match exactly three characters before the anchoring tab and so matched nothing real. `Brandvägg` was then restored alongside `Firewall` as insurance — IMDb has flip-flopped between the two, and duplicate left-hand sides mapping to the same translation are permitted (only differing translations are an error).

- **`Contrib/*.tconst`** — Merged in the watched-show lists and re-augmented. Dropped the high-episode-count anthologies and franchises that bloat the generated spreadsheets without adding cross-reference value: Tatort (1347 episodes), Polizeiruf 110 (428), Nova (1036), American Experience (396). These expand into thousands of rows of one-off credits — documentary narrators, or a franchise whose regional casts don't overlap — diluting every query while contributing almost no cross-show links. Long-running dramas with real recurring casts (Murdoch Mysteries 336, Don Matteo 287, SOKO Kitzbühel 263) were kept. Runtime for the MHz list dropped from 3:18 to 2:14 as a result.

## [Unreleased] — 2026-08-11

### Fixed

- **`functions/safeFilename.function`** (new), **`findOtherShows.sh`**, **`saveFilmography.sh`** — Strip colons when building filenames from show and person names. Titles like "Spider-Man: Far from Home" produced `ShowsWithActorsFrom-Spider-Man:_Far_from_Home.csv`; macOS permits the colon, but Finder still renders it as a `/` (in classic Mac OS `:` was the path separator), so these appeared in Finder as `ShowsWithActorsFrom-Spider-Man/_Far_from_Home.csv` and looked corrupt. A leading `something:` also makes `open` treat the argument as a possible URL scheme and stop to ask which was meant. Forward slashes now become `-` as well, since they can't appear in a filename at all. Apostrophes are removed too — not substituted, since `Hitchhiker's` → `Hitchhikers` reads better than the `Hitchhiker_s` or `Hitchhiker-s` a substitution would give — which also stops filenames from needing shell quoting. Both the ASCII `'` and the typographic `’` are handled, since IMDb uses either. The four call sites across both branches each had their own inline `${name//[[:space:]]/_}`, so the substitution was factored into a shared `safeFilename` function to keep them from drifting. Existing files keep their old names until regenerated.

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
