# Seat image: where everything comes from

Read this before changing anything a customer sees on their machine: desktop, menu, dock, wallpaper, noVNC, or the driver.

## What Railway actually runs

Every seat (one Railway service per customer machine) is built **from this repo** (`helderperez-dev/cua-agent-desktop`) with [`Dockerfile.vendor`](../Dockerfile.vendor) (see [`railway.toml`](../railway.toml)). Railway redeploys **every seat** on each push to `main`.

`Dockerfile.vendor` is self-contained. It builds from the copies in `vendor/`, never from a registry:

| Layer | Built from | Source of truth |
|---|---|---|
| XFCE desktop: theme, panel, icons, wallpaper, GTK, fonts | `vendor/reavion-xfce` | **This repo.** Edit it here. |
| noVNC viewer: Reavion gate, control rail, logos | `vendor/reavion-xfce/vendor/reavion-vnc` | [`reavion-vnc`](../../reavion-vnc) repo |
| reavion-driver (MCP tools, Rust) | `vendor/reavion-driver/rust` | [`reavion-driver`](../../reavion-driver) repo |
| Chrome, Caddy, supergateway, supervisor programs | `image/` | This repo |

The registry images are **not** on the seat path today:

| Image | Built by | Used by seats? |
|---|---|---|
| `ghcr.io/helderperez-dev/reavion-desktop`, `docker.io/helderbuilds/reavion-desktop` | this repo's `release.yml` (XFCE rebuilt from `vendor/reavion-xfce`) | Only if the backend sets `MACHINE_SOURCE_IMAGE` (it is empty today) |
| `ghcr.io/helderperez-dev/reavion-xfce` | `reavion-images` `release-xfce.yml` from `images/xfce` | No. `release.yml` rebuilds XFCE from vendor instead |
| `ghcr.io/helderperez-dev/reavion-vnc`, `reavion-driver` | their repos | No. Seats compile from vendor |

Pushing `reavion-vnc` or `reavion-images` triggers the image cascade (vnc → xfce → desktop) on GitHub Actions. It only publishes images. **It does not change any seat.** Only a push to this repo does.

## Guard rails (keep them on)

| Guard | What it stops |
|---|---|
| `scripts/preflight.sh` | Theme version mismatch, broken shell scripts, hand-authored panel XML, Plank, Whisker type swap, missing watcher or Reavion icon, lost noVNC branding, vendor drift from `reavion-vnc` / `reavion-driver` |
| `.githooks/pre-push` (`git config core.hooksPath .githooks` once per clone) | Pushing when preflight fails |
| `.github/workflows/seat-checks.yml` | Same preflight in CI on every push and PR |
| Railway "wait for CI" (`checkSuites` on each seat's deploy trigger) | Seats rebuilding before the checks pass. The backend sets it on every machine it creates or wipes (`RailwayClient.require_passing_checks`) |
| Deploy trigger on every seat | A seat that never picks up a new image. Seats created through the API had none (the spare `jg4grp` was stuck on an old build); the backend now creates one |
| `scripts/verify-seat.py` | A deploy that "succeeded" but shows the stock desktop. Reads the real menu icon, theme version, watcher, dock position, and noVNC branding from each seat |

## Making a change

1. **Desktop:** edit `vendor/reavion-xfce`. **noVNC or driver:** edit the sibling repo, then copy it in:
   ```bash
   scripts/sync-vendor.sh          # copies ../reavion-vnc and ../reavion-driver into vendor/
   scripts/sync-vendor.sh --check  # exit 1 if a vendor copy drifted
   ```
2. Desktop change that must reach existing seats: bump the theme version in **all four** places (they must match):
   `THEME_VERSION` in `vendor/reavion-xfce/src/scripts/reavion-desktop-theme.sh`, and the `THEME_VERSION` printf in `Dockerfile`, `Dockerfile.vendor`, `vendor/reavion-xfce/Dockerfile`.
3. noVNC CSS or JS change: bump the `?v=` cache-buster in `reavion-vnc/index.html`, or browsers keep the old files.
4. Keep `reavion-images` in step: `scripts/sync-xfce.sh` publishes `vendor/reavion-xfce` **out** to `../reavion-images/images/xfce`. It never copies the other way.
5. Before pushing this repo, check nothing is running: every seat restarts, and any agent run or AI employee cycle on it is cut off.
   ```sql
   select status, count(*) from runs where status in ('queued','running','waiting_seat','waiting_user') group by status;
   select status, count(*) from employees where status in ('working','sleeping') group by status;
   ```
6. After the deploy, verify every seat (keys come from the backend, never commit them):
   ```bash
   SEATS='{"abc123": "MCP_KEY", ...}' python3 scripts/verify-seat.py --env
   ```
   It must print `ok` for each seat. Then open one and look: the Reavion mark next to **Applications**, the dock on the bottom edge, the Reavion tab on the left edge of noVNC.

## How the desktop gets branded at runtime

```
start-vnc.sh -> xstartup.sh
   1. reavion-desktop-theme.sh   seed configs (wallpaper, GTK, terminal, xsettings) before XFCE starts
   2. startxfce4 &
   3. reavion-desktop-theme.sh   display tweaks once X answers
   4. reavion-desktop-watch.sh & waits for xfce4-panel's own config, then brands the panel;
                                 on every screen resize restarts the panel so the dock follows
```

Rules learned the hard way:

- **Panel branding must wait for the panel.** Xvnc is already running when `xstartup.sh` starts, so step 3 used to run before xfce4-panel had written any config. It found no plugins and branded nothing, on every boot. The watcher (step 4) fixes this.
- **Brand the stock menu in place.** Set `button-icon=reavion-mark`, `button-title`, `show-button-title` on the `applicationsmenu` plugin. They apply live. Do not change the plugin type to `whiskermenu` from a script: the running panel writes its own config back and undoes it.
- **No hand-authored `xfce4-panel.xml`.** A full custom panel file (theme v4) broke the desktop and was removed in v5. Change live properties with `xfconf-query` instead.
- **No Plank.** It drew a giant grey bar over the VNC desktop.
- **noVNC resizes the session** to the browser (`resize=remote`). Panels placed before the resize stay at the old bottom edge (the "floating dock"). The watcher restarts the panel, detached with `setsid -f`, when the size changes.
- **The menu icon is a vector.** `assets/icons/hicolor/scalable/apps/reavion-mark.svg` (traced from the 323px PNG, centered, tight padding) plus PNGs rendered from it at 16 to 256px. The older PNGs were soft downscales with the mark off-center. To change the mark, edit the SVG and re-render the PNG sizes from it.
- noVNC defaults to JPEG quality 8. At 6, icons and small text looked blurry.
- `/home/reavion/.config/xfce4` is not on a volume (only Chrome's profile is), so each boot starts from the image, and the theme reapplies.

## noVNC

- Served by websockify from `/usr/share/reavion-vnc` behind Caddy. `/vnc.html` redirects to `index.html` (the Reavion single-page gate), keeping the hash so `#autoconnect=1&password=...` still works. The cloud app embeds `https://{seat}/vnc.html#...`.
- After connecting, the control rail tucks behind a handle on the left edge. The handle is styled in `app/styles/reavion.css` as a visible tab with the Reavion mark. Before 2026-11-03 it was a 15px dark strip, so the controls looked missing.

## History

| Date | Change |
|---|---|
| 2026-11-01 | Reavion noVNC gate, logos, remote resize (`reavion-vnc` a98e091, 7a520a5) |
| 2026-11-01 | Modern XFCE desktop baked in (5a45aa3); Plank dock and a custom panel with the Reavion mark (b41f9a6, theme v4) |
| 2026-11-01 | Custom panel and Plank broke the VNC desktop, removed (7a4ae36, v5). Whisker conversion added (5fd9149, v6), but it never applied (startup race above). From here on seats showed the stock XFCE menu icon |
| 2026-11-03 | Panel watcher, in-place menu branding, dock re-placed on resize, visible noVNC tab (e939f07, v8). `sync-xfce.sh` reversed so it can no longer overwrite the desktop. `reavion-images/images/xfce` brought up to date |

## Faster machine creation (optional)

Every seat today compiles the Rust driver during its own build. To create new machines faster, set `MACHINE_SOURCE_IMAGE=docker.io/helderbuilds/reavion-desktop:main` on the backend and worker. New machines then pull the CI-built image (public on Docker Hub). That image comes from the same `vendor/` copies, so the result is identical. Existing seats keep building from the repo until they are switched.
