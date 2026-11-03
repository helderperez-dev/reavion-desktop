# reavion-vnc

> **Reavion seats** serve a vendored copy of this repo. After a change: bump the `?v=` cache-buster in `index.html`, run `reavion-desktop/scripts/sync-vendor.sh`, and push `reavion-desktop`. Pushing this repo alone does not change any seat. See [reavion-desktop/docs/seat-image.md](../reavion-desktop/docs/seat-image.md).

Reavion’s HTML5 VNC viewer — private fork of [noVNC](https://github.com/novnc/noVNC) v1.5.0 (MPL-2.0).

Defaults tuned for Reavion seats: `resize=scale`, auto-reconnect. Served from seat images at `/vnc.html`.

## Build into images

Vendored into `reavion-images` as `vendor/reavion-vnc` and copied to `/usr/share/reavion-vnc` in `reavion/xfce`.

```bash
# from reavion-images
./scripts/sync-vnc.sh
./scripts/build.sh xfce
```

## Attribution

Upstream: noVNC Authors — see `LICENSE.txt` / `AUTHORS`.
