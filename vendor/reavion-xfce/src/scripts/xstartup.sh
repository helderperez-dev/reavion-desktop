#!/bin/bash
set -euo pipefail

export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export XDG_SESSION_TYPE=x11

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  eval "$(dbus-launch --sh-syntax --exit-with-session)"
fi

# Seed branded XFCE configs into the (possibly volume-mounted) home before the session.
if [[ -x /usr/local/bin/reavion-desktop-theme.sh ]]; then
  /usr/local/bin/reavion-desktop-theme.sh || true
fi

startxfce4 &
xfce_pid=$!

for _ in $(seq 1 20); do
  if xset q >/dev/null 2>&1; then
    xset s off
    xset -dpms
    xset s noblank
    break
  fi
  sleep 1
done

# Wallpaper/compositing once the display is up (monitor names settle).
if [[ -x /usr/local/bin/reavion-desktop-theme.sh ]]; then
  /usr/local/bin/reavion-desktop-theme.sh || true
fi

# Panel branding needs the panel's own config, which appears a few seconds
# after startxfce4; the watcher applies it then and re-places the dock on resize.
if [[ -x /usr/local/bin/reavion-desktop-watch.sh ]]; then
  /usr/local/bin/reavion-desktop-watch.sh &
fi

wait "$xfce_pid"
