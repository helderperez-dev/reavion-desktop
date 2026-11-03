#!/usr/bin/env bash
# Copy the sibling source repos into vendor/, which is what seats are built from.
#
#   scripts/sync-vendor.sh          copy ../reavion-vnc and ../reavion-driver into vendor/
#   scripts/sync-vendor.sh --check  only report drift (exit 1 if any)
#
# Source of truth:
#   noVNC viewer   ../reavion-vnc               -> vendor/reavion-xfce/vendor/reavion-vnc
#   driver         ../reavion-driver/rust       -> vendor/reavion-driver/rust
#   XFCE desktop   vendor/reavion-xfce itself (edit it here; nothing upstream)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIBLINGS="$(cd "${ROOT}/.." && pwd)"
CHECK=0
[[ "${1:-}" == "--check" ]] && CHECK=1

VNC_EXCLUDES=(--exclude .git --exclude .github --exclude docs --exclude tests --exclude node_modules)
DRIVER_EXCLUDES=(--exclude .git --exclude target)

pairs=(
  "${SIBLINGS}/reavion-vnc/|${ROOT}/vendor/reavion-xfce/vendor/reavion-vnc/|vnc"
  "${SIBLINGS}/reavion-driver/rust/|${ROOT}/vendor/reavion-driver/rust/|driver"
)

drift=0
for pair in "${pairs[@]}"; do
  IFS='|' read -r src dst kind <<<"${pair}"
  if [[ ! -d "${src}" ]]; then
    echo "skip ${kind}: ${src} not found" >&2
    continue
  fi
  if [[ "${kind}" == "vnc" ]]; then ex=("${VNC_EXCLUDES[@]}"); else ex=("${DRIVER_EXCLUDES[@]}"); fi
  changes="$(rsync -a --delete --dry-run --itemize-changes "${ex[@]}" "${src}" "${dst}" | grep -v '^\.' || true)"
  if [[ -n "${changes}" ]]; then
    drift=1
    echo "== ${kind} differs from ${src}"
    echo "${changes}" | head -40
    if [[ "${CHECK}" == "0" ]]; then
      rsync -a --delete "${ex[@]}" "${src}" "${dst}"
      echo "   synced"
    fi
  else
    echo "== ${kind} in sync"
  fi
done

if [[ "${CHECK}" == "1" && "${drift}" == "1" ]]; then
  echo "Vendor copies drifted. Run scripts/sync-vendor.sh and commit." >&2
  exit 1
fi
