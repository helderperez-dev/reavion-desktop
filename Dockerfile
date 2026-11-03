# reavion-desktop (published as ghcr.io/helderperez-dev/reavion-desktop)
# Repo: helderperez-dev/cua-agent-desktop
#
# Default: pull prebuilt XFCE base + reavion-driver from GHCR (cascade CI).
# Local override examples:
#   DESKTOP_BASE=reavion/xfce:local
#   DRIVER_IMAGE=localhost/reavion-driver:local
# Vendor compile fallback: Dockerfile.vendor (Railway self-contained until GHCR pull works).

ARG DESKTOP_BASE=ghcr.io/helderperez-dev/reavion-xfce:main
ARG DRIVER_IMAGE=ghcr.io/helderperez-dev/reavion-driver:main

FROM ${DRIVER_IMAGE} AS driver

FROM ${DESKTOP_BASE}

ARG TARGETARCH
ARG CADDY_VERSION=2.10.2
ARG REAVION_DRIVER_VERSION=main
ARG DESKTOP_BASE
ARG DRIVER_IMAGE

LABEL org.opencontainers.image.title="reavion-desktop" \
      org.opencontainers.image.description="Isolated Linux desktop for AI agents via Reavion Driver MCP + noVNC" \
      org.opencontainers.image.source="https://github.com/helderperez-dev/cua-agent-desktop" \
      reavion.desktop.managed="true" \
      reavion.desktop.driver="reavion-driver" \
      reavion.desktop.driver.version="${REAVION_DRIVER_VERSION}" \
      reavion.desktop.base="${DESKTOP_BASE}" \
      cua.agent.desktop.managed="true" \
      cua.agent.desktop.driver="reavion-driver" \
      cua.agent.desktop.driver.version="${REAVION_DRIVER_VERSION}" \
      cua.agent.desktop.base="${DESKTOP_BASE}"

ENV PORT=8080 \
    MCP_GATEWAY_PORT=8200 \
    MCP_API_KEY= \
    REQUIRE_MCP_API_KEY=0 \
    RAILWAY_ENVIRONMENT= \
    CUA_DRIVER_RS_TELEMETRY_ENABLED=0 \
    REAVION_DRIVER_RS_TELEMETRY_ENABLED=0 \
    VNC_RESOLUTION=1280x720 \
    VNC_COL_DEPTH=24 \
    HOME=/home/reavion \
    REAVION_SOCKET=/run/user/1000/reavion.sock \
    REAVION_DRIVER=/usr/local/libexec/reavion-desktop/reavion-driver \
    CUA_SOCKET=/run/user/1000/reavion.sock \
    CUA_DRIVER=/usr/local/libexec/reavion-desktop/reavion-driver

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl nodejs npm; \
    case "${TARGETARCH}" in \
      arm64|aarch64) caddy_arch=arm64 ;; \
      amd64|x86_64)  caddy_arch=amd64 ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/caddy.tgz \
      "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_${caddy_arch}.tar.gz"; \
    tar -xzf /tmp/caddy.tgz -C /usr/local/bin caddy; \
    chmod 0755 /usr/local/bin/caddy; \
    caddy version; \
    node --version; \
    npm --version; \
    npm install -g "supergateway@4.2.1"; \
    rm -f /tmp/caddy.tgz; \
    rm -rf /var/lib/apt/lists/*; \
    install -d -o reavion -g reavion -m 0755 /home/reavion/.npm

COPY image/google-chrome-wrapper.sh /usr/local/bin/google-chrome-wrapper.sh
RUN set -eux; \
    case "${TARGETARCH}" in \
      arm64|aarch64) deb_arch=arm64 ;; \
      amd64|x86_64)  deb_arch=amd64 ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/chrome.deb \
      "https://dl.google.com/linux/direct/google-chrome-stable_current_${deb_arch}.deb"; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/chrome.deb || \
      apt-get install -y --no-install-recommends -f; \
    rm -f /tmp/chrome.deb; \
    rm -rf /var/lib/apt/lists/*; \
    chmod 0755 /usr/local/bin/google-chrome-wrapper.sh; \
    if [ -x /usr/bin/google-chrome-stable ]; then \
      mv /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable.real; \
      ln -sfn /usr/local/bin/google-chrome-wrapper.sh /usr/bin/google-chrome-stable; \
      ln -sfn /usr/local/bin/google-chrome-wrapper.sh /usr/bin/google-chrome; \
      ln -sfn /usr/local/bin/google-chrome-wrapper.sh /usr/local/bin/google-chrome; \
      ln -sfn /usr/local/bin/google-chrome-wrapper.sh /usr/local/bin/chrome; \
    fi; \
    update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/local/bin/google-chrome-wrapper.sh 200; \
    update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser /usr/local/bin/google-chrome-wrapper.sh 200; \
    install -d -o reavion -g reavion -m 0700 /home/reavion/.config/google-chrome; \
    install -d -o reavion -g reavion /home/reavion/.config/xfce4; \
    printf 'WebBrowser=google-chrome\nTerminalEmulator=xfce4-terminal\n' \
      > /home/reavion/.config/xfce4/helpers.rc; \
    chown reavion:reavion /home/reavion/.config/xfce4/helpers.rc; \
    google-chrome-stable --version

# Prebuilt binary from GHCR (or local DRIVER_IMAGE)
COPY --from=driver /out/reavion-driver /usr/local/libexec/reavion-desktop/reavion-driver
RUN set -eux; \
    chmod 0755 /usr/local/libexec/reavion-desktop/reavion-driver; \
    ln -sfn /usr/local/libexec/reavion-desktop/reavion-driver /usr/local/bin/reavion-driver; \
    ln -sfn /usr/local/libexec/reavion-desktop/reavion-driver /usr/local/bin/cua-driver; \
    install -d -m 0755 /usr/local/libexec/cua-desktop; \
    ln -sfn /usr/local/libexec/reavion-desktop/reavion-driver /usr/local/libexec/cua-desktop/cua-driver; \
    /usr/local/libexec/reavion-desktop/reavion-driver --version | tee /tmp/reavion-driver-version.txt; \
    install -d -o reavion -g reavion -m 0700 /run/user/1000; \
    install -d -o reavion -g reavion -m 0755 /home/reavion/workspace; \
    rm -f /tmp/reavion-driver-version.txt

COPY image/start-reavion-driver.sh /usr/local/bin/start-reavion-driver.sh
COPY image/start-mcp-gateway.sh /usr/local/bin/start-mcp-gateway.sh
COPY image/start-edge-proxy.sh /usr/local/bin/start-edge-proxy.sh
COPY image/start-system-dbus.sh /usr/local/bin/start-system-dbus.sh
COPY image/fix-chrome-profile.sh /usr/local/bin/fix-chrome-profile.sh
COPY image/Caddyfile /etc/caddy/Caddyfile
COPY image/reavion-driver.conf /etc/supervisor/conf.d/reavion-driver.conf
COPY image/mcp-gateway.conf /etc/supervisor/conf.d/mcp-gateway.conf
COPY image/edge-proxy.conf /etc/supervisor/conf.d/edge-proxy.conf
COPY image/dbus-system.conf /etc/supervisor/conf.d/dbus-system.conf
COPY image/fix-chrome-profile.conf /etc/supervisor/conf.d/fix-chrome-profile.conf

# Branding overlay on top of XFCE base noVNC tree (logos + connect screen).
COPY vendor/reavion-xfce/vendor/reavion-vnc/vnc.html /usr/share/reavion-vnc/vnc.html
COPY vendor/reavion-xfce/vendor/reavion-vnc/index.html /usr/share/reavion-vnc/index.html
COPY vendor/reavion-xfce/vendor/reavion-vnc/app/styles/base.css /usr/share/reavion-vnc/app/styles/base.css
COPY vendor/reavion-xfce/vendor/reavion-vnc/app/styles/reavion.css /usr/share/reavion-vnc/app/styles/reavion.css
COPY vendor/reavion-xfce/vendor/reavion-vnc/app/ui.js /usr/share/reavion-vnc/app/ui.js
COPY vendor/reavion-xfce/vendor/reavion-vnc/app/images/reavion-logo-white.png /usr/share/reavion-vnc/app/images/reavion-logo-white.png
COPY vendor/reavion-xfce/vendor/reavion-vnc/app/images/reavion-logo-black.png /usr/share/reavion-vnc/app/images/reavion-logo-black.png
COPY vendor/reavion-xfce/vendor/reavion-vnc/app/images/reavion-mark-white.png /usr/share/reavion-vnc/app/images/reavion-mark-white.png

# Desktop theme overlay (safe if XFCE base already includes them).
COPY vendor/reavion-xfce/src/scripts/reavion-desktop-theme.sh /usr/local/bin/reavion-desktop-theme.sh
COPY vendor/reavion-xfce/src/scripts/xstartup.sh /usr/local/bin/xstartup.sh
COPY vendor/reavion-xfce/src/scripts/reavion-desktop-watch.sh /usr/local/bin/reavion-desktop-watch.sh
COPY vendor/reavion-xfce/assets/backgrounds/reavion-mountains.jpg /usr/share/backgrounds/reavion/reavion-mountains.jpg
COPY vendor/reavion-xfce/assets/icons/reavion-mark.png /usr/share/pixmaps/reavion-mark.png
COPY vendor/reavion-xfce/assets/icons/hicolor/ /usr/share/icons/hicolor/
COPY vendor/reavion-xfce/assets/applications/reavion-apps.desktop /usr/share/applications/reavion-apps.desktop
COPY vendor/reavion-xfce/src/desktop-skel/ /usr/share/reavion-desktop/skel/
COPY --chown=reavion:reavion vendor/reavion-xfce/src/gtk-3.0/ /home/reavion/.config/gtk-3.0/
RUN chmod 0755 /usr/local/bin/reavion-desktop-theme.sh /usr/local/bin/xstartup.sh /usr/local/bin/reavion-desktop-watch.sh \
 && mkdir -p /usr/share/icons/hicolor/48x48/apps /home/reavion/.config/autostart /etc/xdg/autostart \
 && cp -a /usr/share/reavion-desktop/skel/autostart/. /home/reavion/.config/autostart/ 2>/dev/null || true \
 && cp -a /usr/share/reavion-desktop/skel/autostart/google-chrome.desktop /etc/xdg/autostart/ 2>/dev/null || true \
 && chown -R reavion:reavion /home/reavion/.config/autostart \
 && gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true \
 && apt-get update \
 && apt-get install -y --no-install-recommends dbus xfce4-whiskermenu-plugin \
 && rm -rf /var/lib/apt/lists/* \
 && printf '8\n' > /usr/share/reavion-desktop/THEME_VERSION

RUN ln -sfn /usr/local/bin/start-reavion-driver.sh /usr/local/bin/start-cua-driver.sh

RUN chmod 0755 \
      /usr/local/bin/start-reavion-driver.sh \
      /usr/local/bin/start-mcp-gateway.sh \
      /usr/local/bin/start-edge-proxy.sh \
      /usr/local/bin/start-system-dbus.sh \
      /usr/local/bin/fix-chrome-profile.sh \
 && rm -f /etc/supervisor/conf.d/cua-driver.conf \
 && if grep -Fq '[program:dbus-system]' /etc/supervisor/supervisord.conf 2>/dev/null; then \
      rm -f /etc/supervisor/conf.d/dbus-system.conf; \
    fi \
 && for conf in dbus-system fix-chrome-profile reavion-driver mcp-gateway edge-proxy; do \
      [ -f "/etc/supervisor/conf.d/${conf}.conf" ] || continue; \
      if [ -f /etc/supervisor/conf.d/supervisord.conf ] \
         && ! grep -Fq "[program:${conf}]" /etc/supervisor/conf.d/supervisord.conf; then \
        printf '\n' >> /etc/supervisor/conf.d/supervisord.conf; \
        cat "/etc/supervisor/conf.d/${conf}.conf" >> /etc/supervisor/conf.d/supervisord.conf; \
      fi; \
    done \
 && if [ -f /etc/supervisor/supervisord.conf ] \
      && ! grep -Eq 'files[[:space:]]*=[[:space:]]*/etc/supervisor/conf.d' /etc/supervisor/supervisord.conf \
      && ! grep -Fq '[program:reavion-driver]' /etc/supervisor/supervisord.conf; then \
      printf '\n[include]\nfiles = /etc/supervisor/conf.d/*.conf\n' >> /etc/supervisor/supervisord.conf; \
    fi \
 && if [ -f /etc/supervisor/supervisord.conf ] \
      && ! grep -Eq 'files[[:space:]]*=[[:space:]]*/etc/supervisor/conf.d' /etc/supervisor/supervisord.conf; then \
      for conf in dbus-system fix-chrome-profile; do \
        [ -f "/etc/supervisor/conf.d/${conf}.conf" ] || continue; \
        grep -Fq "[program:${conf}]" /etc/supervisor/supervisord.conf && continue; \
        printf '\n' >> /etc/supervisor/supervisord.conf; \
        cat "/etc/supervisor/conf.d/${conf}.conf" >> /etc/supervisor/supervisord.conf; \
      done; \
    fi

WORKDIR /home/reavion
EXPOSE 8080
