# Experimental lobby and supervisor

This implementation is for local development. It is not a production release.
The private Babylon prototype is separate and is not migrated or restarted.

## Components

- `babylon-lobby.dme` compiles a standalone, one-tile BYOND menu. It includes no
  SS13 code, maps, subsystems, TGUI build or native libraries. Its browser lists
  active, owned, shared and discoverable worlds, with creation and owner controls.
- `services/supervisor/supervisor.py` runs on Python 3.11+ using its standard
  library and SQLite. It owns world metadata, roles, quotas, port assignment,
  child processes and admission. Its HTTP API binds only to loopback.
- `babylon.dme` runs one Babylon station per process. Native Topic control and
  a small early client-admission hook connect it to the supervisor.

Players authenticate with BYOND; ckeys are taken from server-side clients.
The API trusts the lobby credential, not arbitrary HTTP callers claiming ckeys.
Do not expose the supervisor API to the internet or publish configuration files.
Public connections use the lobby port and the configured child port range.
The example binds game ports to loopback too. To host for other machines, set
`public_host` to the reachable hostname and `bind_address` to the desired
interface (for example `0.0.0.0`), and update `lobby_address` accordingly.

## Windows setup

Build `babylon.dme -DCBT` with the pinned BYOND version, native dependencies and
upstream TGUI assets as described in the repository build instructions. Compile
`babylon-lobby.dme` too. Supply a clean, operator-controlled SPLURT configuration
directory; inherited SQL, external integrations, hub settings, bans and admin
configuration remain the operator's responsibility. Do not use a production
server's live configuration or secrets for a test cluster.

```powershell
powershell -File tools/babylon/Initialize-Cluster.ps1 `
  -DreamDaemon C:\BYOND\bin\dd.exe `
  -ConfigDirectory C:\BabylonConfig `
  -Admins YourByondAccount

# Review babylon-supervisor-config.json, especially paths, host and quotas.
powershell -File tools/babylon/Start-Cluster.ps1 -Python C:\Python\python.exe
```

Initialization generates a fresh shared lobby credential in two ignored JSON
files. It refuses to overwrite them. Admin accounts come only from the supplied
`-Admins` list; no account is automatically granted access.

For manual operation, run Python with
`services/supervisor/supervisor.py --config babylon-supervisor-config.json` and
DreamDaemon with `babylon-lobby.dmb 1361 -trusted -close -params
"lobby-config=babylon-lobby-config.json"` from the checkout root. On Linux,
configure the native-library/executable paths and use these manual commands.

The supervisor can restart while children remain alive. It stores run IDs,
per-run control credentials and PIDs in SQLite and checks authenticated child
identity before trusting status. Keep its data directory private. Lobby and
supervisor process IDs/logs are under that directory. Stop worlds through the
lobby before stopping the cluster processes. Do not kill a child to save it.

## Rules and controls

- Private worlds are visible only to their owner, members and server admins.
  Public worlds accept signed-in accounts; password worlds are discoverable
  and require a password for guests. Explicit members bypass passwords.
- Guests can join worlds that are already running, but cannot start stopped
  worlds. Only owners, members and server admins can start a world.
- Owners create worlds, edit settings while stopped, grant/remove members,
  and request an immediate save-and-stop. Admins can see/join/manage every
  world regardless of visibility/password. These permissions do not grant
  SPLURT game-admin powers. Managers and delegated permissions are not yet added.
- Limits configure total running worlds, players per world, worlds per owner,
  and running worlds per owner. A member or admin starting another person's
  world uses that world's owner quota. Admins bypass join capacity so they can
  investigate a full world; world creation/start quotas still apply.
- Concurrent join requests share one startup. Settings are validated by the
  supervisor; the browser cannot choose filesystem paths or executable options.
- Tickets are random, stored as hashes, single use and expire after 60 seconds
  by default. They bind the authenticated ckey, world ID and run ID. Capacity
  includes pending tickets and recently redeemed admissions. Access is checked
  again at redemption. Direct connections without a ticket fail before normal
  client setup. A disconnected player obtains a new ticket through the lobby.
- Empty worlds save and stop after a configurable grace period (default 120s).
  Connected ghosts count; abandoned bodies do not. Pending tickets/admissions
  postpone empty shutdown. Normal physics and drone controls remain paused
  from final checkpoint through exit. Save failure keeps the child alive and
  displays an error; the owner can inspect logs and retry Stop.
- Force stop blocks new admissions immediately, saves, offers connected
  players a redirect to the lobby, and exits three seconds later, disconnecting
  anyone who declines the redirect. It does not discard unsaved progress.
- `kept_save_points_per_world` controls retained checkpoints, including the
  current one, and defaults to **4**. It must be a positive integer. Older
  committed generations are removed after a completed save and on startup for
  stopped worlds. Only complete generations at or before the current checkpoint
  are offered for restore.
- Owners/admins can select **Saved checkpoints / rollback** on a stopped world.
  The confirmation warns that the entire world is rewound and **all newer
  checkpoints are permanently deleted**. Members/guests cannot rewind it.
  A stale selection is rejected if the history changed while confirming.
  Rollback atomically changes the current checkpoint; a recovery journal
  completes interrupted deletions before another start. The next Join stages
  the selected map and state, replacing cached startup data.

## Persistence and size

Every world gets its own UUID directory, config and control key. On startup,
the driver stages the canonical wreck or its last committed checkpoint.
Mutable maps, data, logs, config and assets are isolated between children.
The current deployment copies map/asset directories; shared immutable asset
distribution and binary-version pinning/upgrades remain future work.

Checkpoint format 6 adds a ckey-indexed drone roster. Inventories, appearance
and respawn cooldown belong to each player; legacy format-5 owner data can
still load. Disconnected drones remain in the world and can be damaged. On
reconnect the player receives their saved drone or pending respawn state.
An enclosed drone is restored on its enclosing floor tile, preserving its
inventory without trying to reconstruct an active ventcrawl/container session.

Babylon uses one station floor with no vertical adjacency, no mining map,
no generated space/away-mission levels, events, gamemode tracks or weather.
Atmospherics, power, machinery, research and construction remain active.
Minimal CentCom/reservation support levels and upstream plane bookkeeping
remain because SS13 systems depend on them. This does not yet remove all
unused upstream types or make a one-z DreamDaemon. The lobby itself contains
none of those systems.

## Validation

```powershell
python -m unittest discover -s services/supervisor -v

# Compile babylon-test.dme first. Disposable worlds only; never publicly host it.
python services/supervisor/smoke_native.py `
  --dreamdaemon C:\BYOND\bin\dd.exe `
  --config-directory C:\BabylonTestConfig `
  --data-directory C:\BabylonTests\new-empty-test-directory
```

The explicit native smoke starts a fresh real child, exercises authenticated
HTTP admission from DM, ticket replay rejection, a second drone/inventory and
its death/respawn state, then saves/stops/restarts and checks the roster again.
It leaves logs/checkpoints for inspection. It refuses an existing test directory
and occupied API/child ports. Unit tests cover access, limits, concurrency,
offline edits, membership removal, restart reconciliation and failed saves.

Still needed before public hosting: real multi-client UI/admission playtesting,
abuse/load testing, operational backup/restore tooling, stronger crash/launch
reconciliation, schema migrations, moderation/bans, delegated manager roles,
and a controlled update policy for worlds saved by older game builds. Worlds
are isolated processes/directories, not an OS security sandbox.
