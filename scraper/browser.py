"""Playwright browser management with caching and polite rate limiting."""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Optional

from playwright.sync_api import Browser, BrowserContext, Playwright, sync_playwright

# Default delay between page navigations (seconds)
DEFAULT_DELAY = 1.5

# Storage state file for cookies/localStorage persistence
STATE_DIR = Path.home() / ".config" / "IMDb_xref"
STATE_FILE = STATE_DIR / "browser_state.json"

# Append-only record of every WAF challenge seen, one line per event:
#     ISO-timestamp <TAB> kind <TAB> url
#
# Written to a file rather than counted in memory because cli.py runs as a
# fresh process for every show -- generateXrefData.sh invokes _scraper once per
# tconst -- so an in-process counter could never report more than one.
#
# The point of recording these is that the silent JS challenge is invisible
# today: goto() waits for it to detach and carries on, so a run that cleared
# three challenges looks exactly like one that cleared none. Durations showed
# daytime runs dying at 27-30 minutes regardless of how many shows they had
# fetched (123, 119, 79), which points at a ~30 minute WAF token lifetime
# rather than a request-count limit -- but an overnight run went 44:55, which
# only fits that theory if it cleared a silent challenge partway and continued.
# This log is what settles it.
CHALLENGE_LOG = STATE_DIR / "waf_challenges.log"

# Markers for AWS WAF interstitials. The silent JS challenge uses
# #challenge-container and clears itself; the CAPTCHA uses different markup
# and needs a human, so it has to be detected by title as well.
_CHALLENGE_SELECTORS = ("#challenge-container", "#captcha-container")
_CHALLENGE_TITLES = ("confirm you are human", "are you a robot", "access denied")


class WAFChallengeError(RuntimeError):
    """IMDb served a WAF challenge or CAPTCHA instead of real content.

    Raised rather than returning the page, so that an unsolved challenge
    cannot be mistaken for a valid empty result and cached as one.
    """


def log_challenge(kind: str, url: str) -> None:
    """Append one line to CHALLENGE_LOG recording a WAF challenge.

    Never raises: a scrape must not fail because logging did.
    """
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        stamp = time.strftime("%Y-%m-%d %H:%M:%S")
        with CHALLENGE_LOG.open("a") as handle:
            handle.write(f"{stamp}\t{kind}\t{url}\n")
    except OSError:
        pass


def challenge_count() -> int:
    """Return the number of challenges recorded so far."""
    try:
        with CHALLENGE_LOG.open() as handle:
            return sum(1 for _ in handle)
    except OSError:
        return 0


class BrowserManager:
    """Manages a Playwright browser instance with cookie persistence."""

    def __init__(
        self,
        headless: bool = True,
        delay: float = DEFAULT_DELAY,
        state_file: Path = STATE_FILE,
    ):
        self._playwright: Optional[Playwright] = None
        self._browser: Optional[Browser] = None
        self._context: Optional[BrowserContext] = None
        self._headless = headless
        self._delay = delay
        self._state_file = state_file
        self._last_navigation = 0.0

    def ensure(self) -> BrowserContext:
        """Return an active browser context, launching if needed."""
        if self._context is None:
            self._launch()
        # Respect delay between navigations
        elapsed = time.time() - self._last_navigation
        if elapsed < self._delay:
            time.sleep(self._delay - elapsed)
        return self._context

    def _launch(self) -> None:
        """Launch browser and restore cookies from previous session."""
        self._playwright = sync_playwright().start()
        self._browser = self._playwright.chromium.launch(headless=self._headless)

        # Restore previous cookies if they exist
        if self._state_file.exists():
            try:
                self._context = self._browser.new_context(
                    user_agent=(
                        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                        "AppleWebKit/537.36 (KHTML, like Gecko) "
                        "Chrome/125.0.0.0 Safari/537.36"
                    ),
                    storage_state=self._state_file,
                    viewport={"width": 1280, "height": 900},
                )
                return
            except Exception:
                # Corrupt state file — fall through to fresh context
                pass

        self._context = self._browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/125.0.0.0 Safari/537.36"
            ),
            viewport={"width": 1280, "height": 900},
        )

    def save_state(self) -> None:
        """Persist cookies and localStorage for the next session."""
        if self._context is None:
            return
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        self._context.storage_state(path=str(self._state_file))

    def goto(self, url: str, timeout: int = 30000) -> "playwright.sync_api.Page":
        """Navigate to a URL, respecting rate limits. Returns the Page.

        Handles IMDb's AWS WAF JavaScript challenge by waiting for the
        challenge container to disappear and real content to appear.
        """
        context = self.ensure()
        page = context.new_page()
        try:
            page.goto(url, wait_until="domcontentloaded", timeout=timeout)

            # Wait for AWS WAF challenge to resolve, if present
            if page.is_visible("#challenge-container", timeout=2000):
                # The challenge page reloads itself. Wait for it to go away.
                # Logged before the wait so a challenge that never clears is
                # still recorded -- the timeout below raises out of here.
                log_challenge("js-challenge", url)
                page.wait_for_selector(
                    "#challenge-container", state="detached", timeout=15000
                )

            # Wait for real IMDb content to appear (not just the challenge shell)
            # IMDb pages have a #root div with actual content
            try:
                page.wait_for_selector("#root", state="attached", timeout=10000)
                # Give React a moment to hydrate
                page.wait_for_timeout(500)
            except Exception:
                pass  # Some pages might not have #root; continue anyway

            # A challenge still standing at this point will not resolve on its
            # own. Fail loudly instead of handing back a shell page.
            for selector in _CHALLENGE_SELECTORS:
                if page.query_selector(selector):
                    log_challenge("unresolved", url)
                    raise WAFChallengeError(
                        f"WAF challenge ({selector}) not cleared for {url}"
                    )
            title = (page.title() or "").lower()
            for marker in _CHALLENGE_TITLES:
                if marker in title:
                    log_challenge("captcha", url)
                    raise WAFChallengeError(
                        f"WAF CAPTCHA served for {url} (page title: {title!r})"
                    )

            self._last_navigation = time.time()
            return page
        except Exception:
            page.close()
            raise

    def close(self) -> None:
        """Save state and shut down the browser."""
        try:
            self.save_state()
        finally:
            if self._context:
                self._context.close()
            if self._browser:
                self._browser.close()
            if self._playwright:
                self._playwright.stop()
            self._context = None
            self._browser = None
            self._playwright = None


# Module-level singleton used by pages.py
_manager: Optional[BrowserManager] = None


def get_manager(headless: bool = True, delay: float = DEFAULT_DELAY) -> BrowserManager:
    """Return or create the module-level browser singleton."""
    global _manager
    if _manager is None:
        _manager = BrowserManager(headless=headless, delay=delay)
    return _manager


def close_manager() -> None:
    """Shut down the browser singleton."""
    global _manager
    if _manager:
        _manager.close()
        _manager = None
