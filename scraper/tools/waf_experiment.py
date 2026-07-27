#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright", "pydantic"]
# ///
"""WAF experiment: does real Chrome (channel='chrome') avoid the CAPTCHA that
headless bundled Chromium triggers?

This is a DIAGNOSTIC. It does NOT touch browser.py. It launches your actual
installed Google Chrome (not Playwright's bundled Chromium), headful, sharing
the same ~/.config/IMDb_xref/browser_state.json the scraper uses, and navigates
to an UNCACHED title so the request actually hits IMDb.

What to watch for:
  - Page loads to a normal IMDb title page with NO CAPTCHA  -> strong evidence
    the headless fingerprint was the trigger; the fix is adding channel="chrome"
    (and likely headless=False) to browser.py.
  - A CAPTCHA appears                                       -> real Chrome alone
    isn't sufficient; solve it in the window (that seeds the state file), and we
    lean toward the persistent-browser daemon instead.

Run it, watch the window, then press Return here to record the outcome.
"""

import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

STATE_DIR = Path.home() / ".config" / "IMDb_xref"
STATE_FILE = STATE_DIR / "browser_state.json"

# An uncached, stable title so the request must hit the network. Shawshank is
# never in the TV-detective workflow's cache.
PROBE_URL = "https://www.imdb.com/title/tt0111161/"

_CHALLENGE_SELECTORS = ("#challenge-container", "#captcha-container")
_CHALLENGE_TITLES = ("confirm you are human", "are you a robot", "access denied")

UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/125.0.0.0 Safari/537.36"
)


def main() -> int:
    pw = sync_playwright().start()
    try:
        # THE experiment: channel="chrome" uses the real installed Chrome.
        browser = pw.chromium.launch(headless=False, channel="chrome")
    except Exception as exc:  # noqa: BLE001
        print(f"Could not launch real Chrome (channel='chrome'): {exc}")
        print("Chrome may not be found where Playwright expects it.")
        pw.stop()
        return 2

    ctx_args = {"user_agent": UA, "viewport": {"width": 1280, "height": 900}}
    if STATE_FILE.exists():
        ctx_args["storage_state"] = str(STATE_FILE)
        print(f"Restored cookies from {STATE_FILE}")
    else:
        print("No saved state; starting cold (this is the harshest test).")

    context = browser.new_context(**ctx_args)
    page = context.new_page()
    print(f"Navigating to {PROBE_URL} in real Chrome...")
    page.goto(PROBE_URL, wait_until="domcontentloaded", timeout=60000)

    # Give it a moment, then check for a challenge WITHOUT auto-failing --
    # we want to observe, and let you solve if one appears.
    page.wait_for_timeout(1500)
    title = (page.title() or "").strip()

    hit_challenge = any(page.query_selector(s) for s in _CHALLENGE_SELECTORS) or \
        any(m in title.lower() for m in _CHALLENGE_TITLES)

    if hit_challenge:
        print(f"\n>>> CHALLENGE detected (title: {title!r}).")
        print(">>> Real Chrome alone did NOT avoid it.")
        print(">>> Solve it in the window if you like (seeds the state file),")
        input(">>> then press Return... ")
        title2 = (page.title() or "").strip()
        still = any(page.query_selector(s) for s in _CHALLENGE_SELECTORS) or \
            any(m in title2.lower() for m in _CHALLENGE_TITLES)
        if still:
            print("Still challenged -- state NOT saved.")
            context.close(); browser.close(); pw.stop()
            return 1
        context.storage_state(path=str(STATE_FILE))
        print(f"Solved; saved {STATE_FILE}")
    else:
        print(f"\n>>> NO challenge. Page loaded clean (title: {title!r}).")
        print(">>> Strong evidence the headless fingerprint was the trigger.")
        print(">>> Fix = add channel='chrome' to browser.py.")
        input(">>> Press Return to close... ")
        context.storage_state(path=str(STATE_FILE))
        print(f"Saved fresh state to {STATE_FILE}")

    context.close()
    browser.close()
    pw.stop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
