## IMDb_xref

Quickly search IMDb for principal cast members of TV shows or movies, characters
they portray, other shows they are in, and whether multiple shows have cast
members in common. Includes episode counts for ranking cast members.

Create comprehensive lists about your favorite shows. Cross-reference to find
shared actors, explore filmographies, and discover connections between shows.

[![MIT License](https://img.shields.io/github/license/Monty/IMDb_xref)](LICENSE)
[![Commits](https://badgen.net/github/commits/Monty/IMDb_xref/main/)](https://github.com/Monty/IMDb_xref)
[![Last Commit](https://img.shields.io/github/last-commit/Monty/IMDb_xref)](https://github.com/Monty/IMDb_xref)

**Table of Contents**

- [Motivation](#motivation)
  - [A simpler solution](#a-simpler-solution)
- [Download IMDb_xref](#download-imdb_xref)
- [Quickstart](#quickstart)
  - [Understanding query results](#understanding-query-results)
  - [Cross-reference saved shows](#cross-reference-saved-shows)
- [Manual installation](#manual-installation)
  - [Install prerequisites](#install-prerequisites)
  - [Run your first query](#run-your-first-query)
  - [Explore other commands](#explore-other-commands)
- [How it works](#how-it-works)
- [Limitations](#limitations)
- [Compatibility](#compatibility)
- [Suggestions](#suggestions)
- [Contributing](#contributing)
- [License](#license)

## Motivation

When watching a TV show or movie, have you ever spotted a familiar face but
can't remember the actor's name or what other shows you've seen them in?

To solve this I used to go to the IMDb website; find the show; click on "See
full cast & crew"; find the character; click on the actor's name; then scroll
through their "Filmography" to see if I recognized any other shows I'd watched.
This was both time-consuming and difficult -- even more so if I wanted to know
if two shows had actors in common.

I wrote **IMDb_xref** to answer such questions simply and quickly. It uses
Playwright to scrape IMDb data on demand, caching results locally for fast
subsequent queries. Now I have even more fun learning about actors and shows.

### A simpler solution

Suppose you're a fan of the PBS series "The Crown". You start watching "The
Night Manager". You recognize the actress who played Princess Diana in "The
Crown" but aren't sure of her name.

Run `start.command`, select `1) Find shows, then list their cast & crew members`.
Enter **`The Crown`**, enter **`The Night Manager`**, enter a blank line.
*It will find shows titled The Crown — select the tvSeries.*
*It will find The Night Manager — select the 2016 version.*

It will display the cast of both shows with episode counts, and finally the
principal cast members who appear in more than one show. You can easily see
that the actress you were looking for is Elizabeth Debicki.

Then select `4) Find people, then list all shows having them as cast or crew`.
Enter **`Elizabeth Debicki`**. It will find all titles listing Elizabeth Debicki
as actress, producer, etc.

Repeat with any cast members you want to know more about, such as Olivia Colman.
You'll discover she is in 130+ shows, including "Broadchurch".

Look up the cast of "Broadchurch" to find more actors, then find more shows and
even more actors. Enjoy exploring! Each query result includes handy links to
imdb.com in case you only want to use **IMDb_xref** as a less cumbersome IMDb
search tool.

## Download IMDb_xref

Either **[download an IMDb_xref
release](https://github.com/Monty/IMDb_xref/releases)** or type those commands
into a terminal window:

```sh
git clone https://github.com/Monty/IMDb_xref.git
cd IMDb_xref
```

## Quickstart

In a terminal window, type `./start.command`. In macOS, you can simply
double-click the `start.command` icon. (*The first time, control-click or
right-click instead. Then select `Open` from the pop-up menu and click `Open` in
the dialog box.*)

This will set up your preferences, check for prerequisites (rg, jq, uv,
Playwright), install scraper dependencies, and open the top-level menu.

Select #1 `Find shows, then list their cast & crew members`. Enter
the title of a movie or TV show you like. If you know another show starring some
of the same actors, enter that on the next line. Then enter a blank line.

### Understanding query results

The cast list shows each actor with their character name and episode count.
Use `-e NNN` to filter by minimum episodes (e.g., `-e 10` to show only series
regulars).

When searching for multiple shows, the results include a section showing cast
members who appear in more than one show.

Selecting #2 `Find shows, then list only cast & crew members they share` will
hide the full cast lists and show only the shared cast.

Menu selections #4 and #5 search for cast and crew members instead of
show titles. Results should be self-explanatory.

### Cross-reference saved shows

When prompted, save shows to your favorites. This enables fast local queries
without re-scraping IMDb.

Select #6 `Run a cross-reference of your cached shows` to enter search terms a
line at a time. You can mix and match shows, cast or crew members, and
characters portrayed in a single search, e.g. The Crown, Olivia Colman, and
Queen Elizabeth.

Select #7 `Run a guided cross-reference of your cached shows` to predict and fill
in search terms with minimal typing. This is particularly useful on a tablet
running a terminal emulator.

### Search term hints

You don't need to quote a search term or escape spaces. **`The Crown`** or
**`Schitt's Creek`** will both be handled correctly.

Shows with non-English titles such as **`La casa de papel`** must be entered
exactly. You can copy/paste such search terms, or use a tconst/nconst found in
their IMDb URL, e.g. https://imdb.com/title/tt6468322/ and
https://www.imdb.com/name/nm0489862/

## Manual installation

### Install prerequisites

- **ripgrep** (`brew install ripgrep`) — for fast text search
- **jq** (`brew install jq`) — for JSON processing
- **uv** ([install](https://docs.astral.sh/uv/)) — Python package manager
- **Playwright** (`npm install -g playwright`) — browser automation for scraping
- **Playwright chromium** (`playwright install chromium`) — the browser binary

The `ensurePrerequisites` function (run automatically by scripts) checks for
these and installs scraper dependencies and the Playwright browser if missing.

### Run your first query

Run `./findCastOf.sh "The Crown"` to see the cast of The Crown with episode
counts. Or `./findCastOf.sh -e 20 "The Crown"` to see only actors with 20+
episodes.

Run `./xrefCast.sh "Olivia Colman"` to see what cached shows she appears in.

Run `./demo.command` to see example queries and results.

### Explore other commands

All the commands in the top-level menu invoke shell scripts that can be run in a
terminal window, supplying options and parameters on the command line.

Run `./explain_scripts.sh` to learn about all available scripts.

If you run one of the commands from `start.command` as a shell script, it will
still open the top-level menu when it exits. Set `NO_MENUS=yes` to skip this.

## How it works

IMDb_xref uses Playwright to scrape IMDb's fullcredits and filmography pages,
storing results as JSON in `.xref_cache/`. A flat JSONL index in `.xref_index/`
is built from the cache for fast local queries.

**First query for a show:** scrapes IMDb (~2-3 seconds with rate limiting),
caches the result, rebuilds the index.

**Subsequent queries:** read from the local index — instant.

The scraper handles IMDb's AWS WAF JavaScript challenge automatically and
persists cookies between runs.

Job categories indexed are controlled by `rg_jobs.rgx` (currently: actor,
actress, cinematographer, director, editor, producer, writer).

## Limitations

- IMDb data sometimes has errors or omissions
- The scraper fetches data from the "Full Cast & Crew" page, which may differ
  slightly from the principal cast shown on title pages
- Episode counts are scraped from text on the page and may occasionally be
  misparsed
- IMDb may change their page structure, requiring scraper updates
- Rate limiting (1.5s default between requests) means bulk operations take time
- First-time setup requires Playwright browser installation (~170 MB)

## Compatibility

Tested on macOS (Apple Silicon) and Linux. Requires Bash, rg, jq, uv, Python
3.13+, and Playwright. May work in Windows 11 with WSL2 installed.

## Suggestions

Start your own `.tconst` lists: broad genres such as Comedies, Sci-Fi, Musicals,
Historical Dramas — or more specific ones like "All Alfred Hitchcock movies",
"TV shows with Robots", or "Shows with Salsa music".

Run `./generateXrefData.sh` on a `.tconst` file to fetch full credits for all
shows in it, then use `./xrefCast.sh` and `./iQuery.sh` to explore connections.

## Contributing

Feel free to dive in! Contribute an interesting `.tconst` list, submit
additional scripts, [Open an issue](https://github.com/Monty/IMDb_xref/issues/new),
or submit PRs.

## License

[MIT](LICENSE) © Monty Williams
