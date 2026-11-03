#!/usr/bin/env bash
# Checks that must pass before a push to this repo (every push redeploys all seats).
# Runs locally and in CI (.github/workflows/seat-checks.yml).
#
#   scripts/preflight.sh            all checks, siblings expected at ../reavion-vnc, ../reavion-driver
#   SKIP_VENDOR_DRIFT=1 scripts/preflight.sh   skip the sibling drift check
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"
fail=0
ok()   { echo "ok    $*"; }
bad()  { echo "FAIL  $*"; fail=1; }

# 1. Theme version: the script and the three Dockerfiles must agree, or seats keep stale config.
script_v="$(sed -n 's/^THEME_VERSION="\([0-9]*\)".*/\1/p' vendor/reavion-xfce/src/scripts/reavion-desktop-theme.sh)"
versions="${script_v}"
for f in Dockerfile Dockerfile.vendor vendor/reavion-xfce/Dockerfile; do
  v="$(grep -o "printf '[0-9]*\\\\n' > /usr/share/reavion-desktop/THEME_VERSION" "$f" | grep -o "[0-9]\+" | head -n1)"
  versions="${versions} ${v:-missing}"
  [[ "${v}" == "${script_v}" ]] || bad "THEME_VERSION in $f is '${v:-missing}', theme script says '${script_v}'"
done
[[ "${fail}" == "0" ]] && ok "theme version ${script_v} everywhere"

# 2. Shell scripts parse.
for f in vendor/reavion-xfce/src/scripts/*.sh image/*.sh scripts/*.sh; do
  bash -n "$f" 2>/dev/null || bad "syntax error in $f"
done
ok "shell scripts parse"

# 3. Known-bad desktop patterns (see docs/seat-image.md, "Rules learned the hard way").
if find vendor/reavion-xfce -name 'xfce4-panel.xml' | grep -q .; then
  bad "hand-authored xfce4-panel.xml in vendor/reavion-xfce (broke the desktop in theme v4)"
fi
if grep -rqs "plank" vendor/reavion-xfce/src/desktop-skel vendor/reavion-xfce/src/xfce; then
  bad "Plank config in the desktop skeleton (drew a grey bar over the desktop)"
fi
if grep -q -- '-s "whiskermenu"' vendor/reavion-xfce/src/scripts/reavion-desktop-theme.sh; then
  bad "theme script swaps the menu plugin type (the running panel reverts it)"
fi
if grep -rnsE "xfce4-panel +(-r|--restart)" vendor/reavion-xfce/src image | grep -vqE '^[^:]+:[0-9]+: *#'; then
  bad "a seat script runs 'xfce4-panel -r' (pops a 'Failed to restart the panel' dialog); restart over D-Bus"
fi
grep -q "reavion-desktop-watch.sh" vendor/reavion-xfce/src/scripts/xstartup.sh \
  || bad "xstartup.sh no longer starts reavion-desktop-watch.sh (panel branding will not apply)"
grep -q 'button-icon" -n -t string -s "reavion-mark"' vendor/reavion-xfce/src/scripts/reavion-desktop-theme.sh \
  || bad "theme script no longer sets the Reavion menu icon"
[[ -f vendor/reavion-xfce/assets/icons/hicolor/32x32/apps/reavion-mark.png ]] || bad "reavion-mark icon missing"
[[ -f vendor/reavion-xfce/assets/icons/hicolor/scalable/apps/reavion-mark.svg ]] \
  || bad "scalable reavion-mark.svg missing (panel icon renders blurry from PNG only)"
ok "desktop rules"

# 4. noVNC: Reavion gate, handle tab, cache-buster.
vnc=vendor/reavion-xfce/vendor/reavion-vnc
grep -q 'location.replace("index.html"' "${vnc}/vnc.html" || bad "vnc.html no longer forwards to the Reavion gate"
grep -q "reavion-mark-white.png" "${vnc}/app/styles/reavion.css" || bad "control rail handle lost the Reavion mark"
grep -q 'reavion.css?v=' "${vnc}/index.html" || bad "index.html lost the ?v= cache-buster"
ok "noVNC branding"

# 5. Vendor copies match the sibling repos.
if [[ "${SKIP_VENDOR_DRIFT:-0}" != "1" ]]; then
  if scripts/sync-vendor.sh --check >/tmp/reavion-vendor-check.txt 2>&1; then
    ok "vendor copies match reavion-vnc and reavion-driver"
  else
    cat /tmp/reavion-vendor-check.txt
    bad "vendor copies drifted (run scripts/sync-vendor.sh)"
  fi
fi

if [[ "${fail}" != "0" ]]; then
  echo "Preflight failed. Do not push: every push redeploys all customer seats."
  exit 1
fi
echo "Preflight passed."
