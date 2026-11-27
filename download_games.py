#!/usr/bin/env python3
"""Open each page, click Download, save into /games, then wait 5 seconds.

One download at a time. Replace LINKS with the pages you want.

    pip install playwright
    playwright install chromium
    python3 download_games.py
"""

import time
from pathlib import Path

from playwright.sync_api import sync_playwright

OUT = Path("/games")
PAUSE_SECONDS = 5

# Example pages. Same Download button on each.
LINKS = [
   "https://vimm.net/vault/28140",
   "https://vimm.net/vault/28329",
   "https://vimm.net/vault/23720",
   "https://vimm.net/vault/23764",
   "https://vimm.net/vault/27745",
   "https://vimm.net/vault/23783",
   "https://vimm.net/vault/27734",
   "https://vimm.net/vault/28061",
   "https://vimm.net/vault/23766",
   "https://vimm.net/vault/24023",
   "https://vimm.net/vault/23818",
   "https://vimm.net/vault/23758",
   "https://vimm.net/vault/28344",
   "https://vimm.net/vault/29410",
   "https://vimm.net/vault/24081",
   "https://vimm.net/vault/24199",
   "https://vimm.net/vault/23918",                          
   "https://vimm.net/vault/27748",
   "https://vimm.net/vault/23825",
   "https://vimm.net/vault/27762",
   "https://vimm.net/vault/23749",
   "https://vimm.net/vault/24183",
   "https://vimm.net/vault/23828",
   "https://vimm.net/vault/23725",
   "https://vimm.net/vault/27748",
   "https://vimm.net/vault/28142",
]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)
        context = browser.new_context(accept_downloads=True)
        page = context.new_page()
        for i, url in enumerate(LINKS, start=1):
            print(f"[{i}/{len(LINKS)}] {url}")
            page.goto(url, wait_until="domcontentloaded")
            button = page.locator('button[type="submit"]', has_text="Download")
            with page.expect_download(timeout=120_000) as info:
                button.click()
            download = info.value
            dest = OUT / download.suggested_filename
            download.save_as(dest)
            print(f"  saved {dest}")
            if i < len(LINKS):
                time.sleep(PAUSE_SECONDS)
        browser.close()


if __name__ == "__main__":
    main()
