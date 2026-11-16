# pterodactyl-kcd-multiplayer

A [Pterodactyl](https://pterodactyl.io) 1.x egg and Docker image for hosting a
**KCD:MP** (Kingdom Come: Deliverance II multiplayer) dedicated server.

No Wine, no Steam, no game install on the node: the KCD:MP server is a
framework-dependent .NET 10 console program with a Linux build, so a container
only has to supply the runtime.

Not affiliated with the KCD:MP project. It ships nothing of theirs — you
download the server from [kcd-mp.com](https://kcd-mp.com/download).

## What's here

| Path | What it is |
| --- | --- |
| `image/Dockerfile` | `mcr.microsoft.com/dotnet/runtime:10.0` + the non-root user Wings expects |
| `image/entrypoint.sh` | expands `{{VARIABLES}}` in `STARTUP` and `exec`s it, so `^C` reaches the server |
| `image/render-server-toml.sh` | writes a small `server.toml` from panel variables on the first start |
| `egg/egg-kcd-mp.json` | the egg, importable as-is |
| `scripts/verify-server.sh` | checksum check for the downloaded archive |
| `scripts/check-egg.py` | asserts the egg matches what the 1.x importer reads (runs in CI) |
| `.github/workflows/image.yml` | builds `ghcr.io/<owner>/kcdmp:10.0` on every push to `main` |

## Requirements

- A Pterodactyl 1.x panel and a node with Docker — nothing else. The server
  does not need the game, .NET, or a desktop environment.
- One allocation, **UDP** — 7777 is the usual choice. No TCP allocation is
  needed; the optional HTTP status endpoint listens inside the container only.
- Your own copy of the game on **Windows**, if you want the four data exports
  (see [Game data](#game-data)).

## Quick start

1. **Build the image.** Push this repo to GitHub; the included workflow pushes
   `ghcr.io/<owner>/kcdmp:10.0` and `:latest` to GHCR. New packages are private
   by default — either make the package public (Package page → *Change
   visibility* → Public) or run `docker login ghcr.io` on the node. Without one
   of those the first pull fails with a 401.

   Locally, with Docker:
   ```sh
   docker build -t ghcr.io/ewbree/kcdmp:10.0 image
   ```

2. **Import the egg.** Admin → Nests → *Import Egg* → `egg/egg-kcd-mp.json`.
   See [egg/README.md](egg/README.md) for the details.

3. **Create the server** with the egg, on an allocation whose UDP port you want
   players to connect to. The egg starts the server with `--port
   {{SERVER_PORT}}`, so the allocation always wins — even if `server.toml` says
   something else.

4. **Upload the server files.** Download the archive from kcd-mp.com, verify it,
   extract the `linux/` folder, and SFTP its *contents* into `/home/container`:

   ```sh
   scripts/verify-server.sh ~/Downloads/kcdmp.zip
   unzip kcdmp.zip -d /tmp/kcdmp
   # then, from the panel's SFTP details:
   sftp -P <port> <user>@<node>
   sftp> put -r /tmp/kcdmp/linux/* .
   ```

   The egg does not download the archive: the download page has no stable
   direct URL.

5. **Start it.** Watch the first lines of the console: version and protocol
   number, tick rate, the loaded game mode, and one line per data file found or
   missing. Then join with `Direct connect` → `<node address>:<port>`.

## Ports

**UDP only.** The game speaks nothing else, and one allocation is all a server
needs.

Pterodactyl does not translate ports: Wings publishes allocation `P` as `P` on
the host and inside the container, and exports it as `SERVER_PORT`. That is why
the egg starts the server with `--port {{SERVER_PORT}}` — the server binds
whatever port the panel gave you, so the allocation can be any free UDP port,
and moving a server to another port needs no file editing.

(`docker run -p 7800:7777/udp` — any host port onto a fixed container port — is
a Docker feature a Pterodactyl allocation cannot express. Pinning the server to
7777 inside the container would mean every server must be allocated 7777.)

`http_status` is the one TCP listener: the server opens TCP on the same number
for its JSON status page. With only UDP published it is reachable from the
container and the panel only, which is harmless, and `http_status = false` in
`EXTRA_TOML` removes it entirely.

`[server] network_threads` (several UDP ports for 1000+ players) is deliberately
not wired into the egg. If you need it, add the extra allocations and set
`network_ports` in `EXTRA_TOML`.

## How configuration works

KCD:MP reads `server.toml` from its working directory. Pterodactyl has no TOML
parser, so the two halves are split:

- **Rendered into `server.toml` on the first start:** `port`, `name`,
  `password`, `max_players`, `level`, `[gamemode] script`, plus whatever you put
  in `EXTRA_TOML`.
- **Passed on the command line:** `--port {{SERVER_PORT}}`. The flag overrides
  the file, so a changed allocation takes effect on the next start without
  regenerating anything.
- **Passed as environment variables**, which the server reads natively and
  which win over the file: `KCDMP_ADMINS`, `KCDMP_MASTER_URL`,
  `KCDMP_AUDIT_MODE`, `KCDMP_DB_DRIVER`, `KCDMP_DB_URL`.

An existing `server.toml` is **never** rewritten, so edits made in the file
manager survive restarts. Set `RENDER_TOML=1` to regenerate it from the panel
variables — that discards those edits, and it happens on every start until you
set it back to `0`.

The generated file is intentionally small: the server's defaults are sane, and
`server.toml.example` next to it documents all ~80 keys, as does
[the configuration docs](https://docs.kcd-mp.com/getting-started/server-config/).

## Game data

The four exports turn on the server's item, terrain, navigation and collision
features. They are made **on Windows, from an installed copy of the game**, with
the `tools/` in the archive — they cannot be produced in the container.

| File | What it turns on |
| --- | --- |
| `data/combat/items.json` | damage from the game's tables, items by name, the item check |
| `data/heightmaps/<level>.hmap` | the terrain check |
| `data/navmesh/<level>.knav` | NPCs that walk around walls, `FindPath` |
| `data/collision/<level>.kcol` | line of sight, `RayCast`, the floor as ground |

Export the tables first. Upload with **SFTP**, not the web uploader: navmesh and
collision files are large and panels often cap web uploads well below them.
`data/` lives in the container mount, so it survives restarts and image
updates — but a *reinstall* of the server is a different story, see
[egg/README.md](egg/README.md).

## Troubleshooting

**Panel stuck at "Starting", console shows nothing.** The startup detection
matches the real first line,
`KcdMp.Server 0.50.0 (protocol 123) starting: ...`, as
`protocol [0-9]+\) starting`. If a release rewords that line, the panel never
sees the server as ready even though it is running. Compare with the actual line
in the console and adjust the egg's *Startup Detection*.

**Exit code 3 / crash loop.** Expected behaviour, not a bug: `[server]
stall_exit = 30` makes a server that cannot send or receive for 30 seconds end
itself so the panel restarts it. If it loops, the port is the usual cause.

**`--help` stops the server with "unknown argument".** Some flags exist —
`--port`, `--name`, `--max-players`, `--level`, `--password`, `--version`,
`--config` — but there is no help text, and anything unknown is fatal. That is
the fastest way to check whether a flag is supported.

**Players cannot connect but the server is up.** Check that the allocation is
UDP and that `[server] password` is what you think. The port cannot drift: the
egg passes `--port` explicitly.

**`Permission denied` for `./KcdMp.Server`.** The entrypoint re-applies `chmod
+x`, so this only happens if the file is owned by root. Re-run the installer, or
`chown -R container:container /home/container`.

## Limits that are the host's, not the egg's

- **UDP socket buffers.** Linux caps them at `net.core.rmem_max` /
  `net.core.wmem_max` (~0.2 MB on most systems), and neither a container nor a
  panel can raise that. Irrelevant for dozens of players; with hundreds, ask the
  host for `16777216` on both.
- **`[rates] reliable_rate`** defaults to 24 MB/s, which is *more than a 100
  Mbit line carries*. On a small VPS set 5–6 in `EXTRA_TOML`.
- **Memory and CPU** are ordinary: a few hundred MB for a small server.

## Tested with

| Piece | Version |
| --- | --- |
| `KcdMp.Server` | 0.50.0, protocol 123 |
| .NET runtime in the image | `Microsoft.NETCore.App` 10.0.15 |
| Base image | `mcr.microsoft.com/dotnet/runtime:10.0`, 311 MB unpacked |
| Pterodactyl | egg schema `PTDL_v2` |
| Docker | 29.10.0 on Ubuntu 26.04 (WSL2), overlayfs, cgroup v2 |

Verified locally against a bind-mounted copy of the server folder: the image
builds, the server binds UDP 7777, `http_status` answers JSON on TCP 7777, the
master list heartbeat goes out, `server.toml` is rendered once and left alone
afterwards, `data/server.db` and `server.log` are written, and `SIGINT` — what
the egg's `^C` stop sends — shuts down cleanly with exit code 0:

```
[main] [info] database: closed (2 row(s) in 1 transaction(s) this run)
[main] [info] KcdMp.Server stopped after 634 ticks
```

The server also reads commands from stdin, so the panel's console accepts
`help`, `say`, `reload` and the rest directly.

## Credits

KCD:MP and Kingdom Come: Deliverance II belong to their respective authors. This
repository contains only container packaging.
