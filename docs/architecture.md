# Architecture

## Overview

```text
Browser / MCP HTTP client
        │
        ▼
┌─ Edge (Caddy :$PORT) ──────────────────────────────────────┐
│  /vnc.html  → noVNC :6901                                  │
│  /mcp       → supergateway :8200                           │
│  /health    → ok                                           │
└────────────────────────────────────────────────────────────┘
        │                              │
        ▼                              ▼
┌─ Linux desktop container ──────────────────────────────────┐
│  XFCE on DISPLAY=:1                                        │
│  reavion-driver serve --socket … --grant existing-profile  │
│  Chrome profile → /home/reavion/.config/google-chrome          │
│  workspace → /home/reavion/workspace                           │
└────────────────────────────────────────────────────────────┘

Local optional path (stdio):
  MCP client → scripts/mcp-bridge.sh → docker exec → reavion-driver mcp
```

## Ownership

| Component | Owns |
|---|---|
| This project (`reavion-desktop`) | Image build, lifecycle, edge proxy, MCP HTTP gateway, Chrome + profile volume |
| Reavion Driver (`vendor/reavion-driver` ← `reavion-driver` repo) | Screenshots, clicks, typing, window discovery (MCP tools) |
| Base image (`trycua/xfce-cua`) | XFCE + noVNC stack |
| Supergateway | stdio MCP → Streamable HTTP |

Driver and VNC are orthogonal: both attach to the same X11 `DISPLAY=:1`.

## Agent path vs human viewer path

**Agent (remote):** MCP client → `https://…/mcp` (Bearer `MCP_API_KEY`) → Caddy → supergateway → `reavion-driver mcp` → unix socket → `reavion-driver serve` on `DISPLAY=:1`.

**Agent (local stdio):** MCP client → `scripts/mcp-bridge.sh` → `docker exec` → same `reavion-driver mcp`.

**Human:** Browser → `/vnc.html` → noVNC → same XFCE desktop. Password = `VNC_PW`.

## Security boundaries

- Local compose: viewer/MCP edge on `127.0.0.1` only.
- Railway: public HTTPS via Railway edge; require strong `VNC_PW` + `MCP_API_KEY`.
- Workspace / Chrome profile mounts are convenience, not a hostile multi-tenant sandbox.
- This repo is private because it vendors customized driver sources.
