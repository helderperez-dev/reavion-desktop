# Deploy on Railway

One service runs the full stack: XFCE desktop, Reavion Driver, noVNC, and a **remote MCP** gateway (Streamable HTTP — not stdio). Caddy listens on Railway’s `$PORT` and routes:

| Path | Backend |
|---|---|
| `/` / `/vnc.html` | noVNC desktop viewer |
| `/mcp` | MCP Streamable HTTP (supergateway → `reavion-driver mcp`) |
| `/health` | liveness (`ok`) |

## 1. Create the service

**Today:** `MACHINE_SOURCE_IMAGE` is empty, so every seat is built from this repo with `Dockerfile.vendor` (see [seat-image.md](seat-image.md)). **Optional fast path:** set `MACHINE_SOURCE_IMAGE=docker.io/helderbuilds/reavion-desktop:main` (public, CI-built from the same vendor copies) so new seats skip the Rust compile.

**Fallback:** Deploy from GitHub (**private** `helderperez-dev/reavion-desktop`) with `Dockerfile.vendor` (compiles `vendor/reavion-driver`).

1. Generate a public domain; target port **8080** (or whatever `$PORT` Railway assigns — the app reads `PORT`).
2. Control plane `MACHINE_SOURCE_REPO` stays `helderperez-dev/reavion-desktop` when not using the GHCR image.

### Volume path migration (`cua` → `reavion`)

Existing seats that mounted `/home/cua/...` must be updated **once** when rolling images that use user `reavion` (UID still `1000`):

| Old mount | New mount |
|---|---|
| `/home/cua/.config/google-chrome` | `/home/reavion/.config/google-chrome` |
| `/home/cua/workspace` | `/home/reavion/workspace` |

Update Railway volume mount paths (and `MACHINE_VOLUME_MOUNTS` on the control plane) before or together with the image cutover so Chrome profile / workspace data keep attaching.

## 2. Required variables

| Variable | Notes |
|---|---|
| `VNC_PW` | Strong password for noVNC (not `changeme`) |
| `MCP_API_KEY` | Long random secret; clients send `Authorization: Bearer <key>` |
| `REQUIRE_MCP_API_KEY` | Set to `1` on Railway |
| `PORT` | Set by Railway automatically |

Optional:

| Variable | Default | Notes |
|---|---|---|
| `MCP_GATEWAY_PORT` | `8200` | Internal only |
| `VNC_RESOLUTION` | `1280x720` | TigerVNC `-geometry`. Set in Railway and **redeploy** — changing it on a running container does nothing. Prefer 16:9 (`1280x720`) so phone noVNC (`resize=scale`) shows the full desk without crop. |
| `VNC_COL_DEPTH` | `24` | Color depth for the VNC server |

## 3. Resources

- Memory: **≥ 4 GB** (XFCE + Chrome)
- Persistent volumes (recommended):
  - mount → `/home/reavion/.config/google-chrome` (cookies / profile)
  - mount → `/home/reavion/workspace` (shared files)

## 4. Connect the viewer

Open:

`https://<your-railway-domain>/vnc.html`

Password = `VNC_PW`.

## 5. Connect MCP remotely (Cursor / Claude / Codex)

Use Streamable HTTP (not the local stdio bridge):

```json
{
  "mcpServers": {
    "cua-desktop": {
      "url": "https://<your-railway-domain>/mcp",
      "headers": {
        "Authorization": "Bearer <MCP_API_KEY>"
      }
    }
  }
}
```

Example files:

- [`configs/cursor-mcp.remote.example.json`](../configs/cursor-mcp.remote.example.json)
- [`configs/claude-mcp.remote.example.json`](../configs/claude-mcp.remote.example.json)

## 6. Security

- Anyone with the public URL can reach the viewer path; protect with a strong `VNC_PW`.
- MCP requires `MCP_API_KEY` when `REQUIRE_MCP_API_KEY=1` or `RAILWAY_ENVIRONMENT` is set.
- This is a full desktop in the cloud — treat it like a privileged workstation, not a multi-tenant sandbox.
