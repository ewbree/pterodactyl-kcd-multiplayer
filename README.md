# pterodactyl-kcd-multiplayer

A [Pterodactyl](https://pterodactyl.io) 1.x egg and Docker image for hosting a
**KCD:MP** (Kingdom Come: Deliverance II multiplayer) dedicated server.

No Wine, no Steam, no game install on the node: the KCD:MP server is a
framework-dependent .NET 10 console program with a Linux build, so the container
only supplies the runtime.

Not affiliated with the KCD:MP project, and it ships nothing of theirs: the
first start downloads the server from the
[official releases](https://github.com/dintech-rappy/kcd-mp-releases/releases)
and verifies the published checksum, or you upload it yourself.

## What's here

| Path | What it is |
| --- | --- |
| `image/` | the runtime image: entrypoint, GitHub-release updater, `server.toml` renderer |
| `egg/egg-kcd-mp.json` | the egg, importable as-is; see [egg/README.md](egg/README.md) |
| `scripts/` | `check-egg.py` (CI contract check), `verify-server.sh` (checksum), `run-local.sh` |
| `.github/workflows/image.yml` | builds `ghcr.io/<owner>/kcdmp:10.0` on every push to `main` |

## Requirements

- A Pterodactyl 1.x panel and an **amd64** node with Docker. The release archive
  is x86-64 only.
- One **UDP** allocation, 7777 by convention. No TCP allocation is needed.
- A copy of the game on **Windows** only if you want the data exports
  ([Game data](#game-data)).

## Quick start

1. **Build the image.** Push to GitHub and the workflow publishes
   `ghcr.io/<owner>/kcdmp:10.0` and `:latest`. A new package is private: make it
   public (Package page → *Change visibility*) or `docker login ghcr.io` on the
   node, or the first pull gets a 401. Locally:
   `docker build -t ghcr.io/ewbree/kcdmp:10.0 image`.
2. **Import the egg.** Admin → Nests → *Import Egg* → `egg/egg-kcd-mp.json`.
3. **Create the server** on a UDP allocation. The egg starts it with
   `--port {{SERVER_PORT}}`, so the allocation always wins over `server.toml`.
4. **Start it.** `AUTO_UPDATE=1` downloads, verifies and unpacks the newest
   release, then starts it — there is nothing to upload first. To use your own
   build, upload the archive's `linux/` folder (verify it with
   `scripts/verify-server.sh`, then SFTP) and set `AUTO_UPDATE=0`.
5. **Join** with `Direct connect` → `<node address>:<port>`. Launcher and server
   must be on the same KCD:MP release; a mismatch looks like a failed join.

## Updates

The image is only the runtime; the server files live on the volume. With
`AUTO_UPDATE=1` (default) each start compares the installed
`./KcdMp.Server --version` with the newest release of
[dintech-rappy/kcd-mp-releases](https://github.com/dintech-rappy/kcd-mp-releases/releases)
and installs the archive when they differ.

- The published SHA-256 is verified before anything is unpacked.
- Only files in the archive are written: `server.toml`, `server.log`, `data/`
  and your own `.lua`/`.dll` are untouched, and nothing is deleted.
- The binary's version is checked again after the swap; a mismatch restores the
  previous files and the server still starts.
- Any failure — GitHub down, rate limit, bad checksum, full disk — is logged,
  and the start continues with what is on disk.

`SERVER_VERSION` pins a release (`0.50.0`); a pin that already matches makes no
API call, and moving to a pin downgrades as happily as it upgrades. When a
release changes the protocol number the log says so, and old launchers are
refused until they update:

```
update: installed 0.51.0 (was 0.50.0)
update: protocol 123 -> protocol 124: players must update their launcher before they can join
```

That is the caveat of auto-update: the server can move before your players do.
Set `AUTO_UPDATE=0` to choose the moment. It cannot re-export the game data
([Game data](#game-data)), and the archive is x86-64 only. GitHub allows 60
anonymous API requests an hour per IP, one per start; `GITHUB_TOKEN` lifts that
on nodes with many servers.

## Ports

**UDP only**, one allocation. Wings publishes allocation `P` as `P` and exports
it as `SERVER_PORT`, which is why the startup command passes `--port`: moving a
server to another port needs no file edit.

`http_status` also opens **TCP** on that number for a JSON status page; with
only UDP published it stays inside the container, and `http_status = false`
under `[server]` turns it off.

`network_threads` (several UDP ports for 1000+ players) is not wired in: add the
allocations and set `network_ports` under `[server]` in `server.toml`.

## How configuration works

KCD:MP reads `server.toml`; Pterodactyl has no TOML parser, so the egg splits
configuration by *time*:

- **At creation** the panel asks for name, password, slots, level and game mode.
  They are written to `server.toml` on the first start and then hidden from the
  Startup tab.
- **Afterwards the file is the truth.** Edit it in the file manager or over
  SFTP; nothing in the panel writes it again. Delete it and the next start
  recreates it from the creation settings, which the panel still holds.
- **The environment** (`KCDMP_ADMINS`, `KCDMP_MASTER_URL`, `KCDMP_AUDIT_MODE`,
  `KCDMP_DB_DRIVER`, `KCDMP_DB_URL`) is read at every start and wins over the
  file, so those variables stay editable.

Everything else — `[rates]`, `[world]`, `[combat]`, `[spawn]` — belongs in
`server.toml`. `server.toml.example` beside it documents every key, as does
[the configuration docs](https://docs.kcd-mp.com/getting-started/server-config/).

`KCDMP_MASTER_URL` is empty by default: a new server is private and on no list
until you set `https://kcd-mp.com/server-list`.

## Game data

Four exports turn on the item, terrain, navigation and collision features. They
are made **on Windows from the installed game**, with the archive's `tools/` —
the container cannot produce them. Export the tables first.

| File | Turns on |
| --- | --- |
| `data/combat/items.json` | damage from the game's tables, items by name, the item check |
| `data/heightmaps/<level>.hmap` | the terrain check |
| `data/navmesh/<level>.knav` | NPCs that walk around walls, `FindPath` |
| `data/collision/<level>.kcol` | line of sight, `RayCast`, the floor as ground |

Upload with **SFTP**, not the web uploader: navmesh and collision files are
large. `data/` survives restarts and image updates; a reinstall is covered in
[egg/README.md](egg/README.md).

## Troubleshooting

- **"KcdMp.Server is missing"**: `AUTO_UPDATE=0` with nothing uploaded. Upload
  the `linux/` folder, or set `AUTO_UPDATE=1` and restart.
- **Panel stuck at "Starting" while the console runs the server**: Wings treats
  each `done` entry as a **literal substring** unless it starts with `regex:`.
  The egg matches `listening on udp/`; if a release rewords it, adjust the egg's
  *Startup Detection*.
- **New image, old server**: Wings only pulls on container creation. Stop,
  `docker rm <uuid>` on the node, start again — the volume is untouched.
  Updating *server files* needs no such thing.
- **Exit code 3 loop**: `[server] stall_exit = 30` makes a silent server exit so
  the panel restarts it; a loop is usually the port.
- **`--help` is fatal**: there is no help text and unknown flags abort. Known
  ones: `--port`, `--name`, `--max-players`, `--level`, `--password`,
  `--version`, `--config`.
- **`Permission denied` on the binary**: reinstall, or
  `chown -R container:container /home/container`.

## Limits that are the host's

- **UDP socket buffers**: Linux caps them around 0.2 MB; with hundreds of
  players ask the host for `16777216` on `net.core.rmem_max`/`wmem_max`.
- **`[rates] reliable_rate`** defaults to 24 MB/s, more than a 100 Mbit line
  carries. On a small VPS set 5–6 in `server.toml`.
- **Memory and CPU** are ordinary: a few hundred MB for a small server.

## Tested with

| Piece | Version |
| --- | --- |
| `KcdMp.Server` | 0.50.0, protocol 123 |
| .NET runtime | `Microsoft.NETCore.App` 10.0.15 |
| Base image | `mcr.microsoft.com/dotnet/runtime:10.0`, 321 MB unpacked |
| Pterodactyl | egg schema `PTDL_v2` |
| Docker | 29.10.0, Ubuntu 26.04 (WSL2), overlayfs, cgroup v2 |

Verified locally: the server binds UDP, `http_status` answers JSON, `server.toml`
is rendered once and left alone, `data/server.db` and `server.log` are written,
and `SIGINT` shuts down cleanly with exit code 0. It reads stdin, so `help`,
`say` and `reload` work from the panel console. Auto-update was exercised
against the real API and a fake endpoint: up to date, empty-volume bootstrap,
offline, pinned and unknown versions, a doctored checksum (refused), a
wrong-version release (rolled back), and an update over a volume with a custom
mode, game data and an edited `server.toml` (all preserved).

## Credits

KCD:MP and Kingdom Come: Deliverance II belong to their respective authors. This
repository contains only container packaging.
