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
  files listed in [UPSTREAM_HOOKS.md](UPSTREAM_HOOKS.md).
- All 30 previously active workflow YAML files were renamed with `.disabled`;
  repository Actions were disabled separately.

The earlier local prototype had additional reactor-running, pipe-expansion,
lathe-material, autosave-countdown and drone-recovery tests. Those results do
not substitute for repeating coverage against this fork after future changes.
This initial smoke test is not a full persistence or multiplayer certification.

## Repeating the smoke test

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
