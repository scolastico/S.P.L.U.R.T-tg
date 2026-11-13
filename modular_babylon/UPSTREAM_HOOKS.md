# Upstream integration hooks

Babylon is opt-in: compile `babylon.dme`. The upstream `tgstation.dme` is
unchanged. The fifteen modified upstream DM files use hooks guarded by
`BABYLON_BUILDER` and marked `BABYLON13`. Ordinary SPLURT builds compile
those blocks out.

The wrapper also defines upstream's `ABSOLUTE_MINIMUM` flag to skip the
separate Interlink/cafe map loader. Builder behavior, restricted observer
interfaces and lore papers live under `modular_babylon`; lore placements are
applied to the fresh upstream map at preparation time, without a copied map.

Babylon is safe for work. `modular_babylon/code/sfw.dm` disables inherited
ERP content through proc and var overrides only (no upstream edits): it locks
`DISABLE_ERP_PREFERENCES`/`DISABLE_LEWD_ITEMS` on, filters lewd interactions,
emotes, research designs and chemistry, removes the Plug13 verb, and opens the
new Babylon-only `tgui/packages/tgui/interfaces/BabylonInteraction.tsx`
instead of SPLURT's `MobInteraction` window. After an upstream merge, re-check
newly added lewd interactions, designs, reactions and verbs against it.

Babylon has no storyteller yet. `modular_babylon/code/storyteller.dm` runs an
inert `/datum/storyteller/babylon` in every world (no events, no antagonists),
refuses the storyteller vote and any other storyteller, and keeps tgstation's
random events off, again through overrides only. After an upstream merge,
re-check `SSgamemode`'s `set_storyteller`/`init_storyteller`, the storyteller
vote and `SSevents.spawnEvent` against it; the native smoke test asserts it.

`modular_babylon/code/moderation.dm` grants lobby admins (`BABYLON_ADMINS`) full
game-admin rights on admission, removes mentors (no mentor is loaded, admins
are not made mentors, Mentorhelp and Mentorwho are gone) and relays adminhelps
to the supervisor for the Discord `ahelp` feature; Discord replies use the
game's external admin PM (`TgsPm`). All through overrides. After an upstream
merge, re-check `MessageNoRecipient`, `reply_to_admins_notification`,
`receive_ahelp`, `TgsPm` and the Skyrat mentor module against it.

`modular_babylon/code/research.dm` replaces the research point bank and queue:
a techweb researches one selected node at a time, all income (through
`add_point_list`) goes towards it capped at its price, `research_points` holds
that progress, income without a target is dropped and switching targets starts
over. The target is saved with the world. After an upstream merge, re-check
`add_point_list`, `research_node`, `complete_experiment`, the queue procs and
the R&D console / PDA `research_node` and `ui_data` against it. It also removes
designs Babylon never offers (ERP, pAI, AI core, MMI, positronic brain) from every node in
`SSresearch.calculate_techweb_nodes` and refuses them in `/datum/techweb/add_design`;
`/datum/techweb_node/Initialize` is not usable for that, because upstream's
`initialize_all_techweb_nodes` calls it on the old, empty node list.

`modular_babylon/code/silicons.dm` removes pAIs, station AIs, MMIs and positronic
brains, which no one can play: pAI cards, AI cores and loose MMIs/posibrains delete
themselves on creation (wreck, saves, loot), their designs are removed,
the plasteel "AI core" recipe and the PDA vendor's pAI cards are gone, and ghosts
get no "Enter Soulcatcher" button. After an upstream merge, re-check new sources
of pAI cards, AI cores and ghost-joinable silicons against it.

`modular_babylon/code/interface.dm` trims the game window through overrides and
runtime winsets (the shared `interface/skin.dmf` is unchanged): the top bar keeps
Menu, Settings, Fullscreen and Reconnect; the station is named after the world
(`babylon-name`, markup characters removed); the status tab drops the round ID;
and verbs for systems Babylon lacks (antag tickets, OPFOR, round-end reports,
votes, respawn, relays, forum/Discord-DB linking ...) are removed. After an
upstream merge, check new player verbs and the `infobuttons` controls.

| Upstream file | Purpose |
| --- | --- |
| `code/controllers/master.dm` | Wait for restoration and final subsystem initialization before physics runs; support the isolated-test hold parameter. |
| `code/controllers/subsystem/mapping.dm` | Size the standalone map for Babylon and account for already allocated, unregistered lobby levels. |
| `code/modules/mapping/preloader.dm` | Apply saved structural properties before atom initialization builds pipes and power networks. |
| `code/game/machinery/computer/atmos_computers/_air_sensor.dm` | Skip fresh-map automatic vent claiming for restored sensors. |
| `code/__HELPERS/priority_announce.dm` | Suppress round announcements and command reports in the builder world. |
| `modular_zubbers/code/modules/storyteller/divergency_report.dm` | Suppress round-start station-trait reporting. |
| `code/modules/client/client_procs.dm` | Validate single-use lobby admission before registering a child client or creating an avatar. Enforce showcase play mode and restrict visitor Topics/clicks before target dispatch. Standalone builds restrict access to their configured owner. |
| `code/modules/escape_menu/escape_menu.dm` | Add the Discord button (`modular_babylon/code/links.dm`) to Resources when `DISCORDURL` is set. |
| `code/controllers/subsystem/verbs.dm` | Enforce the visitor verb allowlist for native/context verbs, including verbs belonging to world objects. |
| `code/_onclick/drag_drop.dm` | Reject showcase visitor mouse-down/up, drag and drop before target handlers or signals run. |
| `code/modules/keybindings/bindings_client.dm` | Limit visitor shortcuts to chat and harmless display controls; normal movement handling remains available. |
| `code/modules/mob/mob_movement.dm` | Enforce the visitor body before accepting movement, including reconnects from a former playable body. |
| `code/modules/atmospherics/machinery/components/unary_devices/airlock_pump.dm` | Skip fresh-install door animations for saved pumps; rebuild their saved connections after restoration. |
| `code/datums/materials/material_container/material_container.dm` | Discard invalid material keys before UI generation and stock accounting, preserving valid quantities. |
| `tgui/packages/tgui-panel/settings/atoms.ts`, `migration.ts` | Default the chat panel (and with it the window) to the dark theme, and apply the default theme on a player's first start. Players' saved choices are kept. |
| `tgui/packages/tgui/interfaces/Techweb/Content.tsx`, `nodes/TechNode.tsx`, `types.ts` | When the server sends `babylon_research`, show the node being researched instead of point balances and the queue, a Research / Researching button instead of research and queue buttons, and progress only on that node. Without it, the upstream screens are unchanged. |
| `tgui/packages/tgui-escape-menu/EscapeMenu.tsx`, `pages/PlayersPage.tsx` | When the server sends `babylon`, hide the Round ID line and the "No Admins Online!" heading. Unchanged otherwise. |
| `code/modules/admin/sql_message_system.dm` | Without a database (`SQL_ENABLED` off), `get_message_output` returns quietly instead of telling every player at login that the database connection failed. |
| `tgui/packages/tgui/interfaces/VaultController.tsx` | Render the Babylon generation interlock (live generation, ignored battery output, hold timer) when the controller sends those fields; the upstream charge view is unchanged otherwise. Rebuild the TGUI bundle after editing. |

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
