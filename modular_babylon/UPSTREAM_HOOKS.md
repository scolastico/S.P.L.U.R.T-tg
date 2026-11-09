# Upstream integration hooks

Babylon is opt-in: compile `babylon.dme`. The upstream `tgstation.dme` is
unchanged. All six non-modular edits are guarded by `BABYLON_BUILDER` and
marked `BABYLON13`. Ordinary SPLURT builds compile those blocks out.

| Upstream file | Purpose |
| --- | --- |
| `code/controllers/master.dm` | Wait for restoration and final subsystem initialization before physics runs; support the isolated-test hold parameter. |
| `code/controllers/subsystem/mapping.dm` | Size the standalone map for Babylon and account for already allocated, unregistered lobby levels. |
| `code/modules/mapping/preloader.dm` | Apply saved structural properties before atom initialization builds pipes and power networks. |
| `code/game/machinery/computer/atmos_computers/_air_sensor.dm` | Skip fresh-map automatic vent claiming for restored sensors. |
| `code/__HELPERS/priority_announce.dm` | Suppress round announcements and command reports in the builder world. |
| `modular_zubbers/code/modules/storyteller/divergency_report.dm` | Suppress round-start station-trait reporting. |

Keep these patches small. Do not copy complete upstream files from the local
prototype. When upstream changes a hook's surrounding procedure, review its
execution order, not just whether Git merges the text cleanly. In particular,
moving restoration after simulation startup reintroduces reactor/network bugs.

## Updating upstream

```sh
git remote add upstream https://github.com/SPLURT-Station/S.P.L.U.R.T-tg.git
git fetch upstream
git merge upstream/master
```

Skip `remote add` if the remote already exists. Preserve upstream history;
do not squash upstream into this repository or force-push over its branches.

After every merge:

1. Review every `BABYLON13` marker and the standalone wrapper.
2. Rename newly introduced `.github/workflows/*.yml` / `*.yaml` files with a
   `.disabled` suffix before pushing. Keep repository Actions disabled too.
3. Compile ordinary `tgstation.dme`, production `babylon.dme`, and the local
   `babylon-test.dme` test build.
4. Exercise a fresh wreck, a save/reload, pipe expansion, vent/alarm links,
   materials, airlock groups, and drone death/respawn. Use an isolated process
   and disposable world; never point tests at a player's running instance.

The private prototype's six upstream hooks were carried forward. Its chat
transcript patch, personal config, owner name, repair object IDs, saved world,
and training/admin subsystem were deliberately not imported.
