#!/bin/sh
# Run the server locally, outside Pterodactyl, against this repo's ./server.
# This is the closest thing to the panel without the panel: same image, same
# startup command, same volume layout.
#
#   scripts/run-local.sh          start (builds the image if it is missing)
#   scripts/run-local.sh stop     stop and remove the container
#   scripts/run-local.sh logs     follow the log
#
# PORT, SERVER_NAME and IMG may be overridden from the environment.
set -eu

IMG="${IMG:-kcdmp:test}"
CONTAINER="${CONTAINER:-kcdmp-local}"
PORT="${PORT:-7777}"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

case "${1:-start}" in
  stop)
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    echo "stopped and removed $CONTAINER (the files in server/ are kept)"
    exit 0
    ;;
  logs)
    exec docker logs -f "$CONTAINER"
    ;;
  start) ;;
  *)
    echo "usage: $0 [start|stop|logs]" >&2
    exit 2
    ;;
esac

docker image inspect "$IMG" >/dev/null 2>&1 || docker build -t "$IMG" "$ROOT/image"

docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" --restart unless-stopped \
  --user "$(id -u):$(id -g)" \
  -e STARTUP='./KcdMp.Server --port {{SERVER_PORT}}' \
  -e SERVER_PORT="$PORT" \
  -e SERVER_NAME="${SERVER_NAME:-KCD:MP local test}" \
  -e KCDMP_MASTER_URL= \
  -v "$ROOT/server:/home/container" \
  -p "$PORT:$PORT/udp" \
  "$IMG" >/dev/null

sleep 4
docker logs "$CONTAINER" 2>&1 | grep -E 'render-server-toml|listening on|status:' || true

echo
echo "Direct connect: $(hostname -I | awk '{print $1}'):$PORT"
echo "live log:       $0 logs"
