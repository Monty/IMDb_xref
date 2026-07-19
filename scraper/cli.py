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
from index import (
    find_common_cast,
    get_cast_for_show,
    get_person_info,
    get_shows_for_person,
    get_title_info,
    index_stats,
    list_persons as list_index_persons,
    list_titles,
    rebuild_index,
    search_index,
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
        print(
            json.dumps([r.model_dump() if hasattr(r, "model_dump") else r for r in obj])
        )
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
        save_show(show)
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


# ---------------------------------------------------------------------------
# Index commands (no browser needed)
# ---------------------------------------------------------------------------


def cmd_rebuild_index(args: argparse.Namespace) -> None:
    counts = rebuild_index()
    _json(counts)


def cmd_index_stats(args: argparse.Namespace) -> None:
    _json(index_stats())


def cmd_query(args: argparse.Namespace) -> None:
    index_file = args.index_file or "cast-by-person.jsonl"
    results = search_index(args.query, index_file)
    if args.limit:
        results = results[: args.limit]
    _json(results)


def cmd_cast_for_show(args: argparse.Namespace) -> None:
    cast = get_cast_for_show(args.tconst)
    if args.actors_only:
        cast = [c for c in cast if c["job"] == "actor"]
    if args.min_episodes:
        cast = [c for c in cast if c["episodes"] >= args.min_episodes]
    # Sort by episodes descending, then rank ascending
    cast = sorted(cast, key=lambda c: (-c["episodes"], c["rank"]))
    if args.limit:
        cast = cast[: args.limit]
    _json(cast)


def cmd_shows_for_person(args: argparse.Namespace) -> None:
    shows = get_shows_for_person(args.nconst)
    if args.limit:
        shows = shows[: args.limit]
    _json(shows)


def cmd_common_cast(args: argparse.Namespace) -> None:
    results = find_common_cast(args.tconsts)
    _json(results)


def cmd_title_info(args: argparse.Namespace) -> None:
    info = get_title_info(args.tconst)
    if info is None:
        print(f"tconst {args.tconst} not found in index")
        return
    _json(info)


def cmd_person_info(args: argparse.Namespace) -> None:
    info = get_person_info(args.nconst)
    if info is None:
        print(f"nconst {args.nconst} not found in index")
        return
    _json(info)


def cmd_list_titles(args: argparse.Namespace) -> None:
    _json(list_titles())


def cmd_list_persons_index(args: argparse.Namespace) -> None:
    _json(list_index_persons())


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="scraper",
        description="IMDb scraper CLI for IMDb_xref",
    )
    parser.add_argument(
        "--headed",
        action="store_true",
        help="Run browser in headed mode for debugging",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=1.5,
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
    p_cr = subs.add_parser("cast-rankings", help="List cast sorted by episode count")
    p_cr.add_argument("tconst", help="IMDb tconst ID")
    p_cr.add_argument("--refresh", action="store_true", help="Bypass cache")
    p_cr.add_argument(
        "--min-episodes",
        type=int,
        default=0,
        help="Minimum episodes to include (default 0)",
    )
    p_cr.add_argument(
        "--all",
        action="store_true",
        help="Include all jobs, not just actors",
    )
    p_cr.add_argument("--limit", type=int, default=0, help="Max results (0=all)")
    p_cr.set_defaults(func=cmd_cast_rankings)

    # list-cache
    p_lc = subs.add_parser("list-cache", help="List cached tconst/nconst IDs")
    p_lc.add_argument(
        "--persons",
        action="store_true",
        help="List cached person IDs instead of title IDs",
    )
    p_lc.set_defaults(func=cmd_list_cache)

    # clear-cache
    p_cc = subs.add_parser("clear-cache", help="Remove all cached data")
    p_cc.set_defaults(func=cmd_clear_cache)

    # rebuild-index
    p_ri = subs.add_parser("rebuild-index", help="Rebuild JSONL index from cache")
    p_ri.set_defaults(func=cmd_rebuild_index)

    # index-stats
    p_is = subs.add_parser("index-stats", help="Show index file stats")
    p_is.set_defaults(func=cmd_index_stats)

    # query — search any index file
    p_q = subs.add_parser("query", help="Search the index by substring")
    p_q.add_argument("query", help="Search query")
    p_q.add_argument(
        "--index-file",
        default="cast-by-person.jsonl",
        help="Index file to search (default: cast-by-person.jsonl)",
    )
    p_q.add_argument("--limit", type=int, default=0, help="Max results (0=all)")
    p_q.set_defaults(func=cmd_query)

    # cast-for-show
    p_cfs = subs.add_parser("cast-for-show", help="Get cast for a show from index")
    p_cfs.add_argument("tconst", help="IMDb tconst ID")
    p_cfs.add_argument("--actors-only", action="store_true")
    p_cfs.add_argument("--min-episodes", type=int, default=0)
    p_cfs.add_argument("--limit", type=int, default=0, help="Max results (0=all)")
    p_cfs.set_defaults(func=cmd_cast_for_show)

    # shows-for-person
    p_sfp = subs.add_parser(
        "shows-for-person", help="Get shows for a person from index"
    )
    p_sfp.add_argument("nconst", help="IMDb nconst ID")
    p_sfp.add_argument("--limit", type=int, default=0, help="Max results (0=all)")
    p_sfp.set_defaults(func=cmd_shows_for_person)

    # common-cast
    p_cc2 = subs.add_parser("common-cast", help="Find cast shared between shows")
    p_cc2.add_argument("tconsts", nargs="+", help="Two or more tconst IDs")
    p_cc2.set_defaults(func=cmd_common_cast)

    # title-info
    p_ti = subs.add_parser("title-info", help="Get title info from index")
    p_ti.add_argument("tconst", help="IMDb tconst ID")
    p_ti.set_defaults(func=cmd_title_info)

    # person-info
    p_pi = subs.add_parser("person-info", help="Get person info from index")
    p_pi.add_argument("nconst", help="IMDb nconst ID")
    p_pi.set_defaults(func=cmd_person_info)

    # list-titles
    p_lt = subs.add_parser("list-titles", help="List all indexed titles")
    p_lt.set_defaults(func=cmd_list_titles)

    # list-persons
    p_lp = subs.add_parser("list-persons-index", help="List all indexed persons")
    p_lp.set_defaults(func=cmd_list_persons_index)

    args = parser.parse_args(argv)

    # Index commands don't need a browser
    needs_browser = args.command not in (
        "rebuild-index",
        "index-stats",
        "query",
        "cast-for-show",
        "shows-for-person",
        "common-cast",
        "title-info",
        "person-info",
        "list-titles",
        "list-persons-index",
        "list-cache",
        "clear-cache",
    )
    if needs_browser:
        get_manager(headless=not args.headed, delay=args.delay)

    try:
        args.func(args)
    finally:
        close_manager()


if __name__ == "__main__":
    main()
