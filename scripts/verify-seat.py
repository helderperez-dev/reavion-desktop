#!/usr/bin/env python3
"""Check that a running seat shows the Reavion desktop and viewer.

  python3 scripts/verify-seat.py https://abc123.reavion.com MCP_API_KEY [MCP_API_KEY ...]
  SEATS='{"abc123": "key", ...}' python3 scripts/verify-seat.py --env

Reads real state on the seat (through its MCP driver) instead of eyeballing a
screenshot: menu icon, theme version, the panel watcher, dock position, and the
noVNC branding served at the edge. Exit code 1 when any seat fails.
Needs only the Python standard library.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

EXPECTED_THEME = None  # read from the repo's theme script when available


def expected_theme() -> str | None:
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "..", "vendor", "reavion-xfce", "src", "scripts", "reavion-desktop-theme.sh")
    try:
        m = re.search(r'^THEME_VERSION="(\d+)"', open(path).read(), re.M)
        return m.group(1) if m else None
    except OSError:
        return None


class Mcp:
    def __init__(self, base: str, key: str):
        self.url = base.rstrip("/") + "/mcp"
        self.key = key
        self.session = None
        self.seq = 0

    def _post(self, payload: dict, timeout: float = 60) -> dict | None:
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "Authorization": f"Bearer {self.key}",
            "User-Agent": "reavion-verify-seat",
        }
        if self.session:
            headers["Mcp-Session-Id"] = self.session
        req = urllib.request.Request(self.url, json.dumps(payload).encode(), headers, method="POST")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            self.session = resp.headers.get("Mcp-Session-Id") or self.session
            body = resp.read().decode()
        if not body.strip():
            return None
        if body.lstrip().startswith("{"):
            return json.loads(body)
        for line in body.splitlines():  # SSE framing
            if line.startswith("data:"):
                data = json.loads(line[5:].strip())
                if "id" in data:
                    return data
        return None

    def call(self, method: str, params: dict | None = None) -> dict:
        self.seq += 1
        out = self._post({"jsonrpc": "2.0", "id": self.seq, "method": method, "params": params or {}})
        if not out or "error" in out:
            raise RuntimeError(f"{method}: {out and out.get('error')}")
        return out["result"]

    def open(self) -> None:
        self.call("initialize", {
            "protocolVersion": "2025-03-26",
            "capabilities": {},
            "clientInfo": {"name": "reavion-verify-seat", "version": "1"},
        })
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def close(self) -> None:
        if not self.session:
            return
        req = urllib.request.Request(
            self.url, method="DELETE",
            headers={"Mcp-Session-Id": self.session, "Authorization": f"Bearer {self.key}"},
        )
        try:
            urllib.request.urlopen(req, timeout=10).read()
        except Exception:  # noqa: BLE001
            pass

    def tool(self, name: str, args: dict) -> str:
        res = self.call("tools/call", {"name": name, "arguments": args})
        parts = [c.get("text", "") for c in res.get("content", []) if c.get("type") == "text"]
        if res.get("structuredContent"):
            parts.append(json.dumps(res["structuredContent"]))
        return "\n".join(parts)


# Runs in the seat's shell; the results come back as a window title we can read.
PROBE = (
    'm=$(xfconf-query -c xfce4-panel -l -v | awk \'$2=="applicationsmenu"||$2=="whiskermenu"{print $1; exit}\'); '
    'icon=$(xfconf-query -c xfce4-panel -p "$m/button-icon" 2>/dev/null || echo none); '
    'theme=$(cat ~/.config/reavion-desktop-theme.version 2>/dev/null || echo none); '
    'watch=$(pgrep -fc "[r]eavion-desktop-watch.sh"); '
    'h=$(xrandr --current | sed -n "s/.*current [0-9]* x \\([0-9]*\\).*/\\1/p"); '
    'xfce4-terminal --title "RVCHECK menu=${m:-none} icon=$icon theme=$theme watch=$watch height=$h" -x sleep 12'
)


def check_seat(base: str, key: str, want_theme: str | None) -> list[str]:
    problems: list[str] = []

    # noVNC at the edge.
    def fetch(path: str) -> str:
        req = urllib.request.Request(base.rstrip("/") + path, headers={"User-Agent": "reavion-verify-seat"})
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.read().decode(errors="replace")

    try:
        if 'location.replace("index.html"' not in fetch("/vnc.html"):
            problems.append("vnc.html does not forward to the Reavion gate")
        if "reavion-mark-white.png" not in fetch("/app/styles/reavion.css"):
            problems.append("noVNC control rail handle is not the Reavion tab")
    except urllib.error.URLError as exc:
        problems.append(f"edge unreachable: {exc}")
        return problems

    # Desktop state through the driver.
    mcp = Mcp(base, key)
    try:
        deadline = time.time() + 240
        while True:
            try:
                mcp.open()
                break
            except Exception as exc:  # noqa: BLE001
                if time.time() > deadline:
                    problems.append(f"MCP not ready: {exc}")
                    return problems
                time.sleep(8)
        mcp.tool("launch_app", {"name": "bash", "additional_arguments": ["-c", PROBE]})
        title = ""
        windows: list[dict] = []
        for _ in range(8):
            time.sleep(1.5)
            raw = mcp.tool("list_windows", {})
            m = re.search(r"RVCHECK [^\"\\\n]*", raw)
            if m:
                title = m.group(0)
                blob = raw[raw.find('{"windows"'):] if '{"windows"' in raw else "{}"
                try:
                    windows = json.loads(blob).get("windows", [])
                except ValueError:
                    windows = []
                break
        if not title:
            problems.append("could not read desktop state (probe window never appeared)")
            return problems
        fields = dict(kv.split("=", 1) for kv in title.split()[1:] if "=" in kv)
        if fields.get("icon") != "reavion-mark":
            problems.append(f"menu icon is {fields.get('icon')!r}, expected 'reavion-mark'")
        if want_theme and fields.get("theme") != want_theme:
            problems.append(f"theme version {fields.get('theme')!r}, expected {want_theme!r}")
        if fields.get("watch", "0") in ("", "0"):
            problems.append("reavion-desktop-watch.sh is not running (dock will not follow resizes)")
        try:
            height = int(fields.get("height", "0"))
        except ValueError:
            height = 0
        for w in windows:
            if w.get("app_name") == "Xfce4-panel" and height and w.get("height", 0) > 8:
                if w.get("y", 0) + w.get("height", 0) > height + 2:
                    problems.append(f"a panel sits off screen (y={w.get('y')}, screen height {height})")
        print(f"      {title}")
    finally:
        mcp.close()
    return problems


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] == "--env":
        seats = json.loads(os.environ.get("SEATS", "{}"))
        targets = [(f"https://{name}.reavion.com", key) for name, key in seats.items()]
    elif len(sys.argv) >= 3:
        targets = [(sys.argv[1], sys.argv[2])]
    else:
        print(__doc__)
        return 2
    want = expected_theme()
    failed = 0
    for base, key in targets:
        print(f"== {base}")
        problems = check_seat(base, key, want)
        if problems:
            failed += 1
            for p in problems:
                print(f"FAIL  {p}")
        else:
            print("ok    Reavion desktop and viewer")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
