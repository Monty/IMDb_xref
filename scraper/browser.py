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
                page.wait_for_selector(
                    "#challenge-container", state="detached", timeout=15000
                )

            # Wait for real IMDb content to appear (not just the challenge shell)
            # IMDb pages have a #root div with actual content
            try:
                page.wait_for_selector(
                    "#root", state="attached", timeout=10000
                )
                # Give React a moment to hydrate
                page.wait_for_timeout(500)
            except Exception:
                pass  # Some pages might not have #root; continue anyway

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
