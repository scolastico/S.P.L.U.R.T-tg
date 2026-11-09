# Babylon13

> **Work in progress — not ready to use or host publicly.**
> This is an experimental foundation, not a released game or a production
> persistence service. Do not entrust an irreplaceable world to it.

Babylon13 is a fork of [S.P.L.U.R.T.](https://github.com/SPLURT-Station/S.P.L.U.R.T-tg)
for developing persistent Babylon building worlds. It keeps upstream Git
history and uses an optional build plus a separate `modular_babylon` module
so upstream changes can continue to be merged.

## Groundwork currently included

- Construction, nested inventories, stock parts, materials, power cells,
  research, machine settings, and exact saved gas quantities/temperatures.
- Structural restoration before pipe/power initialization, followed by full
  restoration before the simulation starts.
- Drone appearance, airlock electronics/cycle groups, vent settings and alarm
  links, solar hardware/tracking, and active modular-computer programs.
- Fifteen-minute autosaves with 30/10/5-second warnings and a “now” notice one
  second before capture. A short consistent-snapshot pause still occurs.
- Fresh-map cleanup of unused Babylon drone shells, a 60-second respawn
  cooldown that survives saves, and confirmed self-destruct with inventory
  drops.
- Authenticated checkpoint status/save/stop controls. Arbitrary live mutation
  tools are compiled only into the explicitly unsafe integration-test build.
- A standalone lightweight BYOND lobby and Python/SQLite supervisor: world
  creation, private/password/public access, memberships, quotas, offline edits,
  owner stop controls, administrator admission, and single-use join tickets.
- Per-player drone persistence in shared worlds, with separate inventories,
  appearances and respawn state. Empty worlds save and stop automatically.
- Configurable checkpoint retention (four per world by default), with owner/
  admin rollback of stopped worlds and confirmation before deleting newer saves.

These features were ported from a local prototype. The fork still needs
broader validation, save-schema evolution and failure recovery work.

## Scope and limitations

The cluster runs **one world per process**, with a separate minimal menu server.
See [cluster setup and limitations](modular_babylon/CLUSTER.md). Multiplayer
and admission are experimental and still need real multi-client playtesting.
Delegated manager roles, moderation/bans, synthetic-body progression and public
hosting hardening have not been implemented.

The checkpoint is not a complete memory image. Arbitrary mob types, organs/DNA,
all temporary effects, timers, event/antagonist state, and every machine-specific
datum are not guaranteed to persist. Only the Babylon station level is saved;
support maps are regenerated. Treat restores as experimental and retain backups.

The local owner's world, credentials, BYOND binaries, compiled artifacts, and
personal launch/configuration files are **not** included. Old private saves are
not an advertised migration path. No one-off reactor settings, door labels or
object-ID repairs are applied to new worlds.

## Developer entry points

- `babylon.dme`: opt-in Babylon build; includes upstream `tgstation.dme`.
- `babylon-lobby.dme`: independent menu-only BYOND build.
- `services/supervisor/`: world metadata, admission and process lifecycle service.
- `babylon-test.dme`: local test build with privileged inspection/mutation tools.
  **Never expose it to untrusted clients.**
- `modular_babylon/code/`: persistence, session, recovery and control modules.
- `_maps/babylon13.json`: standalone map configuration.
- `tools/babylon/Prepare-World.ps1`: select a checkpoint or copy the original
  upstream wreck into the ignored runtime map before starting a stopped server.

Use the BYOND version and other dependencies pinned in `dependencies.sh` and
follow upstream's build/dependency instructions in [README.upstream.md](README.upstream.md).
An experimental local workflow, from the repository directory, is:

```powershell
powershell -File tools/babylon/Prepare-World.ps1
# Compile babylon.dme using the pinned Dream Maker.
# Supply your own local server configuration, including a fresh COMMS_KEY.
DreamDaemon babylon.dmb 1339 -ip 127.0.0.1 -trusted -close -params "config-directory=babylon-config&babylon-owner=YOUR_BYOND_CKEY"
```

This is a developer example, not a turnkey hosting guide. Normalize the owner
to a BYOND ckey; never publish your configuration or comms key. No credentials
are supplied by the project. Do not run map preparation against a live world.

Generated checkpoints live under `data/babylon/saves/`; `latest.json` selects
the committed generation. Each contains `map.dmm` and `state.json`. Resume
preparation writes `data/babylon/resume-state.json` and
`_maps/babylon/active.dmm`; both are ignored by Git.

## Keeping the fork mergeable

All inherited GitHub Actions workflow YAML files have a `.disabled` filename
suffix. No replacement CI/deployment automation is enabled yet. Newly merged
upstream workflows must also be disabled until they are reviewed for this fork.

See [UPSTREAM_HOOKS.md](modular_babylon/UPSTREAM_HOOKS.md) for the six small,
compile-guarded integration patches and the merge/validation checklist. Normal
SPLURT builds do not include the Babylon module.

## Upstream and licensing

This project builds on the work of SPLURT, Bubberstation, Skyrat, /tg/station,
and their contributors. Existing source and asset licenses and attribution
requirements continue to apply. See [LICENSE](LICENSE) and the preserved
[upstream README](README.upstream.md) for the original notices and credits.
