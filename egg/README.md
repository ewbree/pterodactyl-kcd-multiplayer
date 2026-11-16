# The egg

`egg-kcd-mp.json` is a Pterodactyl **1.x** egg (`PTDL_v2`). 2.0 can import 1.x
exports, so this file works there too.

## Import

Admin → Nests → pick or create a nest → **Import Egg** → upload
`egg-kcd-mp.json`.

Two things the import does not set for you:

- **Docker image.** It points at `ghcr.io/ewbree/kcdmp:10.0`. If your image
  lives somewhere else, edit the egg's *Docker Images* field.
- **Tags.** Imported eggs have none; add whatever your panel uses.

## Create the server

1. Pick the egg, give it a name, and set **Dedicated IP / Port** to a UDP
   allocation. The port you choose here becomes `[server] port` in
   `server.toml` — no manual editing, no port mismatch.
2. Set the variables you care about (see below) and create it.
3. Upload the server: SFTP the *contents* of the archive's `linux/` folder into
   `/home/container`. It should end up as
   `/home/container/KcdMp.Server`, `/home/container/server.toml.example`,
   `/home/container/gamemodes/`, `/home/container/sdk/`, `/home/container/tools/`.
4. Start it on the console page.

If `KcdMp.Server` is missing the install still succeeds, and the console says so
on the next start — the egg does not download the archive, because the download
page has no stable direct URL.

## Variables

| Variable | Default | Notes |
| --- | --- | --- |
| `SERVER_NAME` | `KCD:MP server` | shown in the launcher and the public list |
| `SERVER_PASSWORD` | *(empty)* | empty = open server |
| `MAX_PLAYERS` | `32` | slots; ids run to this minus one |
| `LEVEL` | `klaster` | `klaster`, `trosecko`, `kutnohorsko` |
| `GAMEMODE` | `gamemodes/freeroam.lua` | `.lua` or compiled `.dll`; empty = built-in freeroam |
| `KCDMP_ADMINS` | *(empty)* | comma-separated names, e.g. `Henry,Hans` |
| `KCDMP_MASTER_URL` | `https://kcd-mp.com/server-list` | empty = private server, announced nowhere |
| `KCDMP_AUDIT_MODE` | `observe` | `observe` logs only, `enforce` takes unexplained items away |
| `KCDMP_DB_DRIVER` | *(empty)* | `mysql` or `postgres`; empty = the game mode runs without a database |
| `KCDMP_DB_URL` | *(empty)* | `mysql://user:pass@host:3306/db` |
| `EXTRA_TOML` | *(empty)* | appended verbatim to the generated `server.toml` |
| `RENDER_TOML` | `0` | `1` rewrites `server.toml` from these variables on every start |

The `KCDMP_*` variables are read by the server itself and **override the same
keys in `server.toml`** — the server documents them as the way a panel or
container configures it. Everything else is written into `server.toml` once.
See "How configuration works" in the [top-level README](../README.md).

### About `RENDER_TOML`

Published images render `server.toml` only when it does not exist yet, so a file
edited in the panel's file manager is kept forever. That means a later change to
`SERVER_NAME` (say) does nothing until you regenerate:

- set `RENDER_TOML=1`, restart once, then set it back to `0`; or
- edit `server.toml` directly and skip the panel variables entirely.

Leaving it at `1` makes the panel own the whole file and discards edits on every
restart — fine if you never edit it by hand, dangerous if you do.

## Ports

One **UDP** allocation is enough: the game listens on it, and the `http_status`
endpoint listens on the same number over TCP. Stock 1.x allocations are not
protocol-specific, so both are covered.

The startup command is `./KcdMp.Server --port {{SERVER_PORT}}`, so the
allocation always wins over `[server] port` in `server.toml` — changing the
allocation takes effect on the next start, with no file editing.

Extra ports are only needed for `[server] network_threads` (thousands of
players). Add allocations and list them in `EXTRA_TOML` as
`network_ports = [27016, 27020]`.

## Reinstalling

The install script creates `server.toml`'s directory structure, fixes ownership
and the executable bit, and touches nothing else — it never deletes your
`data/`, `server.toml` or game modes.

1.x's **Reinstall Server** refuses to run when the server directory is not
empty unless you confirm/force it, and that is the behaviour you want: uploads
are not wiped. If it does run, the server files you uploaded stay where they
are (the installer changes permissions, not contents), and the panel's
variables remain the source of truth for a regenerated `server.toml`.
