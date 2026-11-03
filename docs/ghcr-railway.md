# Seat images: Docker Hub pull vs scratch build

> Start with [seat-image.md](seat-image.md): which copy each seat layer is built from, how to ship a desktop change, and what broke before.

## Toggle (control plane)

One env var on `reavion-app-backend`:

| Mode | `MACHINE_SOURCE_IMAGE` | What Railway does |
|---|---|---|
| **Scratch (default)** | empty | Clone `MACHINE_SOURCE_REPO` and build `Dockerfile.vendor` |
| **Fast** | `docker.io/<hub-user>/reavion-desktop:main` | Pull public Hub image (no build) |

**Use scratch by default.** Hub-image seats have been observed with `reavion-driver` FATAL and `/mcp` 502 while vendor-built seats (`r3mrem`) work. Only enable Fast after `/mcp` initialize succeeds on a Hub-deployed seat.

Switching modes: change the variable, redeploy the backend, then provision new seats. Existing seats keep their current source until recreated (or reconnect + redeploy).

**Volume:** mount `/home/reavion/.config/google-chrome` only. Do **not** mount `/home/reavion` — an empty volume hides image skel/XDG config.

## Docker Hub publish (Hobby-friendly)

Seat release workflow ([`.github/workflows/release.yml`](../.github/workflows/release.yml)) pushes to GHCR and, when secrets are set, also to Docker Hub:

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | Hub namespace (e.g. `helderbuilds`) |
| `DOCKERHUB_TOKEN` | Hub access token with read/write |

Published tags: `main` / version tag, `latest`, `sha-<12>`.

Keep the Hub repo **public** so Railway Hobby can pull without registry credentials.

Control plane production (reliable path):

```env
MACHINE_SOURCE_IMAGE=
MACHINE_SOURCE_REPO=helderperez-dev/cua-agent-desktop
MACHINE_VOLUME_MOUNTS=/home/reavion/.config/google-chrome
```

## GHCR (CI / cascade)

GHCR remains the cascade registry for `reavion-xfce`, `reavion-driver`, `reavion-vnc`, and internal desktop tags. Private GHCR pulls on Railway need **Pro** registry credentials or public packages — prefer public Docker Hub for seat deploys on Hobby.

### Optional: make GHCR packages public

For each of `reavion-desktop`, `reavion-xfce`, `reavion-driver`, `reavion-vnc`:

Package settings → Danger Zone → Change visibility → **Public**

### Optional: Railway private registry (Pro)

| Field | Value |
|---|---|
| Host | `ghcr.io` |
| Username | `helderperez-dev` |
| Password | GitHub PAT with `read:packages` |

## Scratch path notes

- Repo `cua-agent-desktop` must be cloneable by Railway (public, or connected GitHub App).
- Control plane sets `dockerfilePath=Dockerfile.vendor` after create when image is empty.
- Repo [`railway.toml`](../railway.toml) also pins `dockerfilePath = "Dockerfile.vendor"`.

## Volume remount

1. Put `RAILWAY_API_TOKEN=...` in `reavion-app-backend/.env`.
2. Dry-run: `cd reavion-app-backend && python scripts/migrate_volume_mounts.py`
3. Apply: `python scripts/migrate_volume_mounts.py --apply`  
   **Warning:** recreate mounts are empty — copy Chrome profile out first if you need cookies.
4. Redeploy seats after remount.
