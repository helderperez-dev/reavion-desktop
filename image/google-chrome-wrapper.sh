#!/usr/bin/env bash
# Launch Google Chrome with flags needed inside this hardened agent seat.
set -euo pipefail

REAL="${CHROME_REAL:-/usr/bin/google-chrome-stable.real}"
if [ ! -x "$REAL" ]; then
  # Fallback if package layout differs
  for candidate in /opt/google/chrome/chrome /usr/bin/google-chrome-stable; do
    if [ -x "$candidate" ] && [ "$candidate" != "$(readlink -f "$0" 2>/dev/null || true)" ]; then
      REAL="$candidate"
      break
    fi
  done
fi

# Chrome/Chromium 150+ SIGTRAPs (exit 133) if the system bus is missing.
# Supervisord starts dbus-system first; wait briefly for late boots.
for _ in $(seq 1 50); do
  if [ -S /run/dbus/system_bus_socket ] || [ -S /var/run/dbus/system_bus_socket ]; then
    break
  fi
  sleep 0.1
done

# Match the VNC framebuffer EXACTLY — agents click in native coordinates.
# Do not shrink for the panel; --start-maximized fills the usable work area.
IFS=x read -r _chrome_w _chrome_h <<EOF
${VNC_RESOLUTION:-1280x720}
EOF
_chrome_w="${_chrome_w:-1280}"
_chrome_h="${_chrome_h:-720}"

# Chrome ≥136 ignores --remote-debugging-port on the default user-data-dir
# (~/.config/google-chrome). Use a nested non-default dir on the same volume so
# DevTools listens at startup for browser_prepare(existing_profile).
HOME_DIR="${HOME:-/home/reavion}"
VOLUME_ROOT="${CHROME_PROFILE_DIR:-${HOME_DIR}/.config/google-chrome}"
USER_DATA="${CHROME_USER_DATA_DIR:-${VOLUME_ROOT}/cdp-userdata}"
mkdir -p "$USER_DATA"

# Seat restarts (deploys) kill Chrome, so on the next start it shows "Restore pages?
# Chrome didn't shut down correctly" over the page the agent works on. Before a
# fresh start (never while Chrome runs), mark the last session as a clean exit.
if ! pgrep -u "$(id -u)" -f -- "--user-data-dir=${USER_DATA}" >/dev/null 2>&1; then
  for prefs in "$USER_DATA"/*/Preferences; do
    [ -f "$prefs" ] || continue
    sed -i -e 's/"exit_type":"Crashed"/"exit_type":"Normal"/g' \
           -e 's/"exited_cleanly":false/"exited_cleanly":true/g' "$prefs" 2>/dev/null || true
  done
fi

# --force-renderer-accessibility: required by reavion-driver on Linux for exact
# browser bind + semantic snapshots.
# --no-sandbox: needed under cap_drop ALL; its warning bar is hidden by the managed policy (chrome-policies.json).
# --remote-debugging-port: loopback only — not published outside the container.
exec "$REAL" \
  --user-data-dir="$USER_DATA" \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --no-first-run \
  --no-default-browser-check \
  --hide-crash-restore-bubble \
  --password-store=basic \
  --force-renderer-accessibility \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port=9222 \
  --remote-allow-origins=* \
  --start-maximized \
  --window-size="${_chrome_w},${_chrome_h}" \
  --window-position=0,0 \
  --force-device-scale-factor=1 \
  --high-dpi-support=1 \
  "$@"
