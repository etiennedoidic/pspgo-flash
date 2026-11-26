#!/usr/bin/env python3
"""PSPGo Studio: a local web app for the pspgo-flash profile.

Standard library only. Binds to 127.0.0.1. Everything it edits lives in
profile/ (and library/ for listing); "Push" runs `pspgo-setup.sh push`.
"""
import argparse
import json
import re
import os
import shutil
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

ARGS = None
IMG_EXT = (".jpg", ".jpeg", ".png")
GAME_SKIP = re.compile(r"^(UPDATE|FasterARK|FASTERARK|ARK_.*|CustomIPL|CIPL.*|ARK.*Updater)$")


def cfg():
    root = ARGS.root
    return {
        "root": root,
        "profile": os.path.join(root, "profile"),
        "library": os.path.join(root, "library"),
        "go": os.environ.get("PSPGO_VOL", "/Volumes/PSPGO"),
        "sd": os.environ.get("PSPGOSD_VOL", "/Volumes/PSPGoSD"),
        "state": os.path.join(root, ".state"),
    }


def safe_name(name):
    name = os.path.basename(unquote(name or "")).strip()
    if not name or name.startswith("."):
        raise ValueError("bad file name")
    return name


def disk(path):
    if not os.path.isdir(path):
        return None
    u = shutil.disk_usage(path)
    return {"total": u.total, "free": u.free, "used": u.used}


def du(path):
    total = 0
    for dp, _, files in os.walk(path):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(dp, f))
            except OSError:
                pass
    return total


def listdir(path, exts=None):
    if not os.path.isdir(path):
        return []
    out = []
    for n in sorted(os.listdir(path)):
        if n.startswith("."):
            continue
        p = os.path.join(path, n)
        if exts and not n.lower().endswith(exts):
            continue
        out.append({"name": n, "size": du(p) if os.path.isdir(p) else os.path.getsize(p)})
    return out


def read_state():
    st = {}
    try:
        with open(cfg()["state"]) as f:
            for line in f:
                if "=" in line:
                    k, v = line.rstrip("\n").split("=", 1)
                    st[k] = v
    except OSError:
        pass
    return st


def run_cli(*args):
    p = subprocess.run(
        ["bash", os.path.join(cfg()["root"], "pspgo-setup.sh"), *args],
        capture_output=True, text=True, timeout=1800,
        env={**os.environ, "PSPGO_YES": "1"},
    )
    return {"code": p.returncode, "output": (p.stdout + p.stderr)}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a):
        pass

    # ---- helpers ----
    def send_json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path, ctype):
        with open(path, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        n = int(self.headers.get("Content-Length", 0))
        if n > 2 * 1024 ** 3:
            raise ValueError("upload too large")
        return self.rfile.read(n)

    def route(self):
        return [p for p in urlparse(self.path).path.split("/") if p]

    # ---- GET ----
    def do_GET(self):
        c = cfg()
        r = self.route()
        try:
            if not r:
                return self.send_file(os.path.join(c["root"], "studio", "index.html"), "text/html; charset=utf-8")
            if r == ["api", "status"]:
                last = os.path.join(c["go"], ".pspgo-last-sync")
                return self.send_json({
                    "go": disk(c["go"]), "sd": disk(c["sd"]),
                    "lastPush": open(last).read().strip() if os.path.isfile(last) else None,
                    "state": read_state(),
                })
            if r == ["api", "wallpapers"]:
                return self.send_json(listdir(os.path.join(c["profile"], "wallpapers"), IMG_EXT))
            if r[:2] == ["files", "wallpapers"] and len(r) == 3:
                p = os.path.join(c["profile"], "wallpapers", safe_name(r[2]))
                return self.send_file(p, "image/png" if p.lower().endswith(".png") else "image/jpeg")
            if r == ["api", "themes"]:
                return self.send_json({
                    "profile": listdir(os.path.join(c["profile"], "theme"), (".ctf",)),
                    "device": listdir(os.path.join(c["go"], "PSP", "THEME"), (".ctf",)),
                })
            if r == ["api", "plugins"]:
                p = os.path.join(c["profile"], "seplugins", "PLUGINS.TXT")
                return self.send_json({"text": open(p).read() if os.path.isfile(p) else ""})
            if r == ["api", "wifi"]:
                p = os.path.join(c["profile"], "wifi.json")
                return self.send_json(json.load(open(p)) if os.path.isfile(p) else {"networks": []})
            if r == ["api", "games"]:
                lib = c["library"]
                dev = {}
                for label, v in (("PSPGoSD", c["sd"]), ("PSPGO", c["go"])):
                    if os.path.isdir(v):
                        dev[label] = {
                            "iso": listdir(os.path.join(v, "ISO"), (".iso", ".cso")),
                            "game": [g for g in listdir(os.path.join(v, "PSP", "GAME"))
                                     if not GAME_SKIP.match(g["name"])],
                        }
                return self.send_json({
                    "library": {"iso": listdir(os.path.join(lib, "ISO"), (".iso", ".cso")),
                                "game": listdir(os.path.join(lib, "GAME"))},
                    "device": dev,
                })
            self.send_json({"error": "not found"}, 404)
        except (OSError, ValueError) as e:
            self.send_json({"error": str(e)}, 400)

    # ---- POST / PUT / DELETE ----
    def do_POST(self):
        c = cfg()
        r = self.route()
        try:
            if r[:2] == ["api", "upload"] and len(r) == 3:
                kind = r[2]
                dest = {"wallpapers": ("wallpapers", IMG_EXT),
                        "themes": ("theme", (".ctf",)),
                        "iso": (os.path.join("..", "library", "ISO"), (".iso", ".cso"))}.get(kind)
                if not dest:
                    raise ValueError("unknown upload type")
                name = safe_name(self.headers.get("X-Filename"))
                if not name.lower().endswith(dest[1]):
                    raise ValueError("wrong file type for " + kind)
                d = os.path.normpath(os.path.join(c["profile"], dest[0]))
                os.makedirs(d, exist_ok=True)
                remaining = int(self.headers.get("Content-Length", 0))
                with open(os.path.join(d, name), "wb") as f:   # stream: ISOs can be GBs
                    while remaining > 0:
                        chunk = self.rfile.read(min(1 << 20, remaining))
                        if not chunk:
                            break
                        f.write(chunk)
                        remaining -= len(chunk)
                return self.send_json({"ok": True, "name": name})
            if r == ["api", "push"]:
                return self.send_json(run_cli("push"))
            if r == ["api", "push-dry"]:
                return self.send_json(run_cli("push", "--dry-run"))
            if r == ["api", "games-push"]:
                return self.send_json(run_cli("games", "push"))
            if r == ["api", "eject"]:
                return self.send_json(run_cli("eject"))
            self.send_json({"error": "not found"}, 404)
        except (OSError, ValueError, subprocess.SubprocessError) as e:
            self.send_json({"error": str(e)}, 400)

    def do_PUT(self):
        c = cfg()
        r = self.route()
        try:
            if r == ["api", "plugins"]:
                text = json.loads(self.body())["text"]
                os.makedirs(os.path.join(c["profile"], "seplugins"), exist_ok=True)
                with open(os.path.join(c["profile"], "seplugins", "PLUGINS.TXT"), "w") as f:
                    f.write(text.rstrip("\n") + "\n")
                return self.send_json({"ok": True})
            if r == ["api", "wifi"]:
                data = json.loads(self.body())
                nets = [{"ssid": str(n.get("ssid", ""))[:32],
                         "password": str(n.get("password", ""))[:63],
                         "security": n.get("security", "wpa2-aes")}
                        for n in data.get("networks", []) if n.get("ssid")]
                p = os.path.join(c["profile"], "wifi.json")
                with open(p, "w") as f:
                    json.dump({"networks": nets}, f, indent=2)
                os.chmod(p, 0o600)
                return self.send_json({"ok": True, "count": len(nets)})
            self.send_json({"error": "not found"}, 404)
        except (OSError, ValueError, KeyError) as e:
            self.send_json({"error": str(e)}, 400)

    def do_DELETE(self):
        c = cfg()
        r = self.route()
        try:
            if len(r) == 3 and r[:2] == ["api", "wallpapers"]:
                os.remove(os.path.join(c["profile"], "wallpapers", safe_name(r[2])))
                return self.send_json({"ok": True})
            if len(r) == 3 and r[:2] == ["api", "themes"]:
                os.remove(os.path.join(c["profile"], "theme", safe_name(r[2])))
                return self.send_json({"ok": True})
            self.send_json({"error": "not found"}, 404)
        except (OSError, ValueError) as e:
            self.send_json({"error": str(e)}, 400)


def main():
    global ARGS
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--port", type=int, default=8478)
    ARGS = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", ARGS.port), Handler)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
