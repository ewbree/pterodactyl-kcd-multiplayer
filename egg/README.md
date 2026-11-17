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

### If you edit the egg

The panel validates the egg model on save, and a validation failure during
import is returned as a plain **HTTP 500** — not as a field error. Four things
that trip people up:

- `author` must be an **email address**. A display name there fails
  `'author' => 'required|string|email'`; put the name in `_comment` instead.
- `docker_images` values must match the panel's image regex: word characters,
  `# . / - : @` and spaces, with an optional `label|` prefix. The admin form
  also validates the display label separately; it allows only word characters,
  `# . / -` and spaces. For example, `KCD-MP .NET 10` is valid, but
  `KCD:MP (.NET 10)` is not.
- An egg variable may not use a reserved environment name (`SERVER_MEMORY`,
  `SERVER_IP`, `SERVER_PORT`, `ENV`, `HOME`, `USER`, `STARTUP`, `SERVER_UUID`,
  `UUID`).
- A variable that only writes `server.toml` must keep `user_viewable` and
  `user_editable` false, and a run-time variable must be viewable. The checker
  enforces that split, plus the rule that the renderer reads nothing else.

`scripts/check-egg.py` checks all of these, plus the rest of what the importer
reads, and runs in CI:

```sh
python3 scripts/check-egg.py
```

## Create the server

1. Pick the egg, give it a name, and set **Dedicated IP / Port** to a UDP
   allocation. The port you choose here becomes `[server] port` in
   `server.toml` — no manual editing, no port mismatch.
2. Set the creation-time variables — name, password, slots, level, game mode —
   and create it. The rest stay editable in the Startup tab afterwards; the
   five are written into `server.toml` once and then left to the file.
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

### Set when the server is created

These five are asked for on the creation form. They are written into
`server.toml` on the first start and then hidden from the server's Startup tab;
change them in `server.toml` afterwards.

| Variable | Default | Written to |
| --- | --- | --- |
| `SERVER_NAME` | `KCD:MP server` | `[server] name`, shown in the launcher and the public list |
| `SERVER_PASSWORD` | *(empty)* | `[server] password`; empty = open server |
| `MAX_PLAYERS` | `32` | `[server] max_players`; ids run to this minus one |
| `LEVEL` | `klaster` | `[server] level`: `klaster`, `trosecko`, `kutnohorsko` |
| `GAMEMODE` | `gamemodes/freeroam.lua` | `[gamemode] script`; `.lua` or compiled `.dll`, empty = built-in freeroam |

### Available while it runs

Passed to the server as environment variables on every start, and editable in
the Startup tab. None of them is ever written into `server.toml`.

| Variable | Default | Notes |
| --- | --- | --- |
| `KCDMP_ADMINS` | *(empty)* | comma-separated names, e.g. `Henry,Hans` |
| `KCDMP_MASTER_URL` | *(empty)* | empty = private server, announced nowhere; `https://kcd-mp.com/server-list` publishes it |
| `KCDMP_AUDIT_MODE` | `observe` | `observe` logs only, `enforce` takes unexplained items away |
| `KCDMP_DB_DRIVER` | *(empty)* | `mysql` or `postgres`; empty = the game mode runs without a database |
| `KCDMP_DB_URL` | *(empty)* | `mysql://user:pass@host:3306/db` |
| `AUTO_UPDATE` | `1` | `1` installs the newest release on start; `0` never contacts GitHub |
| `SERVER_VERSION` | `latest` | pin a release (`0.50.0`); with auto-update on, moves to exactly that version |
| `GITHUB_TOKEN` | *(empty)* | optional; raises GitHub's anonymous API limit on busy nodes |

The `KCDMP_*` variables are read by the server itself and **override the same
keys in `server.toml`** — the server documents them as the way a panel or
container configures it. See "How configuration works" in the
[top-level README](../README.md).

### About `server.toml`

Published images write `server.toml` only when it does not exist. After that it
is yours: edit it in the panel's file manager or over SFTP, and nothing in the
panel overwrites it. Every key the server has is documented in
`server.toml.example` next to it.

Deleting the file does not strand the server: the next start writes it again
from the values the server was created with. Those stay in the panel's database
as that fallback, which is why hiding them from the Startup tab loses nothing.

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
harmless; `http_status = false` under `[server]` removes the listener.

Extra ports are only needed for `[server] network_threads` (thousands of
players). Add allocations and list them under `[server]` in `server.toml` as
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
- `config.startup`'s `done` entries are **literal substrings** in Wings unless
  they start with `regex:` (`remote/types.go`, `OutputLineMatcher.Matches`). The
  egg matches `listening on udp/`, the line printed after the socket is bound.
  The panel wraps a string value in an array (`EggConfigurationService`), but
  this egg uses the array form directly.
- Wings runs the container as the panel's **pterodactyl user**, not the image's
  `container` user, and chowns `/home/container` before each boot when
  `system.check_permissions_on_boot` is on (the default). The installer's
  `chown` is a fallback for nodes that turn that off.
- A variable that only feeds `server.toml` is hidden after creation with
  `user_viewable: false` / `user_editable: false`. The panel's admin create form
  renders every egg variable (`public/themes/pterodactyl/js/admin/new-server.js`)
  while the server's Startup tab lists only `user_viewable` ones and refuses to
  edit the rest (`StartupController`), so the same variable is a creation field
  and nothing else afterwards. Note that the **admin** server page still shows
  them: `ServerViewController::startup` passes every variable to the blade.
- `scripts/check-egg.py` asserts all of the above and runs in CI before the
  image is built.

## Reinstalling

The install script creates `server.toml`'s directory structure, fixes ownership
and the executable bit, and touches nothing else — it never deletes your
`data/`, `server.toml` or game modes.

1.x's **Reinstall Server** refuses to run when the server directory is not
empty unless you confirm/force it, and that is the behaviour you want: uploads
are not wiped. If it does run, the server files you uploaded stay where they
are (the installer changes permissions, not contents), and the settings the
server was created with remain the fallback for a regenerated `server.toml`.

Reinstalling does not update the server files either — that is what
`AUTO_UPDATE` does on the next start, and it needs no reinstall. A reinstall is
only useful to reset permissions or recreate `data/` and `gamemodes/`.
