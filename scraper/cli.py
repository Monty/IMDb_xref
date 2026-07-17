"""CLI entry point for the IMDb scraper.

Usage from the project root:
    uv run scraper/cli.py search-title "Money Heist"
    uv run scraper/cli.py search-person "Jon Bernthal"
    uv run scraper/cli.py full-credits tt6468322
    uv run scraper/cli.py title-basics tt6468322
    uv run scraper/cli.py filmography nm0000123
    uv run scraper/cli.py cast-rankings tt6468322
    uv run scraper/cli.py list-cache
    uv run scraper/cli.py list-cache --persons

All commands output JSON to stdout.

Common flags:
    --refresh     Bypass cache, always scrape fresh.
    --headed      Run browser in headed mode (for debugging).
    --delay SEC   Seconds between requests (default 1.5).
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Sequence

from browser import close_manager, get_manager
from cache import (
    clear_cache,
    get_filmography,
    get_show,
    list_cached_persons,
    list_cached_titles,
    save_filmography,
    save_show,
)
from models import CastMember, Show
from pages import (
    get_filmography as scrape_filmography,
    get_full_credits,
    get_title_basics,
    search_person,
    search_title,
)


def _json(obj) -> None:
    """Print a model or list of models as compact JSON to stdout."""
    if hasattr(obj, "model_dump_json"):
        print(obj.model_dump_json())
    elif isinstance(obj, list):
        # For lists of SearchResults, dump manually
        print(json.dumps([
            r.model_dump() if hasattr(r, "model_dump") else r for r in obj
        ]))
    else:
        print(json.dumps(obj))


def cmd_search_title(args: argparse.Namespace) -> None:
    results = search_title(args.query, limit=args.limit)
    _json(results)


def cmd_search_person(args: argparse.Namespace) -> None:
    results = search_person(args.query, limit=args.limit)
    _json(results)


def cmd_full_credits(args: argparse.Namespace) -> None:
    tconst = args.tconst
    show = None
    if not args.refresh:
        show = get_show(tconst)
    if show is None:
        show = get_full_credits(tconst)
        save_show(show)
    _json(show)


def cmd_title_basics(args: argparse.Namespace) -> None:
    tconst = args.tconst
    show = None
    if not args.refresh:
        show = get_show(tconst)
    if show is None:
        show = get_title_basics(tconst)
    _json(show)


def cmd_filmography(args: argparse.Namespace) -> None:
    nconst = args.nconst
    fg = None
    if not args.refresh:
        fg = get_filmography(nconst)
    if fg is None:
        fg = scrape_filmography(nconst)
        save_filmography(fg)
    _json(fg)


def cmd_cast_rankings(args: argparse.Namespace) -> None:
    """Output cast members sorted by episode count (descending), then rank."""
    tconst = args.tconst
    show = None
    if not args.refresh:
        show = get_show(tconst)
    if show is None:
        show = get_full_credits(tconst)
        save_show(show)

    # Filter to actors only unless --all is set
    cast = show.cast
    if not args.all:
        cast = [c for c in cast if c.job == "actor"]

    # Sort: episodes descending, then rank ascending
    ranked = sorted(cast, key=lambda c: (-c.episodes, c.rank))

    # Apply minimum episode filter
    if args.min_episodes:
        ranked = [c for c in ranked if c.episodes >= args.min_episodes]

    # Apply limit
    if args.limit:
        ranked = ranked[: args.limit]

    _json(ranked)


def cmd_list_cache(args: argparse.Namespace) -> None:
    if args.persons:
        _json(list_cached_persons())
    else:
        _json(list_cached_titles())


def cmd_clear_cache(args: argparse.Namespace) -> None:
    count = clear_cache()
    print(f"Cleared {count} files from cache.")


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="scraper",
        description="IMDb scraper CLI for IMDb_xref",
    )
    parser.add_argument(
        "--headed", action="store_true",
        help="Run browser in headed mode for debugging",
    )
    parser.add_argument(
        "--delay", type=float, default=1.5,
        help="Seconds between page navigations (default 1.5)",
    )

    subs = parser.add_subparsers(dest="command", required=True)

    # search-title
    p_st = subs.add_parser("search-title", help="Search for show/movie titles")
    p_st.add_argument("query", help="Search query")
    p_st.add_argument("--limit", type=int, default=25, help="Max results (default 25)")
    p_st.set_defaults(func=cmd_search_title)

    # search-person
    p_sp = subs.add_parser("search-person", help="Search for people")
    p_sp.add_argument("query", help="Search query")
    p_sp.add_argument("--limit", type=int, default=25, help="Max results (default 25)")
    p_sp.set_defaults(func=cmd_search_person)

    # full-credits
    p_fc = subs.add_parser("full-credits", help="Get full cast & crew for a title")
    p_fc.add_argument("tconst", help="IMDb tconst ID (e.g. tt6468322)")
    p_fc.add_argument("--refresh", action="store_true", help="Bypass cache")
    p_fc.set_defaults(func=cmd_full_credits)

    # title-basics
    p_tb = subs.add_parser("title-basics", help="Get basic title metadata")
    p_tb.add_argument("tconst", help="IMDb tconst ID")
    p_tb.add_argument("--refresh", action="store_true", help="Bypass cache")
    p_tb.set_defaults(func=cmd_title_basics)

    # filmography
    p_fg = subs.add_parser("filmography", help="Get filmography for a person")
    p_fg.add_argument("nconst", help="IMDb nconst ID (e.g. nm0000123)")
    p_fg.add_argument("--refresh", action="store_true", help="Bypass cache")
    p_fg.set_defaults(func=cmd_filmography)

    # cast-rankings
    p_cr = subs.add_parser(
        "cast-rankings", help="List cast sorted by episode count"
    )
    p_cr.add_argument("tconst", help="IMDb tconst ID")
    p_cr.add_argument("--refresh", action="store_true", help="Bypass cache")
    p_cr.add_argument(
        "--min-episodes", type=int, default=0,
        help="Minimum episodes to include (default 0)",
    )
    p_cr.add_argument(
        "--all", action="store_true",
        help="Include all jobs, not just actors",
    )
    p_cr.add_argument("--limit", type=int, default=0, help="Max results (0=all)")
    p_cr.set_defaults(func=cmd_cast_rankings)

    # list-cache
    p_lc = subs.add_parser("list-cache", help="List cached tconst/nconst IDs")
    p_lc.add_argument(
        "--persons", action="store_true",
        help="List cached person IDs instead of title IDs",
    )
    p_lc.set_defaults(func=cmd_list_cache)

    # clear-cache
    p_cc = subs.add_parser("clear-cache", help="Remove all cached data")
    p_cc.set_defaults(func=cmd_clear_cache)

    args = parser.parse_args(argv)

    # Initialize browser
    get_manager(headless=not args.headed, delay=args.delay)

    try:
        args.func(args)
    finally:
        close_manager()


if __name__ == "__main__":
    main()
