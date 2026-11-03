#!/bin/bash
# Keep the Reavion desktop branded and laid out for the life of the session.
#
# 1. Wait until xfce4-panel has written its config, then apply the branding
#    (the pass in xstartup runs before the panel exists, so it finds nothing).
# 2. When the screen size changes (noVNC resizes the session to the browser),
#    re-place the panel so the dock sits on the new bottom edge.
#
# Never call `xfce4-panel -r` here: when the panel is mid-restart or not on the
# bus it pops up a "Failed to restart the panel" dialog on the customer's screen.
# Restart over D-Bus instead (errors stay in the log), only once the size has
# settled, and no more than once every MIN_GAP seconds.
set -uo pipefail

THEME=/usr/local/bin/reavion-desktop-theme.sh
MIN_GAP=10

log() { echo "reavion-desktop-watch: $*"; }

panel_on_bus() {
  dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.NameHasOwner string:org.xfce.Panel 2>/dev/null | grep -q 'boolean true'
}

panel_ready() {
  panel_on_bus && xfconf-query -c xfce4-panel -l 2>/dev/null | grep -q '^/plugins/plugin-[0-9]*$'
}

screen_size() {
  xrandr --current 2>/dev/null | sed -n 's/.*current \([0-9]*\) x \([0-9]*\).*/\1x\2/p' | head -n1
}

last_restart=0
replace_panel() {
  local now
  now=$(date +%s)
  if (( now - last_restart < MIN_GAP )); then
    return
  fi
  last_restart=${now}
  if panel_on_bus; then
    dbus-send --session --type=method_call --dest=org.xfce.Panel /org/xfce/Panel \
      org.xfce.Panel.Terminate boolean:true 2>/dev/null || log "panel restart call failed"
  elif ! pgrep -u "$(id -u)" -x xfce4-panel >/dev/null 2>&1; then
    # No panel at all: start one (detached) instead of asking a missing one to restart.
    log "panel not running; starting it"
    setsid -f xfce4-panel >/dev/null 2>&1 || true
  fi
}

for _ in $(seq 1 90); do
  panel_ready && break
  sleep 1
done

if panel_ready; then
  sleep 2
  # Menu icon, title and dock size are live xfconf properties: no restart needed.
  REAVION_PANEL_LIVE=1 "${THEME}" || true
  log "branding applied"
fi

last="$(screen_size)"
while sleep 2; do
  now="$(screen_size)"
  [[ -z "${now}" || "${now}" == "${last}" ]] && continue
  # A browser resize arrives as several sizes in a row: wait until it holds still.
  while sleep 2; do
    settled="$(screen_size)"
    [[ "${settled}" == "${now}" ]] && break
    now="${settled}"
  done
  last="${now}"
  log "screen is now ${now}; re-placing the panel"
  replace_panel
  # Give the restarted panel time to come back before re-applying branding.
  for _ in $(seq 1 10); do
    panel_ready && break
    sleep 1
  done
  REAVION_PANEL_LIVE=1 "${THEME}" || true
done
