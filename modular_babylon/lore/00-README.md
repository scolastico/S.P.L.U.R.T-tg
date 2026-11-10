# Babylon 13 lore pack

These files are the source text and design notes for the lore compiled into
`modular_babylon/code/lore.dm` and `modular_babylon/code/vault.dm`. Edit the
paper here first, then copy the body into the matching `default_raw_text`.
Each paper file has a short header (type, tier, placement, stamps) above a `---`
line; only the text below that line goes into the paper.

Implemented on 2026-11-10: all fifteen papers, the flat satchels and sealed
crates that hold them, the vault annex and inner doors
(`_maps/babylon/vault_annex.json`), the generation interlock, the one-hour
pulse interlock, the watchdog server with its generated core log, and lethal
hunger and thirst (`modular_babylon/code/survival.dm`).

## Canon spine

- **Babylon** was a research station run by "Operations" for "the Board".
  Dr. Mara Vale led **Project MNEMOSYNE**: holding a human mind in the station's
  maintenance drone lattice.
- Mnemosyne worked, partially. The lattice holds a **pattern** (dispositions,
  skills, wanting, how you decide) but not the **archive** (what happened to
  you: faces, names, the order of days). Operations ordered the archive media
  destroyed. Vale sealed it in the server behind the vault instead.
- The recall order was signed at 02:40, before the accident. The uplink was cut
  at 03:14, the hull failed at 03:17. Twenty-eight people left in three groups.
  None confirmed arrival.
- **Vale and Ilya stayed** and wrote themselves into the lattice.

### Lattice, seeds, selves (the shard rules)

- The lattice is **one shared substrate** across every drone shell and the
  watchdog cell. Vale's pattern went in first. Ilya's went in over the top of
  it, onto the same nodes, because there was no time to partition. The result is
  a **blend**. Neither original can be reassembled from it. Vale knew that and
  accepted it.
- Waking a shell means the watchdog draws a **seed**: a small, self-consistent
  sample of the blend, leaning by chance toward one or the other. A seed is
  what you wake with: some skills, some habits, a strong wish to fix what is
  broken and keep the others safe. **A seed is not a personality.** It does not
  decide what you like, what you build, or who you become.
- A seed becomes a **self** by living. From the first hour, what a shell
  chooses is its own. That is the only way a fragment becomes a complete
  person, and it is the only way Vale wanted it to happen. Nobody is meant to
  reassemble Vale or Ilya.

### Death, re-seat, drift (what survives)

- The watchdog keeps each woken self synced into the lattice. On chassis loss
  it seats that self, whole, into the next shell. **Everything the self has
  lived since waking survives.** The player keeps their own memories.
- **Drift** (the old "copy loss"): each re-seat re-samples the inherited part.
  A little less Vale-or-Ilya each time, a little more of what the self made on
  its own. Vale treats drift as the experiment succeeding, not failing.
- The **archive** is not in the lattice. It is sealed media in the inner
  chamber. Nothing about dying or re-seating touches it.
- Tools and the issued emergency kit stay with the old chassis. The watchdog
  moves selves, not matter.

### Shells

- Sixteen was the **reserve count at the night of the split**, not a limit.
  The dispenser in secure engineering storage fabricates shells from stock
  materials. Shells cost material, not lives. Emergency stores are issued once
  per self.

### Why it slept, why it woke

- Ilya cut the watchdog from the station bus and tied it to the vault's own
  isolated cell, with one rule: wake only when a chassis can survive long enough
  to repair. The cell charged at a trickle from one surviving solar string. The
  clock lost sync when the bus was cut. Nobody chose "now". A capacitor crossed
  a line.

### The vault and the inner door

- **Outer vault:** Ilya moved the interlock from a stored-charge reading to a
  live-generation reading. Batteries are not proof; a salvage crew arrives with
  batteries. The vault wants a number, not a method. The supermatter is the
  route Ilya knows; the papers leave room for others.
- **Inner door:** the archive is dangerous to a fresh seed. An archive written
  onto a self that has not yet become anyone does not inform it, it replaces it.
  You would wake up Vale, and Vale did not want to be woken up. The door
  therefore needs a condition meaning "has become someone and chose a
  housing". Vale could not build a sensor for that. In the time she had, the
  only sensor she could build was a **pulse**: a grown body is proof of a long,
  chosen, cooperative project. It is a proxy, not a philosophy, and Ilya says
  so in writing. Vale apologises for it in her last letter.
- **Once opened, the inner door stays open.** One self with a pulse opens it
  for everyone. Nobody has to stay in a body they did not want.
- The transfer rig is **not** behind the door. It is built from the Phase III
  roadmap in the open.
- The watchdog's rule is symmetric: a self in a pulsed body is a heartbeat. A
  heartbeat that stops is a chassis lost, and the self comes back as a drone.

### After the archive (open threads for continued play)

- The twenty-eight: no arrival was ever confirmed. Long-range comms, a
  telescope, a probe.
- The bus: whatever came down the uplink at 03:14 is still on the isolated
  main computer. Investigate it, quarantine it, or leave it.
- The Board: someone signed a termination order before the accident. The
  recall printout is the only evidence on the station.
- Somewhere safe to wake up: more seeds will come. More bodies can be grown.
  The station can be a place others arrive at rather than a wreck others
  left.

Names: Vale is "she". Ilya is deliberately never gendered. S. Ren (medical)
stays as the evacuation voice.

## Paper tiers and placement

| # | File | Type suffix | Tier | Placement |
|---|------|-------------|------|-----------|
| 1 | 01-watchdog-sheet.md | watchdog | 0 open | secure engineering storage (respawn room) |
| 2 | 02-restart-order.md | restart | 0 open | engine room |
| 3 | 03-triage-tally.md | triage | 0 open | medical |
| 4 | 04-recall-directive.md | recall | 0 open | bridge |
| 5 | 05-fault-review.md | pressure | 0 open | atmospherics |
| 6 | 06-last-light.md | last_light | 0 open | chapel |
| 7 | 07-notebook-page.md | research | 1 under floor | research, smuggler's satchel |
| 8 | 08-cell-note.md | cell | 1 under floor | north solar control, smuggler's satchel |
| 9 | 09-to-whoever.md | letter | 1 under floor | service / dorm side, smuggler's satchel |
| 10 | 10-seed-ledger.md | ledger | 2 vault chamber 1 | inside a crate |
| 11 | 11-housing-roadmap.md | housing | 2 vault chamber 1 | inside a crate |
| 12 | 12-interlock-memo.md | interlock | 2 vault chamber 1 | on the floor by the inner door |
| 13 | 13-core-log.md | core_log | 3 watchdog chamber | **printed by the server from world state** |
| 14 | 14-transfer-transcript.md | transcript | 3 watchdog chamber | printed by the server, hangs beside the core log |
| 15 | 15-vale-final.md | vale_final | 3 watchdog chamber | sealed envelope on the server |

Tier 0 establishes the evacuation, the two who stayed, and that the drones were
meant to remain. Tier 1 seeds the shard idea. Tier 2 states the seed rules,
what survives death, and the body project. Tier 3 is confirmation and the
handover to open-ended play.

## Where each rule lives (to keep repetition down)

| Rule | Stated fully in | Callback only in |
|---|---|---|
| Live generation unlocks the outer vault | 02 | 13 (log line) |
| Seeds, selves, drift, what survives death | 10 | 07 (pattern/archive table), 09 (one line), 14 (shown, not stated) |
| Pulse opens the inner door, and why | 12 | 11 (one line), 13 (rule R8), 15 (apology) |
| Stopped heartbeat re-seats you as a drone | 13 (rules R6, R7) | 11 (one line) |
| Shell supply | 01, 10 | none |
| "Check every flow path" | 05 | 02 (quoted), 15 (postscript joke) |

## Presentation notes

- Papers render Markdown (GFM, line breaks on) and then a DOMPurify HTML subset.
  By default `style`, `class` and `img` are stripped. Our paper subtype adds its
  default text with the advanced flag so inline style and data-URI images work.
- Stamps are placed with explicit x, y, rotation, colour and scale. Existing
  icon states cover VOID, DENIED, OK, CentCom, and the head-of-staff seals. A
  Mnemosyne seal needs one new icon state; until then the RD stamp in a custom
  colour stands in.
- Keep each paper under about 1,800 characters.

## The core log is generated, not written

Paper 13 is a template. The watchdog server structure prints a fresh strip
from the world's own state when the inner door is first opened (and again on
request from the server), filling:

| Field | Source |
|---|---|
| `{woken}` | number of distinct selves ever seated in this world |
| `{reseats}` | total re-seat events (drone respawns) |
| `{events}` | the last N re-seat lines: shell id lost, shell id seated, drift % |
| `{outer}` | tick or save stamp when the outer vault first unlocked |
| `{inner}` | tick or save stamp when the inner door opened, and who stood there |
| `{heartbeats}` | current count of selves in pulsed bodies |

Ticks are shown as `t+<n>` with no date, because the clock was lost with the
bus. The persistence layer already tracks respawns, so this is mostly plumbing.

## Vault power gate (design)

Current upstream behaviour: the vault controller siphons surplus from the cable
under it until it has absorbed 10 MW total, then the lock button works. Any
charged SMES dumped onto that cable satisfies it.

New behaviour for Babylon:

- The controller **consumes nothing**. Every tick it reads the powernet of the
  cable beneath it and computes **live generation**: `powernet.avail` minus
  `output_used` of every SMES on that same powernet. SMES output never counts;
  solar, generators, TEG and turbine do.
- The lock toggles only while live generation is at or above
  `required_generation` (default 2 MW; a var so you can tune it). A 40-panel
  solar field makes about 100 kW. An SM loop through a TEG makes several MW. A
  large turbine setup can also reach it, which keeps the "a number, not a
  method" line honest.
- To avoid a one-tick spike unlocking it, the reading has to hold above the
  threshold for `hold_time` (default 30 s) of consecutive ticks.
- The UI shows "Live generation: x kW / required y kW" and a hold progress bar
  instead of the current charge bar.

The inner door is a separate console, the continuity interlock, in the first
chamber. A conscious human who touches it starts a 60-minute real-time
sequence. The console checks every tick that the same human is still alive; if
they die the sequence resets and the world is told. Anything that is not a
living human gets "No pulse detected." When the hour completes the inner doors
open and bolt open, the opener's name and tick are saved with the world, and
the watchdog server prints a core log. Players therefore have to have built
life support and food before the inner chamber opens, which is also why hunger
and thirst are lethal in Babylon (see `survival.dm`).
