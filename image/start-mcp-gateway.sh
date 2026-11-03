#!/usr/bin/env bash
# Expose reavion-driver MCP over Streamable HTTP + SSE for remote clients.
set -euo pipefail

export HOME="${HOME:-/home/reavion}"
export DISPLAY="${DISPLAY:-:1}"
export CUA_DRIVER_RS_TELEMETRY_ENABLED="${CUA_DRIVER_RS_TELEMETRY_ENABLED:-0}"
export REAVION_DRIVER_RS_TELEMETRY_ENABLED="${REAVION_DRIVER_RS_TELEMETRY_ENABLED:-0}"

SOCKET="${REAVION_SOCKET:-${CUA_SOCKET:-/run/user/1000/reavion.sock}}"
DRIVER="${REAVION_DRIVER:-${CUA_DRIVER:-/usr/local/libexec/reavion-desktop/reavion-driver}}"
MCP_PORT="${MCP_GATEWAY_PORT:-8200}"
API_KEY="${MCP_API_KEY:-}"

if [ -z "$API_KEY" ]; then
  if [ -n "${RAILWAY_ENVIRONMENT:-}" ] || [ "${REQUIRE_MCP_API_KEY:-0}" = "1" ]; then
    echo "ERROR: MCP_API_KEY is required for remote/Railway deploys." >&2
    exit 1
  fi
  echo "WARNING: MCP_API_KEY is empty; remote MCP is unauthenticated (local only)." >&2
fi

echo "Waiting for driver socket ${SOCKET}..."
deadline=$((SECONDS + 120))
while (( SECONDS < deadline )); do
  if [ -S "$SOCKET" ]; then
    echo "Socket ready"
    break
  fi
  sleep 1
done
if [ ! -S "$SOCKET" ]; then
  echo "ERROR: driver socket not ready after 120s" >&2
  exit 1
fi

STDIO_CMD="${DRIVER} mcp --socket ${SOCKET}"

extra_args=()
if [ -n "$API_KEY" ]; then
  extra_args+=(--apiKey "$API_KEY")
fi

if command -v supergateway >/dev/null 2>&1; then
  GATEWAY=(supergateway)
else
  GATEWAY=(npx --yes "supergateway@4.2.1")
fi

exec "${GATEWAY[@]}" \
  --stdio "$STDIO_CMD" \
  --outputTransport streamableHttp \
  --streamableHttpPath /mcp \
  --stateful \
  --sessionTimeout "${MCP_SESSION_TIMEOUT_MS:-900000}" \
  --port "$MCP_PORT" \
  --host 127.0.0.1 \
  --cors \
  --healthEndpoint /healthz \
  "${extra_args[@]}"
