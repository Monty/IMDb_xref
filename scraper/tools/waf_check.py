#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright", "pydantic"]
# ///
"""Check whether IMDb is currently serving a WAF CAPTCHA.

The scraper serves cached titles from the local index without touching the
network, so probing a cached title would report "clear" even while the WAF is
up. This forces a live fetch via BrowserManager.goto() -- the same path every
scrape uses -- so the result reflects the actual network state.

    ./waf_check.py            # prints clear/blocked, exits 0/1
    ./waf_check.py --quiet    # no output, just the exit code

Exit codes:
    0  clear   -- live IMDb fetch succeeded
    1  blocked -- WAF challenge/CAPTCHA is up (run solve_challenge.py)
    2  error   -- something else went wrong (network down, page changed)

Because it makes one real IMDb request, don't run it in a tight loop -- rapid
automated hits are part of what escalates a silent challenge into a CAPTCHA.
"""

import sys
from pathlib import Path

# Resolve the scraper package from this file's location (tools/ is one level
# below scraper/), so the tool works from any checkout without a hardcoded path.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from browser import WAFChallengeError, close_manager, get_manager  # noqa: E402

# A stable, long-standing IMDb title used only as a reachability probe. It is
# never written to the cache by this tool, so it can't pollute the workflow;
# it just has to be a real page the WAF sits in front of.
PROBE_URL = "https://www.imdb.com/title/tt0111161/"  # The Shawshank Redemption


def main() -> int:
    quiet = "--quiet" in sys.argv
    try:
        manager = get_manager()
        page = manager.goto(PROBE_URL)
        page.close()
    except WAFChallengeError:
        if not quiet:
            print("blocked -- IMDb is serving a WAF CAPTCHA.")
            print("Run scraper/tools/solve_challenge.py, then re-check.")
        return 1
    except Exception as exc:  # noqa: BLE001 -- probe reports, doesn't crash
        if not quiet:
            print(f"error -- couldn't complete the check: {exc}")
        return 2
    finally:
        close_manager()

    if not quiet:
        print("clear -- live IMDb fetch succeeded.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
