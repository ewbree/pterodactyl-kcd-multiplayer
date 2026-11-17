#!/bin/sh
# Write server.toml from the server's creation settings, on the first start.
#
# KCD:MP reads server.toml itself, and Pterodactyl has no TOML config parser,
# so the file is rendered here instead. It carries only the handful of keys the
# panel asked for at creation; the server's own defaults cover everything else,
# and server.toml.example next to it documents every key.
#
# This runs only when the file is missing. Once it exists it belongs to the
# owner: edit it in the panel's file manager or over SFTP. Delete it to have it
# written again from the creation settings, which the panel still holds.
set -eu

DIR="${1:-/home/container}"
TOML="$DIR/server.toml"

if [ -f "$TOML" ]; then
  echo "render-server-toml: server.toml exists, leaving it alone"
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
TOML_LEVEL="$(esc "${LEVEL:-klaster}")"
# ${VAR-default} rather than ${VAR:-default}: an empty GAMEMODE means the
# server's built-in freeroam mode, which is a legitimate choice.
MODE="$(esc "${GAMEMODE-gamemodes/freeroam.lua}")"

umask 022
cat > "$TOML" <<EOF
# server.toml - created by pterodactyl-kcd-multiplayer on the first start.
#
# This file belongs to you: it is never rewritten. Edit it here in the panel's
# file manager or over SFTP; delete it and the next start writes it again from
# the settings the server was created with.
#
# Everything the server offers is documented in server.toml.example alongside
# this file, and at https://docs.kcd-mp.com/getting-started/server-config/
#
# The panel variables that the server reads straight from the environment are
# not repeated here: KCDMP_ADMINS, KCDMP_MASTER_URL, KCDMP_AUDIT_MODE,
# KCDMP_DB_DRIVER and KCDMP_DB_URL. Set those in the server's Startup tab.

[server]
port = ${PORT}
name = "${NAME}"
password = "${PASS}"
max_players = ${MAX}
level = "${TOML_LEVEL}"

[gamemode]
script = "${MODE}"
EOF

echo "render-server-toml: wrote $TOML (port ${PORT}, ${MAX} slots, level ${TOML_LEVEL})"
