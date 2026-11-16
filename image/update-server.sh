#!/bin/bash
# Keep /home/container current with the official KCD:MP GitHub releases.
#
# Runs from the entrypoint before the server starts and never blocks a start:
# an unreachable API, an unpublished checksum or a bad archive all leave the
# installed files exactly as they were.
#
#   AUTO_UPDATE=1     check on every start and install the wanted version
#   SERVER_VERSION    latest (default), or a release version such as 0.50.0
#   GITHUB_TOKEN      optional; lifts the anonymous API rate limit
#
# Only files that exist in the release archive are written. server.toml,
# server.log and data/ are never touched and nothing is deleted, so custom
# game modes, game-data exports and your configuration survive an update.
set -uo pipefail

DIR=${1:-/home/container}
REPO=${KCDMP_UPDATE_REPO:-dintech-rappy/kcd-mp-releases}
API=${KCDMP_UPDATE_API:-https://api.github.com/repos/$REPO}
AUTO=${AUTO_UPDATE:-1}
WANT=${SERVER_VERSION:-latest}
WANT=${WANT#v}
WORK="$DIR/.kcdmp-update"
AUTH=()

log() { printf 'update: %s\n' "$*"; }

if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

if [ "$AUTO" != "1" ]; then
  log "AUTO_UPDATE=$AUTO, not checking for updates"
  exit 0
fi

# Roll the files written so far back to their previous contents.
restore() {
  [ -d "$WORK/previous" ] || return 0
  while IFS= read -r -d '' file; do
    rel=${file#"$WORK/previous/"}
    mkdir -p "$DIR/$(dirname "$rel")"
    cp -p "$file" "$DIR/$rel" 2>/dev/null || true
  done < <(find "$WORK/previous" -type f -print0)
  chmod +x "$DIR/KcdMp.Server" 2>/dev/null || true
}

# A run killed mid-copy leaves its backup behind. Put those files back before
# doing anything else; the rest of this run then updates from a clean state.
if [ -d "$WORK/previous" ] && [ -n "$(find "$WORK/previous" -type f -print -quit 2>/dev/null)" ]; then
  log "an earlier update did not finish; restoring the previous files"
  restore
  rm -rf "$WORK"
fi

# The linux/ folder in the release archive is x86-64 only.
case "$(uname -m)" in
  x86_64|amd64) ;;
  *)
    log "$(uname -m) is not supported: the release archive is x86-64 only, skipping"
    exit 0
    ;;
esac

for tool in curl unzip jq sha256sum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    log "$tool is missing from this image, skipping"
    exit 0
  fi
done

# Ask the installed binary rather than trusting a marker file: it is the same
# thing the server will run in a moment.
installed=""
installed_protocol=""
if [ -f "$DIR/KcdMp.Server" ]; then
  chmod +x "$DIR/KcdMp.Server" 2>/dev/null || true
  version_output=$(cd "$DIR" && ./KcdMp.Server --version 2>&1 | head -n 5)
  installed=$(printf '%s\n' "$version_output" | sed -n 's/^KcdMp\.Server \([0-9][0-9.]*\).*/\1/p' | head -n 1)
  installed_protocol=$(printf '%s\n' "$version_output" | sed -n 's/.*(protocol \([0-9][0-9]*\)).*/protocol \1/p' | head -n 1)
fi

# A pinned version that is already installed needs no API call at all, which
# keeps nodes with many servers well under GitHub's anonymous rate limit.
if [ "$WANT" != "latest" ] && [ -n "$installed" ] && [ "$installed" = "$WANT" ]; then
  log "up to date: $WANT (pinned, no API call)"
  exit 0
fi

if [ "$WANT" = "latest" ]; then
  endpoint="$API/releases/latest"
  expected="the newest release"
else
  endpoint="$API/releases/tags/v$WANT"
  expected="release $WANT"
fi

if ! json=$(curl -fsSL --max-time 20 --retry 2 --retry-delay 2 \
      -H 'Accept: application/vnd.github+json' "${AUTH[@]}" "$endpoint" 2>/dev/null); then
  log "could not fetch $expected from GitHub; keeping the installed files"
  exit 0
fi

tag=$(printf '%s' "$json" | jq -r '.tag_name // empty' 2>/dev/null)
if [ -z "$tag" ]; then
  log "GitHub returned no tag for $expected; keeping the installed files"
  exit 0
fi
target=${tag#v}

asset=$(printf '%s' "$json" | jq -r \
  '.assets[] | select(.name | test("^KcdMp-server-.*\\.zip$"))
   | [(.browser_download_url // ""), (.name // ""), (.digest // "")] | @tsv' 2>/dev/null | head -n 1)
if [ -z "$asset" ]; then
  log "release $target has no KcdMp-server-*.zip asset; keeping the installed files"
  exit 0
fi
IFS=$'\t' read -r asset_url asset_name digest <<<"$asset"

if [ -n "$installed" ] && [ "$installed" = "$target" ]; then
  log "up to date: $target"
  exit 0
fi

rm -rf "$WORK"
if ! mkdir -p "$WORK/staging" "$WORK/previous"; then
  log "cannot write the update workspace under $DIR, skipping"
  exit 0
fi

log "downloading $asset_name ($target${installed:+, replacing $installed})"
zip="$WORK/$asset_name"
if ! curl -fsSL --max-time 300 --retry 2 --retry-delay 2 -o "$zip" "$asset_url" 2>/dev/null; then
  log "download failed; keeping the installed files"
  rm -rf "$WORK"
  exit 0
fi

# The release API publishes the hash of every asset. Older releases may not,
# so fall back to the .sha256 sidecar next to the archive.
expected_sha=${digest#sha256:}
if [ -z "$expected_sha" ]; then
  expected_sha=$(curl -fsSL --max-time 20 "${AUTH[@]}" "$asset_url.sha256" 2>/dev/null | awk '{print $1; exit}')
fi
actual_sha=$(sha256sum "$zip" | awk '{print $1}')
if [ -z "$expected_sha" ]; then
  log "no checksum is published for $asset_name; refusing to install it"
  rm -rf "$WORK"
  exit 0
fi
if [ "$expected_sha" != "$actual_sha" ]; then
  log "checksum mismatch for $asset_name (expected $expected_sha, got $actual_sha); refusing to install it"
  rm -rf "$WORK"
  exit 0
fi

if ! unzip -q "$zip" -d "$WORK/staging" 2>/dev/null; then
  log "could not unpack $asset_name; keeping the installed files"
  rm -rf "$WORK"
  exit 0
fi

# Tolerate both archive layouts: linux/ (current) and a flat folder.
src="$WORK/staging/linux"
[ -f "$src/KcdMp.Server" ] || src="$WORK/staging"
if [ ! -f "$src/KcdMp.Server" ]; then
  log "the archive has no KcdMp.Server under linux/; keeping the installed files"
  rm -rf "$WORK"
  exit 0
fi

protected() {
  case "$1" in
    ./server.toml|./server.log|./.kcdmp-update|./.kcdmp-update/*|./data|./data/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Back up every file the archive is about to overwrite, then write the files
# one by one. Directories are created as needed; nothing is deleted.
files=()
while IFS= read -r -d '' file; do
  rel=${file#"$src/"}
  protected "./$rel" && continue
  files+=("$rel")
  if [ -e "$DIR/$rel" ]; then
    mkdir -p "$WORK/previous/$(dirname "$rel")"
    cp -p "$DIR/$rel" "$WORK/previous/$rel" 2>/dev/null || true
  fi
done < <(find "$src" -type f -print0)

for rel in "${files[@]}"; do
  mkdir -p "$DIR/$(dirname "$rel")"
  if ! cp -p "$src/$rel" "$DIR/$rel" 2>/dev/null; then
    log "could not write $rel; restoring the previous files"
    restore
    rm -rf "$WORK"
    exit 0
  fi
done

# The zip is built on Windows and carries no Unix mode bits, so the executable
# bit has to be restored here; the entrypoint does the same for SFTP uploads.
chmod +x "$DIR/KcdMp.Server" 2>/dev/null || true
new_output=$(cd "$DIR" && ./KcdMp.Server --version 2>&1 | head -n 5)
new_version=$(printf '%s\n' "$new_output" | sed -n 's/^KcdMp\.Server \([0-9][0-9.]*\).*/\1/p' | head -n 1)
new_protocol=$(printf '%s\n' "$new_output" | sed -n 's/.*(protocol \([0-9][0-9]*\)).*/protocol \1/p' | head -n 1)

if [ "$new_version" != "$target" ]; then
  log "the installed binary reports '${new_version:-nothing}', expected $target"
  if [ -n "$(find "$WORK/previous" -type f -print -quit 2>/dev/null)" ]; then
    log "restoring the previous files"
    restore
  else
    log "there was nothing to restore; leaving the archive in place"
  fi
  rm -rf "$WORK"
  exit 0
fi

if [ -n "$installed" ]; then
  log "installed $target (was $installed)"
else
  log "installed $target"
fi

if [ -n "$installed_protocol" ] && [ -n "$new_protocol" ] && [ "$installed_protocol" != "$new_protocol" ]; then
  log "${installed_protocol} -> ${new_protocol}: players must update their launcher before they can join"
fi

log "re-export the game data from the new release's windows/ folder: data/combat/items.json, plus the heightmap, navmesh and collision for each level"

rm -rf "$WORK"
exit 0
