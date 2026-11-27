#!/usr/bin/env python3
"""Open each page, click Download, save into games/, then wait 5 seconds.

One download at a time. Put one page URL per line in links.txt (gitignored).

Starts normal Google Chrome (not Playwright's Chromium) and waits. Click the
verify checkbox in that window, then press Enter. The script attaches to that
same Chrome and keeps going. Cookies stay in .chrome-profile.

    pip install playwright
    python3 download_games.py
"""

import json
import subprocess
import time
import urllib.request
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "games"
LINKS_FILE = ROOT / "links.txt"
PROFILE = ROOT / ".chrome-profile"
PAUSE_SECONDS = 5
DEBUG_PORT = 9222
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def load_links() -> list[str]:
    if not LINKS_FILE.is_file():
        raise SystemExit(f"Missing {LINKS_FILE.name}: add one URL per line.")
    links = []
    for line in LINKS_FILE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            links.append(line)
    if not links:
        raise SystemExit(f"{LINKS_FILE.name} has no URLs.")
    return links


def chrome_is_listening() -> bool:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{DEBUG_PORT}/json/version", timeout=1) as resp:
            return resp.status == 200
    except OSError:
        return False


def point_downloads_at_games() -> None:
    default = PROFILE / "Default"
    default.mkdir(parents=True, exist_ok=True)
    prefs_path = default / "Preferences"
    prefs = {}
    if prefs_path.is_file():
        try:
            prefs = json.loads(prefs_path.read_text())
        except json.JSONDecodeError:
            prefs = {}
    prefs.setdefault("download", {})
    prefs["download"]["default_directory"] = str(OUT)
    prefs["download"]["directory_upgrade"] = True
    prefs["download"]["prompt_for_download"] = False
    prefs_path.write_text(json.dumps(prefs))


def stop_script_chrome() -> None:
    """Quit only the Chrome this script started (its own profile on port 9222)."""
    if not chrome_is_listening():
        return
    listing = subprocess.run(
        ["lsof", "-nP", f"-iTCP:{DEBUG_PORT}", "-sTCP:LISTEN", "-Fp"],
        capture_output=True,
        text=True,
        check=False,
    )
    pids = [line[1:] for line in listing.stdout.splitlines() if line.startswith("p")]
    for pid in pids:
        cmd = subprocess.run(
            ["ps", "-p", pid, "-o", "command="],
            capture_output=True,
            text=True,
            check=False,
        ).stdout
        if str(PROFILE) in cmd:
            subprocess.run(["kill", pid], check=False)
    for _ in range(25):
        if not chrome_is_listening():
            return
        time.sleep(0.2)


def start_chrome(first_url: str) -> None:
    stop_script_chrome()
    if not Path(CHROME).is_file():
        raise SystemExit(f"Google Chrome not found at {CHROME}")
    PROFILE.mkdir(parents=True, exist_ok=True)
    point_downloads_at_games()
    # -n starts a second Chrome, so this does not have to be the one you already use.
    subprocess.Popen(
        [
            "open",
            "-na",
            "Google Chrome",
            "--args",
            f"--user-data-dir={PROFILE}",
            f"--remote-debugging-port={DEBUG_PORT}",
            "--no-first-run",
            "--no-default-browser-check",
            first_url,
        ],
    )
    for _ in range(75):
        if chrome_is_listening():
            return
        time.sleep(0.2)
    raise SystemExit(
        "Chrome did not open a debugging port. Quit every Chrome window and run this again."
    )


PARTIAL_SUFFIXES = {".crdownload", ".download", ".tmp"}
WATCH_DIRS = (OUT, Path.home() / "Downloads")


def files_in(folder: Path) -> dict[Path, int]:
    found = {}
    if not folder.is_dir():
        return found
    for path in folder.iterdir():
        if path.is_file():
            found[path] = path.stat().st_size
    return found


def is_partial(path: Path) -> bool:
    return path.suffix in PARTIAL_SUFFIXES or path.name.endswith(".crdownload")


def wait_for_new_file(before: dict[Path, int]) -> Path:
    """Wait while Chrome is still writing, then return the finished file.

    A .crdownload is the download in progress. The time limit applies only
    while nothing new is being written, so a large archive can finish.
    """
    started = time.time()
    idle_deadline = started + 90
    stable_since: dict[Path, tuple[int, float]] = {}
    while True:
        partial = False
        candidate: Path | None = None
        for folder in WATCH_DIRS:
            for path, size in files_in(folder).items():
                if path in before and before[path] == size:
                    continue
                if is_partial(path):
                    partial = True
                    idle_deadline = time.time() + 90
                    continue
                if size <= 0:
                    continue
                prev = stable_since.get(path)
                if prev and prev[0] == size and time.time() - prev[1] >= 2:
                    candidate = path
                elif not prev or prev[0] != size:
                    stable_since[path] = (size, time.time())
                    idle_deadline = time.time() + 90
        if candidate and not partial:
            if candidate.parent != OUT:
                dest = OUT / candidate.name
                if dest.exists():
                    dest = OUT / f"{candidate.stem}-{int(time.time())}{candidate.suffix}"
                candidate.replace(dest)
                return dest
            return candidate
        if not partial and time.time() > idle_deadline:
            raise TimeoutError("No finished file showed up in games/ or Downloads.")
        time.sleep(0.5)


def main() -> None:
    links = load_links()
    OUT.mkdir(parents=True, exist_ok=True)
    start_chrome(links[0])
    input(
        "A separate Chrome window should be in front. Click Verify there if it asks, then press Enter. "
    )
    with sync_playwright() as p:
        # no_defaults skips Browser.setDownloadBehavior, which this Chrome rejects.
        browser = p.chromium.connect_over_cdp(
            f"http://127.0.0.1:{DEBUG_PORT}",
            no_defaults=True,
        )
        context = browser.contexts[0]
        page = context.pages[0] if context.pages else context.new_page()
        for i, url in enumerate(links, start=1):
            print(f"[{i}/{len(links)}] {url}")
            if page.url != url:
                page.goto(url, wait_until="domcontentloaded")
            button = page.locator('button[type="submit"]', has_text="Download")
            button.wait_for(state="visible", timeout=120_000)
            before = {}
            for folder in WATCH_DIRS:
                before.update(files_in(folder))
            button.click()
            try:
                dest = wait_for_new_file(before)
            except TimeoutError as exc:
                print(f"  skipped: {exc}")
            else:
                print(f"  saved {dest}")
            if i < len(links):
                time.sleep(PAUSE_SECONDS)


if __name__ == "__main__":
    main()
