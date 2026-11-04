#!/bin/bash
# Keep the Reavion desktop branded and laid out for the life of the session.
#
# 1. Wait until xfce4-panel has written its config, then apply the branding
#    (the pass in xstartup runs before the panel exists, so it finds nothing).
# 2. When the screen size changes (noVNC resizes the session to the browser),
#    re-place the panel so the dock sits on the new bottom edge, and fit windows
#    that are now wider or taller than the screen back inside it.
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
  local now wait_for
  now=$(date +%s)
  # Never drop a change: wait out the rest of the gap instead, so the panel always comes back.
  wait_for=$(( MIN_GAP - (now - last_restart) ))
  if (( wait_for > 0 )); then
    sleep "${wait_for}"
  fi
  last_restart=$(date +%s)
  if panel_on_bus; then
    dbus-send --session --type=method_call --dest=org.xfce.Panel /org/xfce/Panel \
      org.xfce.Panel.Terminate boolean:true 2>/dev/null || log "panel restart call failed"
  elif ! pgrep -u "$(id -u)" -x xfce4-panel >/dev/null 2>&1; then
    # No panel at all: start one (detached) instead of asking a missing one to restart.
    log "panel not running; starting it"
    setsid -f xfce4-panel >/dev/null 2>&1 || true
  fi
}

# Windows left wider or taller than a smaller screen (the browser running past the edge) are
# fitted back inside it. Sticky windows (desktop, panels) are skipped.
fit_windows() {
  command -v wmctrl >/dev/null 2>&1 || return 0
  local sw sh
  IFS=x read -r sw sh <<<"$(screen_size)"
  [[ -z "${sw}" || -z "${sh}" ]] && return 0
  wmctrl -l -G 2>/dev/null | while read -r id desk x y w h _; do
    [[ "${desk}" == "-1" ]] && continue
    if (( w > sw || h > sh || x + w > sw || y + h > sh )); then
      local nw=$(( w > sw ? sw : w )) nh=$(( h > sh - 40 ? sh - 40 : h ))
      local nx=$(( x + nw > sw ? sw - nw : x )) ny=$(( y + nh > sh ? sh - nh : y ))
      (( nx < 0 )) && nx=0
      (( ny < 0 )) && ny=0
      wmctrl -i -r "${id}" -e "0,${nx},${ny},${nw},${nh}" 2>/dev/null || true
    fi
  done
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
while sleep 0.5; do
  now="$(screen_size)"
  [[ -z "${now}" || "${now}" == "${last}" ]] && continue
  # A browser resize arrives as several sizes in a row: wait until it holds still for 1s.
  while sleep 1; do
    settled="$(screen_size)"
    [[ "${settled}" == "${now}" ]] && break
    now="${settled}"
  done
  last="${now}"
  log "screen is now ${now}; re-placing the panel"
  fit_windows
  replace_panel
  # Give the restarted panel time to come back before re-applying branding.
  for _ in $(seq 1 20); do
    panel_ready && break
    sleep 0.5
  done
  REAVION_PANEL_LIVE=1 "${THEME}" || true
done
