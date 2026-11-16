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

`meta.update_url` points at the copy of this egg in the repository, so a panel
that checks egg updates can tell you when the egg itself changed.

## Create the server

1. Pick the egg, give it a name, and set **Dedicated IP / Port** to a UDP
   allocation. The port you choose here becomes `[server] port` in
   `server.toml` — no manual editing, no port mismatch.
2. Set the variables you care about (see below) and create it.
3. Start it on the console page. `AUTO_UPDATE=1` downloads the newest release
   into `/home/container` on the first start; there is no upload step unless you
   want one.
4. To upload instead, SFTP the *contents* of the archive's `linux/` folder into
   `/home/container`. It should end up as `/home/container/KcdMp.Server`,
   `/home/container/server.toml.example`, `/home/container/gamemodes/`,
   `/home/container/sdk/`, `/home/container/tools/`. Set `AUTO_UPDATE=0` so the
   next start does not replace them.

SFTP stays the way to add game data, custom game modes and anything else of your
own; the updater only writes files that exist in the release archive.

## Variables

| Variable | Default | Notes |
| --- | --- | --- |
| `SERVER_NAME` | `KCD:MP server` | shown in the launcher and the public list |
| `SERVER_PASSWORD` | *(empty)* | empty = open server |
| `MAX_PLAYERS` | `32` | slots; ids run to this minus one |
| `LEVEL` | `klaster` | `klaster`, `trosecko`, `kutnohorsko` |
| `GAMEMODE` | `gamemodes/freeroam.lua` | `.lua` or compiled `.dll`; empty = built-in freeroam |
| `KCDMP_ADMINS` | *(empty)* | comma-separated names, e.g. `Henry,Hans` |
| `KCDMP_MASTER_URL` | *(empty)* | empty = private server, announced nowhere; `https://kcd-mp.com/server-list` publishes it |
| `KCDMP_AUDIT_MODE` | `observe` | `observe` logs only, `enforce` takes unexplained items away |
| `KCDMP_DB_DRIVER` | *(empty)* | `mysql` or `postgres`; empty = the game mode runs without a database |
| `KCDMP_DB_URL` | *(empty)* | `mysql://user:pass@host:3306/db` |
| `EXTRA_TOML` | *(empty)* | appended verbatim to the generated `server.toml` |
| `RENDER_TOML` | `0` | `1` rewrites `server.toml` from these variables on every start |
| `AUTO_UPDATE` | `1` | `1` installs the newest release on start; `0` never contacts GitHub |
| `SERVER_VERSION` | `latest` | pin a release (`0.50.0`); with auto-update on, moves to exactly that version |
| `GITHUB_TOKEN` | *(empty)* | optional; raises GitHub's anonymous API limit on busy nodes |

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

### About auto-update

`AUTO_UPDATE` renders as a real on/off switch: the panel turns any variable
whose rules contain `in:0,1` into a `Switch`
(`resources/scripts/components/server/startup/VariableBox.tsx`), so no boolean
field type is needed. On every start the entrypoint compares the installed
`KcdMp.Server` with the release GitHub reports. If they differ it downloads the
archive, verifies the published SHA-256, and writes only the files that exist in
the archive — `server.toml`, `data/` and your own modes are never touched.

Failures (no network, rate limit, bad checksum, disk full) are logged and the
start continues with the files already on disk. `SERVER_VERSION` pins the
release; see [Updates](../README.md#updates) for the protocol-mismatch caveat
and the one thing an update cannot do (re-export the game data).

Adding these variables to an egg that already has servers works: the panel
builds a server's environment from the egg's variables and falls back to each
variable's default when the server has no stored value
(`EnvironmentService::handle`), so existing servers pick up `AUTO_UPDATE=1` on
their next start.

## Ports

**UDP only** — the game speaks nothing else. One allocation is all a server
needs, and the usual choice is 7777 on both sides (`0.0.0.0:7777/udp →
7777/udp`), since `[server] port` defaults to 7777 anyway.

Pterodactyl does not translate ports: Wings publishes allocation `P` as `P` on
the host and in the container, and exports it as `SERVER_PORT`. The startup
command is `./KcdMp.Server --port {{SERVER_PORT}}`, so the server binds whatever
the panel allocated — moving a server to another port takes effect on the next
start with no file editing.

(`docker run -p 7800:7777/udp` is a Docker feature an allocation cannot express:
pinning the server to 7777 inside would require every server to be allocated
7777.)

`http_status` opens TCP on the same number for the JSON status page. With only
UDP published it is reachable from the container and the panel only, which is
harmless; `http_status = false` in `EXTRA_TOML` removes the listener.

Extra ports are only needed for `[server] network_threads` (thousands of
players). Add allocations and list them in `EXTRA_TOML` as
`network_ports = [27016, 27020]`.

## 1.x compliance

Checked against the source rather than from memory — panel `1.0-develop`,
wings `develop`:

- `EggParserService::fillFromParsed` reads exactly `name`, `description`,
  `features`, `docker_images` (a map), `file_denylist`, `meta.update_url`,
  `config.files` / `config.startup` / `config.logs` / `config.stop` (each a JSON
  **string**), `startup`, and `scripts.installation.script` / `container` /
  `entrypoint`. All present, all the right shape.
- `meta.version` must be `PTDL_v1` or `PTDL_v2`. This is `PTDL_v2`, so the
  panel's v1→v2 conversion (which would rewrite the image list and force
  `field_type`) is correctly skipped.
- Variables are created with `EggVariable::forceCreate`, so each carries the
  columns the model expects, `field_type` included, and `env_variable` is
  `[A-Z0-9_]+` and unique.
- The stop command `^C` is mapped by Wings to `SIGINT`
  (`environment/docker/power.go`), which is what the server's clean shutdown
  needs — verified as exit code 0 with the database closed.
- Wings runs the container as the panel's **pterodactyl user**, not the image's
  `container` user, and chowns `/home/container` before each boot when
  `system.check_permissions_on_boot` is on (the default). The installer's
  `chown` is a fallback for nodes that turn that off.
- `scripts/check-egg.py` asserts all of the above and runs in CI before the
  image is built.

## Reinstalling

The install script creates `server.toml`'s directory structure, fixes ownership
and the executable bit, and touches nothing else — it never deletes your
`data/`, `server.toml` or game modes.

1.x's **Reinstall Server** refuses to run when the server directory is not
empty unless you confirm/force it, and that is the behaviour you want: uploads
are not wiped. If it does run, the server files you uploaded stay where they
are (the installer changes permissions, not contents), and the panel's
variables remain the source of truth for a regenerated `server.toml`.

Reinstalling does not update the server files either — that is what
`AUTO_UPDATE` does on the next start, and it needs no reinstall. A reinstall is
only useful to reset permissions or recreate `data/` and `gamemodes/`.
