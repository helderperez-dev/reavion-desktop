# cua-agent-desktop

Isolated Linux desktop sandbox for AI agents: XFCE runs inside Docker, **Reavion Driver** exposes computer-use tools over MCP, and a human can watch or take over via **noVNC** in a browser.

Driver source is built from private [`reavion-driver`](https://github.com/helderperez-dev/reavion-driver) (vendored under `vendor/reavion-driver`). Desktop base remains `trycua/xfce-cua`. This seat image repo is **`helderperez-dev/cua-agent-desktop`** (private).

Locally you can use a stdio MCP bridge. For **Railway / remote**, the same container exposes **Streamable HTTP MCP** and noVNC behind Caddy on a single `$PORT`.

## Requirements

- Docker Desktop / Engine (or Podman with `CUA_RUNTIME=podman`)
- ~4 GB RAM reserved for the container (compose sets `mem_limit: 4g`)
- Sibling `reavion-driver` checkout when refreshing vendor (`./scripts/sync-driver.sh`)

## Quick start (local)

```bash
cp .env.example .env   # set VNC_PW (and optionally MCP_API_KEY)
./scripts/sync-driver.sh   # if vendor/ is missing or stale
./scripts/build.sh
./scripts/up.sh
open http://127.0.0.1:6080/vnc.html   # password = VNC_PW
```

- Viewer + MCP edge: `http://127.0.0.1:6080` (Caddy → noVNC + `/mcp`)
- Local stdio MCP: `scripts/mcp-bridge.sh` (Cursor project example in `.cursor/mcp.json.example`)

```bash
./scripts/status.sh
./scripts/down.sh   # keeps ./workspace and ./data/chrome-profile
```

Google Chrome is the default browser and **autostarts** on the XFCE session. Profile (cookies/logins) persists at `./data/chrome-profile`.

Boot contract for “Chrome opens + agent bind works”:

1. **system D-Bus** — Chrome 150+ SIGTRAPs (exit 133) without it; supervisord runs `dbus-system` before the session bus.
2. **`fix-chrome-profile`** — chowns the Railway/local profile volume to `reavion` and clears stale `Singleton*` locks after redeploy.
3. **Chrome wrapper** — `--force-renderer-accessibility`, `--no-sandbox` (expected under `cap_drop: ALL`), non-default `--user-data-dir=…/cdp-userdata` (Chrome ≥136 ignores remote debugging on the default profile path), and loopback `--remote-debugging-port=9222` so CDP listens at startup for `browser_prepare({strategy:{kind:"existing_profile"}})`.
4. **Driver** — `serve --grant existing-profile` so agents can attach without a separate consent host.

Driver and noVNC share `DISPLAY=:1`.

## Connect MCP

### Local stdio (Cursor / Claude / Codex)

Point the client at `scripts/mcp-bridge.sh` — see `.cursor/mcp.json.example` and `configs/*-mcp.example.*`.

### Remote HTTP (Railway or local edge)

```json
{
  "mcpServers": {
    "cua-desktop": {
      "url": "https://YOUR-SERVICE.up.railway.app/mcp",
      "headers": {
        "Authorization": "Bearer YOUR_MCP_API_KEY"
      }
    }
  }
}
```

Examples: `configs/cursor-mcp.remote.example.json`, `configs/claude-mcp.remote.example.json`, `configs/codex-mcp.remote.example.toml`.

Local edge equivalent: `http://127.0.0.1:6080/mcp` (set `MCP_API_KEY` in `.env`).

## Deploy on Railway

Changing the desktop, noVNC, or the driver? Read [docs/seat-image.md](docs/seat-image.md) first.

See **[docs/railway.md](docs/railway.md)**. Summary:

1. Deploy this repo (Dockerfile / `railway.toml`)
2. Set `VNC_PW`, `MCP_API_KEY`, `REQUIRE_MCP_API_KEY=1` (and optionally `VNC_RESOLUTION=1280x720`)
3. ≥4 GB memory; optional volumes for Chrome profile + workspace
4. Open `https://<domain>/vnc.html` and point MCP clients at `https://<domain>/mcp`

## Architecture

```text
Client (browser / MCP HTTP)
        │
        ▼
   Caddy :$PORT
     ├─ /vnc.html  → noVNC :6901
     └─ /mcp       → supergateway → reavion-driver mcp (unix socket)
```

More detail: [docs/architecture.md](docs/architecture.md).

## Security notes

- **Local compose** publishes **`127.0.0.1:6080` only**.
- **Railway** exposes the service publicly — use a strong `VNC_PW` and required `MCP_API_KEY`.
- Docker group ≈ host root; workspace/profile mounts are convenience, not multi-tenant isolation.
- Compose drops capabilities (`cap_drop: ALL`) and adds `SETUID` / `SETGID`. No `--privileged`, no Docker socket mount.

## Troubleshooting

| Symptom | What to try |
|---|---|
| Container / socket not ready | `./scripts/status.sh`; `docker exec cua-agent-desktop supervisorctl status` |
| `/health` fails | Wait for Caddy; check `edge-proxy` logs |
| MCP HTTP 401 | Set matching `MCP_API_KEY` / Bearer header |
| VNC password rejected | `VNC_PW` in `.env` / Railway vars; recreate container after change |
| Desk looks cropped / huge on phone | Confirm noVNC `resize=scale`; set `VNC_RESOLUTION=1280x720` and **redeploy** (geometry is fixed at VNC start) |
| Local stdio bridge fails | Container running + socket ready; use absolute path in mcp.json |

## License / attribution

- This harness: [MIT](LICENSE).
- Reavion Driver: `helderperez-dev/reavion-driver` (MIT-derived; see `vendor/reavion-driver/NOTICE`)
- Desktop base: `trycua/xfce-cua` — [trycua](https://github.com/trycua/cua)
- noVNC is bundled in the base image; [supergateway](https://github.com/supercorp-ai/supergateway) bridges stdio MCP to HTTP.
