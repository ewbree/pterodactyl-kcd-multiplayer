#!/bin/bash
# Pterodactyl entrypoint: expand {{VARIABLES}} in STARTUP and exec it, so the
# server receives ^C (SIGINT) directly and shuts down cleanly.
set -uo pipefail

cd /home/container || exit 1

if ! command -v dotnet >/dev/null 2>&1; then
  echo "entrypoint: no dotnet in this image - it must bundle the .NET 10 runtime." >&2
  exit 1
fi

# Keep the server files current with the official releases. This never blocks a
# start: on any failure the updater leaves the installed files alone, and on a
# fresh server with AUTO_UPDATE=1 it installs the release instead of asking for
# an SFTP upload.
timeout 900 /usr/local/bin/update-server.sh /home/container || \
  echo "entrypoint: the update check failed; continuing with the installed files." >&2

# A file uploaded over SFTP often arrives without the executable bit.
if [ -f ./KcdMp.Server ]; then
  chmod +x ./KcdMp.Server 2>/dev/null || true
fi

if [ ! -f ./KcdMp.Server ]; then
  echo "entrypoint: KcdMp.Server is missing. Set AUTO_UPDATE=1 to download the" >&2
  echo "entrypoint: latest release on start, or upload the archive's linux/ folder" >&2
  echo "entrypoint: to /home/container over SFTP." >&2
  exit 1
fi

# Create server.toml on the first boot only. An existing file is never
# rewritten, so whatever the owner edits in the panel's file manager survives
# restarts; deleting it makes the next boot write it again.
/usr/local/bin/render-server-toml.sh /home/container || \
  echo "entrypoint: server.toml was not rendered; the server will fall back to its defaults." >&2

PARSED=$(printf '%s' "${STARTUP:-./KcdMp.Server}" | sed -e 's/{{/${/g' -e 's/}}/}/g' | eval echo "$(cat -)")

printf '\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n' "$PARSED"

exec env ${PARSED}
