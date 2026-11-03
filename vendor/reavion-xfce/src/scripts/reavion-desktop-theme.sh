#!/bin/bash
# Apply Reavion XFCE desktop branding into the user home.
# Safe for persistent VOLUME /home/reavion — reseeds when THEME_VERSION bumps.
set -euo pipefail

THEME_VERSION="8"
STAMP="${HOME}/.config/reavion-desktop-theme.version"
SHARE="/usr/share/reavion-desktop"
WALLPAPER="/usr/share/backgrounds/reavion/reavion-mountains.jpg"
SKEL="${SHARE}/skel"
PANEL_RESTART_FLAG="${HOME}/.config/reavion-desktop-panel-restarted.${THEME_VERSION}"

mkdir -p \
  "${HOME}/.config/xfce4/terminal" \
  "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml" \
  "${HOME}/.config/xfce4/panel" \
  "${HOME}/.config/gtk-3.0" \
  "${HOME}/.config/autostart" \
  "$(dirname "${STAMP}")"

current="$(cat "${STAMP}" 2>/dev/null || true)"
need_seed=0
if [[ "${current}" != "${THEME_VERSION}" || "${REAVION_FORCE_THEME:-0}" == "1" ]]; then
  need_seed=1
fi

write_whisker_rc() {
  local id="$1"
  local rc="${HOME}/.config/xfce4/panel/whiskermenu-${id}.rc"
  cat > "${rc}" <<'EOF'
button-title=Applications
button-icon=reavion-mark
show-button-title=true
launcher-show-name=false
launcher-show-description=false
launcher-show-tooltip=true
item-icon-size=2
category-icon-size=1
EOF
}

if [[ "${need_seed}" == "1" ]]; then
  if [[ -d "${SKEL}/xfce" ]]; then
    cp -a "${SKEL}/xfce/terminal/." "${HOME}/.config/xfce4/terminal/" 2>/dev/null || true
    if [[ -d "${SKEL}/xfce/xfconf/xfce-perchannel-xml" ]]; then
      for f in "${SKEL}/xfce/xfconf/xfce-perchannel-xml/"*.xml; do
        base="$(basename "${f}")"
        # Never overwrite live panel XML with a hand-authored file.
        if [[ "${base}" == "xfce4-panel.xml" ]]; then
          continue
        fi
        cp -a "${f}" "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/"
      done
    fi
  fi
  if [[ -d "${SKEL}/gtk-3.0" ]]; then
    cp -a "${SKEL}/gtk-3.0/." "${HOME}/.config/gtk-3.0/"
  fi

  # Remove failed Plank experiment leftovers.
  pkill -u "$(id -u)" -x plank 2>/dev/null || true
  rm -rf "${HOME}/.config/plank"
  rm -f "${HOME}/.config/autostart/plank.desktop"
  rm -f "${PANEL_RESTART_FLAG}"

  if [[ ! -f "${HOME}/.config/xfce4/helpers.rc" ]]; then
    if [[ -f /usr/share/applications/google-chrome.desktop ]]; then
      printf 'WebBrowser=google-chrome\nTerminalEmulator=xfce4-terminal\n' \
        > "${HOME}/.config/xfce4/helpers.rc"
    else
      printf 'WebBrowser=firefox-esr\nTerminalEmulator=xfce4-terminal\n' \
        > "${HOME}/.config/xfce4/helpers.rc"
    fi
  fi

  printf '%s\n' "${THEME_VERSION}" > "${STAMP}"
fi

# Live display tweaks when X is up.
if command -v xfconf-query >/dev/null 2>&1 && xset q >/dev/null 2>&1; then
  xfconf-query -c xsettings -p /Gtk/FontName -n -t string -s "Inter 10" 2>/dev/null || true
  xfconf-query -c xsettings -p /Gtk/MonospaceFontName -n -t string -s "JetBrains Mono 11" 2>/dev/null || true
  xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s "Arc-Dark" 2>/dev/null || true
  xfconf-query -c xsettings -p /Net/IconThemeName -n -t string -s "Papirus" 2>/dev/null || true
  xfconf-query -c xfwm4 -p /general/theme -n -t string -s "Arc-Dark" 2>/dev/null || true
  xfconf-query -c xfwm4 -p /general/title_font -n -t string -s "Inter Bold 10" 2>/dev/null || true
  xfconf-query -c xfwm4 -p /general/use_compositing -n -t bool -s true 2>/dev/null || true

  # Quiet desktop surface.
  xfconf-query -c xfce4-desktop -p /desktop-icons/style -n -t int -s 0 2>/dev/null || true
  xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-home -n -t bool -s false 2>/dev/null || true
  xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-filesystem -n -t bool -s false 2>/dev/null || true
  xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-trash -n -t bool -s false 2>/dev/null || true

  # Wallpaper on every monitor property XFCE has created.
  if [[ -f "${WALLPAPER}" ]]; then
    while IFS= read -r prop; do
      case "${prop}" in
        */last-image)
          xfconf-query -c xfce4-desktop -p "${prop}" -n -t string -s "${WALLPAPER}" 2>/dev/null || true
          ;;
        */image-style)
          xfconf-query -c xfce4-desktop -p "${prop}" -n -t int -s 5 2>/dev/null || true
          ;;
      esac
    done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null || true)

    for mon in monitor0 monitorVNC-0 monitorVNC-1 monitorVirtual-1 monitoreDP-1; do
      base="/backdrop/screen0/${mon}/workspace0"
      xfconf-query -c xfce4-desktop -p "${base}/last-image" -n -t string -s "${WALLPAPER}" 2>/dev/null || true
      xfconf-query -c xfce4-desktop -p "${base}/image-style" -n -t int -s 5 2>/dev/null || true
      xfconf-query -c xfce4-desktop -p "${base}/color-style" -n -t int -s 0 2>/dev/null || true
    done
  fi

  # Brand the start menu + compact the native bottom dock (no external Plank).
  if xfconf-query -c xfce4-panel -l >/dev/null 2>&1; then
    xfconf-query -c xfce4-panel -p /panels/dark-mode -n -t bool -s true 2>/dev/null || true

    while IFS= read -r prop; do
      case "${prop}" in
        /plugins/plugin-*)
          # Only top-level plugin type props: /plugins/plugin-N
          if [[ "${prop}" =~ ^/plugins/plugin-[0-9]+$ ]]; then
            id="${prop##*-}"
            type="$(xfconf-query -c xfce4-panel -p "${prop}" 2>/dev/null || true)"
            case "${type}" in
              applicationsmenu|whiskermenu)
                # Brand the menu in place. Swapping the plugin type for Whisker does
                # not stick: the running panel writes its own config back.
                xfconf-query -c xfce4-panel -p "${prop}/button-icon" -n -t string -s "reavion-mark" 2>/dev/null || true
                xfconf-query -c xfce4-panel -p "${prop}/button-title" -n -t string -s "Applications" 2>/dev/null || true
                xfconf-query -c xfce4-panel -p "${prop}/show-button-title" -n -t bool -s true 2>/dev/null || true
                if [[ "${type}" == "whiskermenu" ]]; then write_whisker_rc "${id}"; fi
                ;;
            esac
          fi
          ;;
        /plugins/plugin-*/button-icon)
          xfconf-query -c xfce4-panel -p "${prop}" -n -t string -s "reavion-mark" 2>/dev/null || true
          ;;
      esac
    done < <(xfconf-query -c xfce4-panel -l 2>/dev/null || true)

    # Bottom / deskbar panels → compact centered dock.
    while IFS= read -r panel_prop; do
      case "${panel_prop}" in
        /panels/panel-*/position)
          panel_base="${panel_prop%/position}"
          pos="$(xfconf-query -c xfce4-panel -p "${panel_prop}" 2>/dev/null || true)"
          case "${pos}" in
            p=8\;*|p=10\;*|p=2\;*|p=4\;*)
              xfconf-query -c xfce4-panel -p "${panel_base}/length" -n -t uint -s 14 2>/dev/null || true
              xfconf-query -c xfce4-panel -p "${panel_base}/length-adjust" -n -t bool -s true 2>/dev/null || true
              xfconf-query -c xfce4-panel -p "${panel_base}/size" -n -t uint -s 44 2>/dev/null || true
              xfconf-query -c xfce4-panel -p "${panel_base}/icon-size" -n -t uint -s 32 2>/dev/null || true
              xfconf-query -c xfce4-panel -p "${panel_base}/position-locked" -n -t bool -s true 2>/dev/null || true
              xfconf-query -c xfce4-panel -p "${panel_base}/background-style" -n -t uint -s 0 2>/dev/null || true
              ;;
            p=6\;*|p=11\;*|p=0\;*)
              # Top panel — slim.
              xfconf-query -c xfce4-panel -p "${panel_base}/size" -n -t uint -s 28 2>/dev/null || true
              xfconf-query -c xfce4-panel -p "${panel_base}/icon-size" -n -t uint -s 16 2>/dev/null || true
              ;;
          esac
          ;;
      esac
    done < <(xfconf-query -c xfce4-panel -l 2>/dev/null || true)
  fi

  # One panel restart per theme version so Whisker/Papirus/CSS pick up cleanly.
  if [[ "${REAVION_PANEL_LIVE:-0}" != "1" && ! -f "${PANEL_RESTART_FLAG}" ]] && command -v xfce4-panel >/dev/null 2>&1; then
    if pgrep -u "$(id -u)" -x xfce4-panel >/dev/null 2>&1; then
      # Over D-Bus, never `xfce4-panel -r`: that shows an error dialog when the panel is not on the bus yet.
      dbus-send --session --type=method_call --dest=org.xfce.Panel /org/xfce/Panel \
        org.xfce.Panel.Terminate boolean:true >/dev/null 2>&1 || true
      printf '%s\n' "${THEME_VERSION}" > "${PANEL_RESTART_FLAG}"
    fi
  fi

  if pgrep -u "$(id -u)" -x plank >/dev/null 2>&1; then
    pkill -u "$(id -u)" -x plank 2>/dev/null || true
  fi
fi

exit 0
