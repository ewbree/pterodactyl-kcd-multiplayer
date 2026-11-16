#!/bin/sh
# Write a small server.toml from the panel's variables, on the first start.
#
# KCD:MP reads server.toml itself, and Pterodactyl has no TOML config parser,
# so the file is rendered here instead. It carries only the handful of keys the
# panel exposes; the server's own defaults cover everything else, and
# server.toml.example next to it documents every key.
#
# An existing server.toml is left untouched. Set RENDER_TOML=1 to regenerate.
set -eu

DIR="${1:-/home/container}"
TOML="$DIR/server.toml"

if [ -f "$TOML" ] && [ "${RENDER_TOML:-0}" != "1" ]; then
  echo "render-server-toml: server.toml exists, leaving it alone (RENDER_TOML=1 regenerates it)"
  exit 0
fi

# Bare digits only, so a typo cannot produce invalid TOML.
digits() {
  case "${1:-}" in
    ''|*[!0-9]*) printf '%s' "$2" ;;
    *)           printf '%s' "$1" ;;
  esac
}

# Escape for a TOML basic string: backslash first, then the quote.
esc() {
  printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

PORT="$(digits "${SERVER_PORT:-}" 7777)"
MAX="$(digits "${MAX_PLAYERS:-}" 32)"
NAME="$(esc "${SERVER_NAME:-KCD:MP server}")"
PASS="$(esc "${SERVER_PASSWORD:-}")"
LEVEL="$(esc "${LEVEL:-klaster}")"
# ${VAR-default} rather than ${VAR:-default}: an empty GAMEMODE means the
# server's built-in freeroam mode, which is a legitimate choice.
MODE="$(esc "${GAMEMODE-gamemodes/freeroam.lua}")"

umask 022
cat > "$TOML" <<EOF
# server.toml - created by pterodactyl-kcd-multiplayer on the first start.
#
# This file belongs to you: it is never rewritten unless RENDER_TOML=1 is set.
# It holds only the keys the panel asks for. Everything else keeps the server's
# defaults; server.toml.example alongside this file documents every key, and so
# does https://docs.kcd-mp.com/getting-started/server-config/
#
# Variables set in the panel that the server reads straight from the
# environment are not repeated here: KCDMP_ADMINS, KCDMP_MASTER_URL,
# KCDMP_AUDIT_MODE, KCDMP_DB_DRIVER and KCDMP_DB_URL.

[server]
port = ${PORT}
name = "${NAME}"
password = "${PASS}"
max_players = ${MAX}
level = "${LEVEL}"

[gamemode]
script = "${MODE}"
EOF

if [ -n "${EXTRA_TOML:-}" ]; then
  printf '\n# --- appended from EXTRA_TOML ---\n%s\n' "$EXTRA_TOML" >> "$TOML"
fi

echo "render-server-toml: wrote $TOML (port ${PORT}, ${MAX} slots, level ${LEVEL})"
