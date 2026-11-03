#!/bin/bash
# Keep the Reavion desktop branded and laid out for the life of the session.
#
# 1. Wait until xfce4-panel has written its config, then apply the branding
#    (the pass in xstartup runs before the panel exists, so it finds nothing).
# 2. When the screen size changes (noVNC resizes the session to the browser),
#    restart the panel so the dock sits on the new bottom edge.
set -uo pipefail

THEME=/usr/local/bin/reavion-desktop-theme.sh

panel_ready() {
  pgrep -u "$(id -u)" -x xfce4-panel >/dev/null 2>&1 \
    && xfconf-query -c xfce4-panel -l 2>/dev/null | grep -q '^/plugins/plugin-[0-9]*$'
}

screen_size() {
  xrandr --current 2>/dev/null | sed -n 's/.*current \([0-9]*\) x \([0-9]*\).*/\1x\2/p' | head -n1
}

for _ in $(seq 1 90); do
  panel_ready && break
  sleep 1
done

restart_panel() {
  # Detached, so the restarted panel never belongs to this script's process group.
  setsid -f xfce4-panel -r >/dev/null 2>&1 || true
}

if panel_ready; then
  sleep 2
  # Menu icon, title and dock size are live xfconf properties: no restart needed.
  REAVION_PANEL_LIVE=1 "${THEME}" || true
fi

last="$(screen_size)"
while sleep 3; do
  now="$(screen_size)"
  if [[ -n "${now}" && "${now}" != "${last}" ]]; then
    last="${now}"
    # Let the resize settle, then re-place panels and reapply branding.
    sleep 1
    REAVION_PANEL_LIVE=1 "${THEME}" || true
    restart_panel
  fi
done
