#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# # Pinned to match scraper/uv.lock. Unpinned, uv resolves this script to the
# # newest playwright in its own ephemeral environment, which wants a different
# # chromium build than scraper/cli.py -- so this script reports "run playwright
# # install", and doing so installs browsers the scraper will never look at
# # while leaving the ones it needs missing. Bump both together.
# # (Double '#' because uv strips one before parsing this block as TOML.)
# dependencies = ["playwright==1.61.0", "pydantic"]
# ///
"""Open IMDb in a visible browser so a WAF CAPTCHA can be solved by hand.

The scraper cannot clear an AWS WAF CAPTCHA on its own. This launches a
non-headless browser sharing the same ~/.config/IMDb_xref/browser_state.json
the scraper restores from, so a token solved here by hand carries over to
subsequent headless runs.

    ./solve_challenge.py

Solve the CAPTCHA in the window that appears, wait until a normal IMDb page
is showing, then press Return here. If the page is still a challenge when you
press Return, the state is not saved.
"""

import sys
from pathlib import Path

# Resolve the scraper package from this file's location (tools/ is one level
# below scraper/), so the tool works from any checkout without a hardcoded path.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from browser import _CHALLENGE_TITLES, STATE_FILE, BrowserManager

URL = "https://www.imdb.com/name/nm0000123/fullcredits"


def main() -> None:
    manager = BrowserManager(headless=False)
    context = manager.ensure()
    page = context.new_page()
    page.goto(URL, wait_until="domcontentloaded", timeout=60000)

    print(f"Opened {URL}")
    print("Solve the CAPTCHA if one appears, then wait for the credits page.")
    input("Press Return once real IMDb content is showing... ")

    title = (page.title() or "").strip()
    print(f"page title: {title!r}")
    # Reuse the scraper's own challenge markers rather than a private list, so
    # this stays in step with what get_manager().goto() treats as a challenge.
    if any(marker in title.lower() for marker in _CHALLENGE_TITLES):
        print("Still on the challenge page -- state not saved.")
        manager.close()
        sys.exit(1)

    page.close()
    manager.close()  # close() calls save_state()
    print(f"Saved {STATE_FILE}")


if __name__ == "__main__":
    main()
