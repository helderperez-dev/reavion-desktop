# Build prompt: Cua desktop sandbox + MCP + noVNC

Copy this entire file into a **new empty project folder** and give it to an AI coding agent (Cursor, Claude Code, Codex, etc.) as the sole build instruction.

---

## Mission

Build a small, self-contained project that gives AI agents an **isolated Linux desktop** they control through an **MCP server**, while a human can watch / take over via **noVNC** in a browser.

This is the Local VM pattern used by OpenMausBot, stripped of chat UI, Boat cloud, Electron, browser-proxy, leases, and multi-bot orchestration.

**Do not** control the host Mac/Windows desktop. **Do** run everything inside Docker/Podman.

---

## Non-goals

- No Electron app, no chat UI, no multi-bot roster
- No Boat / ascii.dev / cloud VMs
- No host Accessibility / TCC computer-use (that is a different product)
- No reimplementation of click/type/screenshot tools — Cua Driver owns those
- No binding the VNC port to `0.0.0.0` (loopback only)

---

## Architecture (must match)

```text
Cursor / Claude Code / Codex / any MCP client
        │  stdio MCP
        ▼
  host bridge script  (docker|podman exec -i …)
        │
        ▼
┌─ Linux container ──────────────────────────────────┐
│  XFCE desktop on DISPLAY=:1                        │
│  cua-driver serve --socket /run/user/1000/cua.sock │
│  noVNC / websockify on guest :6901                 │
│  workspace bind-mount → /home/cua/workspace        │
└────────────────────────────────────────────────────┘
        ▲
   human opens http://127.0.0.1:6080/vnc.html
```

Ownership split (copy this into the README):

| Component | Owns |
|---|---|
| This project | Image build, container lifecycle, loopback viewer publish, MCP bridge |
| Cua Driver | Screenshots, clicks, typing, window discovery (MCP tools) |
| Base image | XFCE + noVNC stack |

---

## Reference facts (from OpenMausBot Local VM)

Use these as a proven starting point. Prefer pinning digests/versions; bump deliberately.

| Item | Value |
|---|---|
| Base image | `docker.io/trycua/xfce-cua@sha256:274eb636f5cf3fc58f705916ee72b7a701270b3877369d08533a385c5325be9b` |
| Cua driver version (reference) | `0.20.0` (verify current PyPI / cua.ai before pinning) |
| Guest user | `cua` (uid 1000) |
| Display | `:1` |
| Driver socket | `/run/user/1000/cua.sock` (or `/run/user/1000/openmausbot-cua.sock`) |
| Driver binary (after install) | e.g. `/usr/local/libexec/cua-desktop/cua-driver` |
| Guest noVNC port | `6901` |
| Host publish | `127.0.0.1:6080:6901` |
| Workspace guest path | `/home/cua/workspace` |
| Env for VNC password | `VNC_PW` |

Upstream alternatives (acceptable if documented):

- Image `trycua/cua-ubuntu` with KasmVNC (~`localhost:8006`) — see https://cua.ai/blog/ubuntu-docker-support
- Host MCP registration helpers: `cua-driver mcp-config --client cursor` — see https://cua.ai/docs/cua-driver/guides/connect-your-agent

Prefer the **xfce-cua + noVNC on :6901** path so the viewer matches OpenMausBot’s Local VM.

Official Cua MCP docs: https://cua.ai/docs/cua-driver/quickstart

---

## Deliverables (create all of these)

```text
.
├── README.md
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── .gitignore
├── scripts/
│   ├── build.sh
│   ├── up.sh
│   ├── down.sh
│   ├── status.sh
│   └── mcp-bridge.sh          # or mcp-bridge.mjs
├── .cursor/
│   └── mcp.json.example
├── configs/
│   ├── claude-mcp.example.json
│   └── codex-mcp.example.toml
└── docs/
    └── architecture.md
```

Optional later (not required for v1): Node TypeScript bridge, control-gate “human driving” pause, idle stop timer.

---

## Implementation requirements

### 1. Dockerfile

- `FROM` the pinned `trycua/xfce-cua` digest above (multi-arch amd64 + arm64).
- Install a pinned `cua-driver` Linux wheel (SHA-256 verified) into the image.
- Install the binary to a fixed path; `cua-driver --version` must match the pin at build time.
- Start `cua-driver serve --socket … --permission-mode standard` under the existing supervisor (or equivalent) **as user `cua`**, with `HOME=/home/cua` and `DISPLAY=:1`.
- Wait until `DISPLAY=:1` is ready (`xset q`) before starting the driver.
- Do **not** reimplement noVNC — use what the base image already provides on `:6901`.
- Labels: managed flag, driver version, base digest.

Sketch (adapt; do not invent unverified wheel URLs — look up the current manylinux wheel + sha256 for the chosen version):

```dockerfile
FROM docker.io/trycua/xfce-cua@sha256:274eb636f5cf3fc58f705916ee72b7a701270b3877369d08533a385c5325be9b
USER root
# 1) Download + sha256sum -c the cua_driver wheel for $arch
# 2) pip install --force-reinstall --no-deps into /opt/venv
# 3) install binary to /usr/local/libexec/cua-desktop/cua-driver
# 4) supervisor program: wait for DISPLAY=:1, then:
#    cua-driver serve --socket /run/user/1000/cua.sock --permission-mode standard
#    as user cua, env HOME=/home/cua DISPLAY=:1
```

### 2. docker-compose.yml

```yaml
services:
  desktop:
    build: .
    image: localhost/reavion-desktop:local
    container_name: reavion-desktop
    mem_limit: 4g
    cpus: 2
    shm_size: 512m
    environment:
      VNC_PW: ${VNC_PW:-changeme}
    ports:
      - "127.0.0.1:6080:6901"
    volumes:
      - ./workspace:/home/cua/workspace
    # Prefer hardening when the runtime allows it:
    # cap_drop: [ALL]
    # cap_add: [SETUID, SETGID]  # + SYS_CHROOT on Podman if Firefox sandbox needs it
    # ipc: private
    # cgroup: private  # if supported
    restart: unless-stopped
```

Hardening rules:

- Publish **only** `127.0.0.1`, never all interfaces
- No Docker socket mount into the container
- Workspace is a bind mount; document that this is not a multi-tenant security boundary

### 3. MCP bridge (`scripts/mcp-bridge.sh`)

Purpose: what Cursor / Claude / Codex launches. It must **not** define tools. It only `exec`s into the container’s Cua MCP server.

```bash
#!/usr/bin/env bash
set -euo pipefail
RUNTIME="${CUA_RUNTIME:-docker}"          # docker | podman
CONTAINER="${REAVION_CONTAINER:-reavion-desktop}"
SOCKET="${CUA_SOCKET:-/run/user/1000/cua.sock}"
DRIVER="${CUA_DRIVER:-/usr/local/libexec/cua-desktop/cua-driver}"

exec "$RUNTIME" exec -i \
  -u cua \
  -e HOME=/home/cua \
  -e DISPLAY=:1 \
  -e CUA_DRIVER_RS_TELEMETRY_ENABLED=0 \
  "$CONTAINER" \
  "$DRIVER" mcp --socket "$SOCKET"
```

Make it executable. Fail fast with a clear message if the container is not running.

### 4. Cursor MCP config example

`.cursor/mcp.json.example`:

```json
{
  "mcpServers": {
    "cua-desktop": {
      "command": "/ABSOLUTE/PATH/TO/repo/scripts/mcp-bridge.sh",
      "args": []
    }
  }
}
```

Document: copy to `.cursor/mcp.json` or `~/.cursor/mcp.json`, replace the absolute path, restart Cursor.

Also provide Claude Code / Codex example configs that point at the same bridge.

### 5. Lifecycle scripts

| Script | Behavior |
|---|---|
| `build.sh` | `docker compose build` (or podman) |
| `up.sh` | ensure `./workspace` exists (mode 0700), `compose up -d`, wait until Cua socket is ready (poll `docker exec … test -S socket` up to ~90s), print viewer URL |
| `down.sh` | `compose down` (keep workspace volume/dir) |
| `status.sh` | running?, image labels, viewer port, socket exists?, driver version |

### 6. README.md (user-facing)

Must include:

1. What this is (one paragraph)
2. Requirements: Docker Desktop / Engine or Podman; 4GB+ RAM for the container
3. Quick start:
   ```bash
   cp .env.example .env   # set VNC_PW
   ./scripts/build.sh
   ./scripts/up.sh
   open http://127.0.0.1:6080/vnc.html   # password = VNC_PW
   # point Cursor at scripts/mcp-bridge.sh via mcp.json
   ```
4. How agents use it (MCP tools come from Cua; ask the agent to open a browser inside the desktop and navigate)
5. Security notes (loopback-only, Docker group ≈ root, workspace bind mount)
6. Troubleshooting: container not ready, socket missing, wrong arch, VNC password, MCP client not picking up config

### 7. docs/architecture.md

Short diagram + the ownership table above + “agent path vs human viewer path”.

---

## Acceptance criteria (agent must verify)

1. `./scripts/build.sh` succeeds on the developer’s machine (or documents why Docker isn’t available).
2. `./scripts/up.sh` leaves a running container; `./scripts/status.sh` reports socket ready.
3. Browser can open `http://127.0.0.1:6080/vnc.html` and see the XFCE desktop (with `VNC_PW`).
4. Running the MCP bridge with a trivial MCP `initialize` / `tools/list` (or documenting the exact `npx @modelcontextprotocol/inspector` command) shows Cua computer-use tools — **not** an empty tool list.
5. README alone is enough for a new user to connect Cursor.
6. No secrets committed; `.env` is gitignored; `.env.example` has placeholders.
7. Ports never published on `0.0.0.0`.

---

## Security checklist (must follow)

- [ ] Viewer bound to `127.0.0.1` only
- [ ] Strong default guidance for `VNC_PW` (reject empty / `changeme` in production notes)
- [ ] No `--privileged`
- [ ] CapDrop ALL where possible; only add caps the desktop/Firefox sandbox needs
- [ ] Do not mount the host Docker socket into the guest
- [ ] Document: anyone in the Docker group can root the host
- [ ] Workspace bind mount is convenience, not a hostile multi-tenant sandbox

---

## Suggested build order for the coding agent

1. Create repo skeleton + `.gitignore` + `.env.example`
2. Write `Dockerfile` and build once
3. Write `docker-compose.yml` + `up`/`down`/`status`
4. Confirm noVNC viewer works manually
5. Confirm `cua-driver serve` socket exists inside the container
6. Write `mcp-bridge.sh` and prove `tools/list` works
7. Add Cursor / Claude / Codex example MCP configs
8. Write README + architecture doc
9. Run through acceptance criteria and fix gaps

---

## Prompt to paste into the other project’s agent

Use the block below as the user message in the new folder:

```text
Read BUILD-PROMPT.md (or the file you were given) end-to-end and implement the project it describes.

Build a Docker-based Linux desktop sandbox for AI agents:
- Base: pinned trycua/xfce-cua
- Inside: cua-driver serve on a unix socket + existing noVNC on :6901
- Host: loopback publish 127.0.0.1:6080:6901
- Host MCP bridge: docker/podman exec → cua-driver mcp --socket …
- Human viewer: browser → noVNC
- Agent control: Cursor/Claude/Codex via MCP only

Follow the architecture, deliverables, hardening rules, and acceptance criteria exactly.
Do not add Electron, chat UI, cloud VMs, or host-desktop control.
Prefer small shell scripts over a large framework.
When versions/wheel URLs need pinning, look up current authentic cua-driver Linux wheels and record SHA-256s in the Dockerfile.
After implementing, run build + up + status, and document any step you could not verify on this machine.
```

---

## Optional v2 (only if asked after v1 works)

- Control gate: when human opens the viewer, MCP tools return “human is driving”
- Idle timeout that stops the container but keeps `./workspace`
- Per-project named containers / multiple seats
- Packaged `@novnc/novnc` app page that proxies RFB through an authenticated local gateway (OpenMausBot’s DesktopViewer pattern) instead of exposing the container’s `vnc.html` directly
- Podman rootless + `keep-id` userns for workspace ownership on Linux/macOS

---

## License / attribution notes for README

- Cua Driver and `trycua/xfce-cua` are upstream projects (trycua / cua.ai) — link and respect their licenses
- noVNC is typically bundled in the base image — retain notices if you redistribute
- This harness project can be MIT/Apache-2.0 (choose one and state it)

---

*Generated as a portable build brief from an OpenMausBot Local VM architecture review. It is not affiliated with OpenMausBot or trycua; it only describes a minimal reproducible pattern.*
