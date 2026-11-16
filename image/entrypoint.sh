#!/bin/bash
# Pterodactyl entrypoint: expand {{VARIABLES}} in STARTUP and exec it, so the
# server receives ^C (SIGINT) directly and shuts down cleanly.
set -uo pipefail

cd /home/container || exit 1

if ! command -v dotnet >/dev/null 2>&1; then
  echo "entrypoint: no dotnet in this image - it must bundle the .NET 10 runtime." >&2
  exit 1
fi

# A file uploaded over SFTP often arrives without the executable bit.
if [ -f ./KcdMp.Server ]; then
  chmod +x ./KcdMp.Server 2>/dev/null || true
fi

# Create server.toml on the first boot only. An existing file is never
# rewritten, so whatever the owner edits in the panel's file manager survives
# restarts. RENDER_TOML=1 regenerates it from the panel variables.
/usr/local/bin/render-server-toml.sh /home/container || \
  echo "entrypoint: server.toml was not rendered; the server will fall back to its defaults." >&2

PARSED=$(printf '%s' "${STARTUP:-./KcdMp.Server}" | sed -e 's/{{/${/g' -e 's/}}/}/g' | eval echo "$(cat -)")

printf '\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n' "$PARSED"

exec env ${PARSED}
