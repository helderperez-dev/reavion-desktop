#!/usr/bin/env bash
# vendor/reavion-xfce in THIS repo is the source of truth for the seat desktop
# (theme script, panel watcher, icons, wallpaper, GTK, noVNC copy).
#
# This script publishes it OUT to ../reavion-images/images/xfce so the
# reavion-xfce GHCR image matches. It never copies the other way: an older
# version of this script did, and would have wiped the Reavion customizations.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/vendor/reavion-xfce"
DEST="${REAVION_IMAGES_SRC:-$ROOT/../reavion-images}/images/xfce"
if [ ! -d "$(dirname "$DEST")" ]; then
  echo "ERROR: reavion-images not found next to this repo ($DEST)" >&2
  exit 1
fi
mkdir -p "$DEST"
rsync -a --delete --exclude '.git/' "$SRC/" "$DEST/"
echo "Published $SRC -> $DEST ($(du -sh "$DEST" | awk '{print $1}'))"
