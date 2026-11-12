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

## Docker on Linux (amd64)

The root Dockerfile builds the pinned BYOND version, native rust-g/dreamluau
libraries, TGUI, behavior trees, and both production programs. The final image
runs as UID 10001 and keeps the supervisor API inside the container. The lobby
and child DreamDaemon ports are the only published endpoints.

Copy `.env.example` to `.env`, set `BABYLON_PUBLIC_HOST` to the hostname/IP
players can reach, and set `BABYLON_ADMINS` to a comma-separated list of BYOND
accounts. These grant lobby administration and full game-admin rights in every
world they join (granted on admission, for that world's run).

```sh
# Local checkout: automatically includes compose.override.yml, builds :local.
docker compose up -d --build
docker compose logs -f
docker compose down

# Published image: explicitly omit the automatic local override.
BABYLON_IMAGE_TAG=unstable docker compose -f compose.yml up -d
# After a release exists, use latest or a literal release tag such as 1.0.0.
BABYLON_IMAGE_TAG=1.0.0 docker compose -f compose.yml up -d
```

Compose 2.24.4+ is required. `compose.override.yml` uses
`image: !override ghcr.io/scolastico/babylon13:local` and `pull_policy: build`;
it cannot select a downloaded game image even if `BABYLON_IMAGE_TAG` is set.
Base images and pinned build dependencies are still downloaded when building.
CI selects the independent kernel.org Ubuntu mirror with the Docker build
argument `UBUNTU_MIRROR` to avoid the current Canonical DNS outage. A normal
local build keeps Ubuntu's default mirrors; all mirrors use Ubuntu's signed
repository metadata and the image's existing Ubuntu archive keys.

The named `babylon-data` volume holds the database, worlds, logs and every
checkpoint. Keep it when replacing images; `down -v` deletes this volume.
The container locks its data volume so two instances cannot manage it at once.
For a bind mount, make the directory writable by UID 10001. Existing private
PoC saves are not automatically imported.

Set `BABYLON_HUB_LISTED=true` to list the lobby on the BYOND hub (default:
upstream's shared `Exadv1.spacestation13` entry; override with `BABYLON_HUB` and
`BABYLON_HUB_PASSWORD`). Child worlds always start with DreamDaemon's
`-invisible` flag, because they only admit lobby tickets. The hub's own player
counter only sees lobby connections, so the lobby refreshes its hub status every
30 seconds with the total across the lobby and all running worlds. The lobby
never sleeps while empty, so the entry stays listed without players. It starts
invisible and only becomes visible once the configured hub password is set: a
world first announced with a wrong password is listed only while someone is
connected.

The status line is the HTML template `BABYLON_HUB_STATUS`, so links and wording
can be changed without a rebuild. Placeholders: `{name}` (`BABYLON_SERVER_NAME`),
`{players}` (total), `{lobby_players}`, `{world_players}`, `{running_worlds}`,
`{running_worlds_label}` (for example "2 running worlds"; both count admin worlds
like any other), `{admin_worlds}` (how many of them are admin worlds),
`{max_running_worlds}` and `{address}` (the lobby's byond:// address). The
default is
`<b>{name}</b> &#8212; persistent station building<br>Players: <b>{players}</b> ({world_players} in {running_worlds_label}, {lobby_players} in the lobby)`.

Logs: `docker logs` is the single log of the cluster. Every line is prefixed
with its source: `[supervisor]` (world starts, stops, saves, joins and every
lobby action, plus errors), `[lobby]` (the lobby's DreamDaemon: connects,
handoffs to worlds, failed actions) and `[world <name> <id>]` (each child
world's DreamDaemon output, including its round `dd.log` with runtime errors).
The per-world files under `/data/worlds/<id>/` stay as before.

### Discord

The supervisor also runs an optional Discord bot (discord.py, in the same
process). It starts when `BABYLON_DISCORD_TOKEN` and `BABYLON_DISCORD_GUILD_ID`
are set; `BABYLON_DISCORD_FEATURES` picks what it does:

| Feature | What it does | Needs |
| --- | --- | --- |
| `link` | `/link`, `/unlink`; moderators get `/whois`. Links a Discord account to a BYOND account. | |
| `roles` | Buttons with `custom_id` `babylon:role:<role id>` toggle a role from `BABYLON_DISCORD_SELF_ROLES`; `babylon:color:<role id>` picks one of `BABYLON_DISCORD_COLOR_ROLES` (exclusive), `babylon:color:none` removes it. | role IDs |
| `voice` | Joining the voice lobby creates a room for the member, which is deleted when empty. | `_VOICE_LOBBY_CHANNEL` |
| `logs` | Member, message, voice and moderation logs, each in its own channel (unset channels are skipped). | log channels |
| `status` | A status message (players, running worlds; private worlds stay anonymous), updated every minute and marked offline on shutdown. | `_STATUS_CHANNEL` |
| `gamelog` | Every `[supervisor]` log line, batched into a channel. | `_GAME_LOG_CHANNEL` |
| `ahelp` | Every adminhelp from a world becomes a message with a thread in a staff channel: the player's messages and replies, and in-game admins' answers. Staff answer with the "Reply" button; the player gets it as an admin PM (shown as "Administrator" unless `SHOW_IRC_NAME` is set). "Close ticket" closes it in the world and archives the thread. The player is told "Created an adminhelp for you." and, if any member of `_AHELP_ROLES` (default: the staff roles) is online on Discord, how many; that count needs the bot's Presence Intent, without it the bot runs and the count is left out. | `_AHELP_CHANNEL`, `_STAFF_ROLES`, optional `_AHELP_ROLES` |
| `tickets` | An "Open a ticket" button in a read-only channel opens a private channel for the member and `BABYLON_DISCORD_STAFF_ROLES`. Creator and staff can add people; closing it sends a `.txt` transcript to the creator by DM and to the ticket log. | `_TICKET_PANEL_CHANNEL`, `_TICKET_LOG_CHANNEL`, `_TICKET_CATEGORY`, `_STAFF_ROLES` |

`/status` is always available. In the developer portal, enable the
**Server Members Intent** for `link`, `logs` and `ahelp`, and the **Message
Content Intent** for `logs`; without them Discord refuses the connection and the
bot stays off (the game keeps running). The **Presence Intent** is optional: with
`ahelp`, the bot asks for it to count online admins and runs without the count
when it is not enabled. The bot's role must be above every role it
assigns. Voice rooms and open tickets are remembered in the data volume.

Linking: **Link Discord** in the lobby shows a one-time code (valid 10
minutes) to type as `/link code:ABCD-EFGH`. One Discord account links to one
BYOND account. `BABYLON_REQUIRE_DISCORD_TO_CREATE` and
`BABYLON_REQUIRE_DISCORD_TO_JOIN` (both off by default, independent) make a
linked account a condition for creating, and for joining or starting worlds;
lobby admins are exempt. While the bot's member cache is ready, a linked
account must also still be on the Discord server. The lobby shows the link
state and the requirements, with Link, Unlink and Discord invite buttons.

`BABYLON_DISCORD_INVITE` also adds a **Discord** button to the in-game escape
menu (Resources); `BABYLON_RULES_URL` sets its **Rules** button. Babylon hides
upstream's /tg/station wiki, forum, rules and config links.

All supported settings and defaults are listed in `.env.example`: lobby and
world ports, internal API port, admin CSV, global/per-owner world limits,
player limits, retained checkpoints, unused-world expiry, admission lifetime,
empty grace and startup/shutdown timeouts. World port mappings must use the
same host/container numbers because those ports are advertised to clients.
For an advanced custom SPLURT config, mount a directory read-only and set
`BABYLON_CONFIG_DIRECTORY` to its container path; it must contain `config.txt`
including `comms.txt`. The supervisor generates each child's control key.
`BABYLON_DATA_DIRECTORY` defaults to `/data` and should remain on a volume.

SIGTERM closes the lobby, saves/stops worlds, and waits for confirmed child
exits. Compose grants ten minutes by default. If changing timeouts, allow more
than startup plus final-save time with `BABYLON_STOP_GRACE_PERIOD`. For plain
Docker use `docker stop --time 600`; Docker's default short timeout can kill a
world during its save. On save failure the process stays alive and retries;
Docker can still force-kill it when its grace period expires.

### Image publishing

`.github/workflows/babylon-containers.yml` compiles production, test and
ordinary upstream builds and runs Python/browser tests for PRs and pushes to
`main`/`master`. Publication is restricted to the default branch (currently
`master`) and published GitHub releases. PRs never log into GHCR.

- A successful default-branch push replaces `:unstable`. A temporary
  `:unstable-<commit>` marker permits cleanup even after a cancelled run; all
  older marked unstable image versions are deleted after successful publishing.
- Publishing release tag `1.0.0` attaches both `:1.0.0` and `:latest` to the
  same image. If the released commit already has an `:unstable-<commit>` image
  (normally: the release is the latest default-branch commit), the release waits
  for that commit's push run, then only retags that image instead of compiling
  and building again. Tag changes of all runs share one concurrency group.
- After a successful release, the workflow can trigger a Komodo procedure (for
  example a redeploy) through its GitLab-style webhook. Set the action secrets
  `KOMODO_WEBHOOK_URL` (listener URL ending in `/<default branch>`) and
  `KOMODO_WEBHOOK_SECRET`; without both the step is skipped. Set the action variable
  `KOMODO_NOTIFY_UNSTABLE` to `true` to also trigger it after every published
  unstable build of the default branch (for deployments tracking `:unstable`). Release tags are literal Docker tags; `v1.0.0` remains `:v1.0.0`.
- Main/default-branch runs cancel older runs in their concurrency group. PRs
  are grouped by ref; release runs use separate groups and are not cancelled.
- Cleanup never deletes versions with `latest`, a release tag, or any other
  non-unstable tag. Images use a single amd64 manifest without extra attestation
  manifests, so obsolete unstable versions do not leave dangling child images.

The workflow uses `GITHUB_TOKEN` with package-write permission and an OCI
source label linking the package to this repository. For a pre-existing GHCR
package, the repository must have package-admin access for cleanup. GHCR
visibility is managed in the package's settings; a public repository does not
automatically make a newly created package public. Private images need registry
login. Existing documentation and map-viewer workflows are unchanged.

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

Once configured and compiled, double-click **Start Babylon Server.cmd** or
**Stop Babylon Server.cmd** in the repository root. They find Python through
`uv`, the Windows `py` launcher, or `python` on PATH. The PowerShell entry points
also accept `-Python` for an explicit executable path.

Start reports an already-running cluster instead of launching duplicates.
Stop closes the lobby to prevent new starts, waits for any starting worlds to
initialize, requests a final save/stop for every running world, and waits for
confirmed exits before stopping the supervisor. A save failure or timeout
leaves the supervisor and affected children running for recovery; it never
force-kills a world. The scripts do not delete worlds or checkpoints.

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
- The selected lobby tab has a heading, description and active highlight.
  World cards distinguish online/offline/startup/error states and show the
  player's role. Join immediately displays progress before server preparation.
- Owners create worlds, edit settings while stopped, grant/remove members,
  and request an immediate save-and-stop. Admins can see/join/manage every
  world regardless of visibility/password, and are full game admins inside
  every world they join. Managers and delegated permissions are not yet added.
- Limits configure total running worlds, players per world, worlds per owner,
  and running worlds per owner. Worlds owned by an admin (`BABYLON_ADMINS`) do
  not count towards the global running-world limit; they only need a free port
  and are shown separately on the Discord status, e.g. "2/4 (+1)"; the hub lists them as running worlds. A member or admin starting another person's
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
- `delete_unused_worlds_after_days` defaults to **60**; set **0** to disable
  automatic expiry. The supervisor checks hourly and only expires stopped
  worlds. Starting, joining, connected players and owner management actions
  update activity; merely browsing the list does not. Expiry removes the world,
  all checkpoints and memberships. A persistent deletion queue safely resumes
  interrupted filesystem cleanup. Existing databases migrate activity from
  their creation time and recorded actions.

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

Only a player's first chassis receives starter equipment. Respawn constructs
an empty replacement, including no replacement bag or holiday hat. Recover
dropped tools, craft replacements, or restore/reset the world if necessary.
The Return to lobby HUD action comes before Self-destruct and is also available
while waiting as a ghost. Returning leaves the body and inventory in the world.
Ghost spawner/minigame interfaces are disabled; DNR and corpse re-entry remain.

Fresh-map preparation derives the upstream wreck and applies two Babylon-only
overlays with `map_overlay.py`: `_maps/babylon/vault_annex.json` splices the
generation interlock, the inner vault doors and the sealed continuity annex
north of the vault into the map, and `_maps/babylon/lore.json` places fourteen
lore objects (open papers, flat satchels hidden under floor tiles, sealed
crates in the vault, and archive boxes in the annex). Hidden satchels only go
under intact floor tiles, never bare plating, and ghosts can neither read a lore
paper nor look inside a lore box. Existing saved builds are not
overwritten or reseeded. Draft text and the canon live in `modular_babylon/lore/`.
Their types and locations persist through saves; there is no separate
repeatable paper spawner.

Vault progression: the outer vault's generation interlock stores and consumes
nothing. It reads live generation on the cable beneath it, subtracts SMES
output on that powernet, and releases the locks only after that figure holds
at or above 2 MW for 30 seconds, which in practice means a running reactor.
The inner doors are on a separate continuity interlock in the first chamber: a
conscious human starts a 60-minute real-time sequence and must stay alive for
all of it, or it resets. Once opened, the inner doors stay open and the fact is
saved with the world. The watchdog server in the annex prints a core log built
from the world's own re-seat and unlock history.

Survival: in Babylon, hunger and thirst are lethal for living crew. Below the
starving and parched thresholds a human takes ramping brute and toxin damage
each second, with a chat warning every 30 seconds. Drones are unaffected.
The standalone preparation script now also requires Python 3.11+ (`-Python`
can supply its path; otherwise it uses uv's Python or the installed `python`).

Babylon uses one station floor with no vertical adjacency, no mining map,
no generated space/away-mission levels, events, gamemode tracks or weather.
`ABSOLUTE_MINIMUM` disables the separate upstream Interlink/cafe loader and its
associated round-start shuttles. Lavaland is not loaded; a future exploration/
shuttle extension can add it without reintroducing unrelated station maps.
Atmospherics, power, machinery, research and construction remain active.
Minimal CentCom/reservation support levels and upstream plane bookkeeping
remain because SS13 systems depend on them. This does not yet remove all
unused upstream types or make a one-z DreamDaemon. The lobby itself contains
none of those systems.

## Showcase worlds

Visibility choices are **private**, **showcase**, **password**, and **public**.
Showcase worlds are listed in the lobby. Owners, members and server admins
join as normal players; guests can **Visit showcase** while it is online.
Guests cannot start an offline world.

Visitors appear to living players as visible, nonphysical ghosts. They can
move through the station and chat locally with nearby players, or use OOC.
They cannot operate machinery, use items, drag objects, enter a body, use
ghost powers, or trigger object/context verbs. Chat is sent only to clients
and cannot activate speech-controlled machinery. The visitor HUD has a
Return to lobby button. Visitor bodies are temporary and never receive a
drone, inventory or persistent player-roster entry. Existing saved bodies
remain untouched when a former player visits as a guest.

The supervisor selects the play mode when redeeming the single-use ticket;
connection parameters cannot request builder access. Members added while
visiting must reconnect through the lobby to enter as players. Visitors count
toward the world capacity and online population and follow its AFK timeout.

## AFK disconnection

Worlds disconnect inactive players after 900 seconds (15 minutes) by default.
Set `afk_timeout_seconds` in the supervisor JSON, or
`BABYLON_AFK_TIMEOUT_SECONDS` in Docker/Compose; `0` disables it. Changes apply
when a world next starts. Standalone worlds accept the world parameter
`babylon-afk-timeout=<seconds>` with the same default.

Players receive one chat warning up to 60 seconds before disconnection. Moving
or interacting resets BYOND's inactivity counter and cancels the countdown.
The policy includes ghosts, owners and admins, and replaces SPLURT's separate
`KICK_INACTIVE` setting in Babylon worlds. Bodies and equipment are preserved;
players reconnect through the lobby. Once everyone disconnects, the normal
empty-world grace period triggers saving and shutdown. Lobby menu connections
are not subject to this world timeout.

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

## Deleting worlds

Owners and server admins can permanently delete a stopped world using
**Delete world** on its lobby card. The confirmation covers every checkpoint.
Running worlds must be saved/stopped first. Deletion revokes memberships,
tickets and sessions, releases the owner's world quota, and removes that
world's data directory. Filesystem failures retain a cleanup journal for retry.

The lobby shows a loading panel before slow requests, including deletion,
checkpoint restoration, settings and membership changes. Shutdown stays on
that panel until the final save and process exit are confirmed, or an error
or timeout is reported. Cancelling a dialog returns to the world list.
Background status polls update the existing browser document only when its
content changes; each tab keeps its scroll position. Late poll responses
cannot overwrite an action's loading state.

## Persistence repairs carried over from the local prototype

Checkpoints retain air-alarm threshold datums and selected mode, cycling-pump
targets/side links/removability, portable-canister connector attachments, and
computer/frame circuit-board references. Restored doors settle interrupted
animations at their saved physical position. Saved pumps rebuild their links
without running fresh-install door-opening sequences. Reopening a world does
not seed round-start vermin, hidden loot, or weakpoints.

Older saves recover missing circuit references from their saved contents and
missing canister attachments from an anchored device on the same connector
tile. An explicit disconnected state in a newer save stays disconnected.
Legacy Babylon cycling pumps are recoverable as removable player-built pumps;
the original wreck contains no such pumps. Settings never recorded by an older
save, such as custom alarm thresholds, cannot be reconstructed retroactively.

Invalid material entries are removed before UI generation and stock accounting
without changing valid material quantities. This prevents the autolathe's
`materials: null` UI crash. Fault injection and arbitrary inspection remain
confined to the separate `babylon-test.dme` build.

The explicit legacy regression uses an external workshop checkpoint read-only
and stages its own world/config/binaries under a new test directory:

```powershell
python services/supervisor/smoke_reload_fixes.py `
  --dreamdaemon C:\BYOND\bin\dd.exe `
  --config-directory C:\BabylonTestConfig `
  --checkpoint C:\BabylonFixtures\workshop-save `
  --data-directory data\babylon-supervisor\reload-regression-1 `
  --port 1459
```

Compile `babylon.dme` and `babylon-test.dme` first. The fixture needs an R&D
console, autolathe, alarm, cycling airlock pump, and at least two connected
canisters. The regression strips the newly added fields in its disposable
copy, then checks legacy recovery, real tool operations, a second player's
inventory, and a save/reload with the new fields. It refuses occupied ports
and existing test directories and never writes to the supplied checkpoint.
