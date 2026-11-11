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

## Lore, vault annex and survival (2026-11-10)

- `babylon.dme -DCBT` and `babylon-test.dme -DCBT` compile with zero
  errors/warnings on Dream Maker 516 after adding `vault.dm`, `survival.dm`,
  the rewritten `lore.dm` and the VaultController TGUI change; the TGUI bundle
  rebuilt successfully with `bun run tgui:build`.
- All 38 supervisor Python tests pass. The map overlay test now checks the
  46-tile vault annex patch, the 14 lore placements, that lore only lands on
  floor tiles, and that the annex is enclosed by indestructible walls.
- Not yet exercised at runtime: a fresh world with the annex loaded, the
  generation interlock against a running reactor, the one-hour pulse sequence,
  the saved `lore` state across a checkpoint, and lethal hunger/thirst on a
  human. Run the native smoke test in a disposable world before hosting.

## Lore placement fixes (2026-11-11)

- The hidden satchels no longer land on bare plating: the overlay rejects
  plating and broken/burnt turfs for hidden recipes, and the cell note moved
  from north solar control (no intact floor) to the engine room. The test
  asserts every satchel tile is an intact floor.
- The interlock memo, transcript and Vale's final letter ship in archive boxes
  whose storage refuses observers; Babylon lore papers close their UI for
  non-admin ghosts. The test asserts no loose paper in either vault chamber.
- The continuity interlock moved from the tile in front of the inner doors to
  the tile beside it; the displaced plastic crate moved to the vault's
  south-east corner. The test asserts the doorway tile holds no blocker.
- `babylon.dme -DCBT` and `babylon-test.dme -DCBT` compile with zero
  errors/warnings; all 42 supervisor Python tests pass. Not exercised at
  runtime: a ghost clicking a lore box or paper, and the new tile layout.

## Local persistence fixes ported to the multiplayer fork (2026-11-10)

- Production `babylon.dme`, `babylon-test.dme`, and ordinary `tgstation.dme`
  compile with zero errors and warnings on Dream Maker 516.1686. All 38
  supervisor Python tests pass.
- `smoke_reload_fixes.py` passes against a read-only copy of the original PoC
  workshop checkpoint, with new persistence fields deliberately removed in
  the disposable copy. It verifies no critter reseeding; consistent door
  collision/animation; alarm threshold and mode persistence; cycling-pump
  targets, side links and removability; bidirectional canister attachments
  and deliberate detachment; real circuit extraction/reinstallation and
  console completion; invalid-material UI recovery without changing stock;
  and a second player's saved roster entry.
- Evidence: ignored local artifact
  `data/babylon-supervisor/ported-reload-fixes-2/result.json`; checkpoint
  generations `save-20261110-235443-100` and `save-20261110-235625-101`.
- The managed native smoke also passes HTTP ticket redemption/replay checks,
  admin admission, two-player inventories, empty respawn, trimmed ghost HUD,
  return-button order, no physical cafe, and real save/stop/restart. Evidence:
  `data/babylon-supervisor/ported-managed-2/result.json`.
- The fresh managed test loads the newer annex and retains its 12 immediately
  available lore papers through reload. The two sealed lore crates populate
  on first opening and are excluded from that initial-paper count. The pulse
  sequence, interlock behavior and human survival scenarios remain separate
  tests; this port does not change their implementation.
- Test children exit after completion. No private player save, live world,
  credential, or generated binary is committed.

## Lobby loading and scroll behavior (2026-11-11)

- `babylon-lobby.dme` compiles with zero errors/warnings.
- `node tools/babylon/test_lobby_loading.cjs` checks immediate loading,
  duplicate-click blocking, late-poll rejection, completion/cancellation,
  unchanged-content rendering, and scroll retention across updates and tabs.
- An isolated native lobby/browser on port 1371 confirmed real DM-to-browser
  callbacks, tab switching, stable scrolling across the five-second poll,
  a visible loading panel behind deletion confirmation, cancellation, and
  the deletion progress message followed by the updated map list. Only a
  disposable probe world was deleted; its runtime files were removed too.
- The primary lobby was restarted on port 1361. The supervisor and game-world
  processes do not need a restart for these browser changes.

## Windows cluster launchers (2026-11-11)

- Both root `.cmd` launchers were exercised from a different working directory,
  including their Python auto-detection and double-click-style pause behavior.
  Duplicate Start and repeated Stop were verified.
- A disposable real world was started, saved/stopped through the shutdown
  helper, and its committed map/state checkpoint verified before cleanup.
  The test world was then deleted through the normal supervisor API.
- All 47 Python tests pass, including startup waiting, multi-world stop
  requests, save-failure retention, and timeout retention. No launcher can
  force-kill a child world. The cluster was left stopped after validation.
