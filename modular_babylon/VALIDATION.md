# Groundwork validation

Validated locally on 2026-11-09, based on upstream master
`58cd83015ba7a528c87ad4c894785caa6e655265`.

- Dream Maker 516.1686: `babylon-test.dme -DCBT`, zero errors/warnings.
- Dream Maker 516.1686: `babylon.dme -DCBT`, zero errors/warnings.
- Dream Maker 516.1686: ordinary `tgstation.dme -DCBT`, zero errors/warnings.
- Upstream TGUI dependencies installed with the frozen lockfile and
  `bun run tgui:build` completed successfully.
- A separate localhost test process loaded the canonical upstream Babylon
  wreck, saved a seeded world, stopped, prepared that checkpoint, and reloaded.
- The comparison covered 3,304 saved objects and 2,474 room tiles. It checked
  nested/held inventory, appearance, airlock board settings and reconstructed
  cycle groups, nondefault vent pressure/direction, expanded scrubber range,
  and exact saved room/device/pipeline gas data.
- The owner was configured through world parameters using a test identity;
  no personal owner account is compiled into the module.
- `tgstation.dme` is unchanged. Core integration changes are limited to the six
  files listed in [UPSTREAM_HOOKS.md](UPSTREAM_HOOKS.md) at that initial milestone;
  cluster admission adds a seventh guarded upstream hook.
- All 30 previously active workflow YAML files were renamed with `.disabled`;
  repository Actions were disabled separately.

The earlier local prototype had additional reactor-running, pipe-expansion,
lathe-material, autosave-countdown and drone-recovery tests. Those results do
not substitute for repeating coverage against this fork after future changes.
This initial smoke test is not a full persistence or multiplayer certification.

## Lobby/supervisor milestone (2026-11-09)

- All four builds compile with zero errors/warnings on 516.1686: ordinary
  upstream `tgstation.dme`, production `babylon.dme`, privileged local
  `babylon-test.dme`, and independent `babylon-lobby.dme`.
- Twelve supervisor tests pass: private/password/member/admin access, offline
  editing and validation, per-owner/global quotas, concurrent starts, pending
  and redeemed capacity reservations, ticket binding/expiry/replay, membership
  removal, supervisor restart and save failure retention.
- Real DreamDaemon native smoke passes: fresh startup, DM HTTP ticket
  redemption, replay rejection, administrator admission to a private world,
  final save/exit, restart and two separate player roster entries. A second
  drone enclosed inside a locker retains its held backpack and pending respawn.
- The earlier persistence regression passes after the roster refactor:
  3,334 objects, 2,474 room tiles, nested/held inventory, vent settings,
  scrubber widenet, airlock electronics/groups, and exact room/device/pipe gas.
- The menu was opened in a real DreamSeeker client and visually checked. It
  uses a dedicated browser-only skin with no map or SS13 gameplay controls.
- A production child admitted an actual authenticated DreamSeeker client
  using a supervisor-issued ticket; the player appeared in its live roster.
  Owner stop then committed a checkpoint and disconnected the client.
- The separate private prototype on port 1339 was not restarted or changed.

Generated logs/results are ignored under `data/babylon-supervisor/` in the
developer checkout. See [CLUSTER.md](CLUSTER.md) for repeatable commands and
remaining operational limitations. These checks are not a public-hosting or
multi-client load certification.

## Checkpoint retention and rollback

- Twenty-six supervisor/storage tests pass, including the existing twelve
  policy tests. Coverage adds default/custom retention, numeric generation
  ordering, commit/busy boundaries, owner/admin and stopped-world restrictions,
  required destructive confirmation, stale selections, interrupted rollback
  recovery, damaged heads, filesystem path/symlink confinement, and staging the
  selected map/state on the next start.
- The independent lobby build compiles with zero errors/warnings after adding
  the stopped-world checkpoint selection and deletion-warning confirmation.

## Repeating the smoke test

The 2026-11-10 builder update additionally passed 38 Python tests, including
inactivity expiry, interrupted deletion, migration of existing activity data,
path confinement, and preservation of the upstream map under six lore additions.
The production, test and lobby builds compile with zero errors/warnings.
Native smoke checks cover empty replacement equipment through the real respawn
path, Return-before-Self-destruct action order, removal of ghost role/minigame
HUD entries, retained DNR/re-entry, zero physical cafe turfs, and all six paper
items surviving save/reload. The lobby's selected tab was checked in DreamSeeker;
Join displayed its loading panel immediately in a real client before startup.

Use a **disposable checkout**, supply the pinned BYOND/native dependencies and
build the TGUI assets. Compile `babylon-test.dme` first. Supply your own local
configuration directory with a fresh COMMS_KEY; do not commit it.

```powershell
powershell -File tools/babylon/Test-Persistence.ps1 `
  -DreamDaemon C:\BYOND\bin\dd.exe `
  -ConfigDirectory C:\BabylonTestConfig `
  -Port 1351
```

The test refuses an occupied port, the private prototype's port, or an existing
saved world. It only stops the process it launched. Generated results, logs,
map and checkpoint files remain ignored in the disposable checkout.
