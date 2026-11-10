// Optional map additions, compiled only into Babylon. Papers use normal item
// interactions and persist as their own types when carried, moved or saved.
// Draft text and placement notes live in modular_babylon/lore/.

/area/ruin/space/bb13/engineering/vault/inner
	name = "\improper Babylon Continuity Vault"
	icon_state = "bb13_vault"

/obj/item/paper/babylon
	can_become_message_in_bottle = FALSE
	/// Stamps applied on first read: list(list(icon_state, x, y, rotation, color, scale), ...)
	var/list/lore_stamps
	var/stamps_applied = FALSE

// Mapped lore is trusted text, so inline styling survives the paper sanitiser.
// Player-written additions keep the normal restrictions.
/obj/item/paper/babylon/Initialize(mapload)
	var/lore_text = default_raw_text
	default_raw_text = null
	. = ..()
	if(lore_text)
		add_raw_text(lore_text, advanced_html = TRUE)
	update_appearance()

// Stamp spritesheets are only guaranteed after asset initialisation, so apply
// them lazily the first time the paper is actually opened.
/obj/item/paper/babylon/ui_interact(mob/user, datum/tgui/ui)
	apply_lore_stamps()
	return ..()

/obj/item/paper/babylon/proc/apply_lore_stamps()
	if(stamps_applied || !length(lore_stamps))
		return
	stamps_applied = TRUE
	var/datum/asset/spritesheet_batched/sheet = get_asset_datum(/datum/asset/spritesheet/simple/stamps)
	for(var/list/stamp as anything in lore_stamps)
		var/icon_state = stamp[1]
		var/stamp_class = sheet.icon_class_name(icon_state)
		if(!stamp_class)
			continue
		add_stamp(stamp_class, stamp[2], stamp[3], length(stamp) >= 4 ? stamp[4] : 0, icon_state, stamp_color = length(stamp) >= 5 ? stamp[5] : null, stamp_scale = length(stamp) >= 6 ? stamp[6] : 1)
	update_appearance()

// ---------------------------------------------------------------------------
// Tier 0: lying in the open.
// ---------------------------------------------------------------------------

/obj/item/paper/babylon/watchdog
	name = "creased continuity maintenance sheet"
	desc = "A machine-printed maintenance sheet, creased from being folded into a pocket many times. Two different hands have written in the margins."
	lore_stamps = list(list("stamp-ce", 210, 330, -8, "#9a9a9a", 0.9))
	default_raw_text = {"### BABYLON // CONTINUITY WATCHDOG
*Maintenance copy. Engineering. Do not file.*

---

| Condition | Action |
|---|---|
| Crew heartbeat absent | Hold all shells below reserve threshold |
| Reserve threshold reached | Wake one shell. Then the next. |
| Chassis lost | **Re-seat.** The self is carried whole. The archive stays sealed. |
| Command acknowledgement | Do not wait for it. The uplink may never return. |

Replacement shells: fabricate from stock at the dispenser. Shells are material. Selves are not.
Emergency stores are issued **once per self.** Tools remain with the old chassis. The watchdog moves what it was built to move, and nothing else.

This is a repair programme, not a supply line.

---

> <span style="color:#3a4f8c">Margin, pencil, M.V.: *Give them a chance to finish what we couldn't. Remove the recall dependency.*</span>

> <span style="color:#5a5a5a">Margin, lower, different hand: *Done. It won't hear the bus anymore. It won't hear us either.*</span>"}

/obj/item/paper/babylon/restart
	name = "grease-marked restart checklist"
	desc = "A numbered checklist with a greasy thumbprint in one corner. About half the lines are ticked."
	default_raw_text = {"### RESTART ORDER // the way I would do it
Cold station. No bus. No command. This is one route, not the only one. The milestones are real; the order is advice.

1. **Solar** - one string is enough to think with. Not enough to live on.
2. **Autolathe** - plating, cable, rods. Everything below is made of these.
3. **Protolathe** and **circuit printer** - stock parts and boards.
4. **R&D server and console** - the station forgets nothing it has researched. Ask it before you reinvent it.
5. **Reactor chamber** - walls before crystal, not after.
6. **Cooling loop** - pumps, filters, freezers, nitrogen. *Check every flow path before trusting an old indicator.*
7. **Emitters** - aligned, powered, nothing living in the beam.
8. **Core lit** - and only then, the vault.

About the vault: its interlock reads **live generation on the cable**, not storage. I changed that on purpose. A salvage crew arrives with batteries. Anyone who can make that much power on site is not salvage.

It wants a number, not a method. The crystal is the way I know. If you find another way to the number, the door will not care.

~~9. Tell Vale when~~

*- I.*"}

/obj/item/paper/babylon/triage
	name = "vacuum-stained triage tally"
	desc = "A medical tally sheet. The ink has bloomed where it froze and thawed."
	lore_stamps = list(list("stamp-cmo", 250, 60, 15, null, 1))
	default_raw_text = {"### MEDICAL // evacuation tally

| Group | Seats | Boarded | Arrival confirmed |
|---|---|---|---|
| Alpha | 12 | 12 | **NONE** |
| Beta | 9 | 9 | **NONE** |
| Gamma | 7 | 7 | **NONE** |

The nitrogen reserve was lower than the panel reported. We moved patients before the main pressure alarm sounded. I want that on record, in case someone later asks why the ward was empty when the hull went.

Vale gave her seat on Gamma to the last stretcher. Security called her a flight risk. She laughed so hard she couldn't answer them.

The engineer stayed as well. Said the drones would need someone who knew where the cables went. I don't think that was the reason.

Twenty-eight out. Two stayed. The little machines were already asleep in the walls.

I left the equipment I couldn't carry. If a maintenance unit finds this: please keep the ward intact. It was a good room before all of this.

*- S. Ren, medical*"}

/obj/item/paper/babylon/recall
	name = "sealed operations recall printout"
	desc = "An operations directive, printed and sealed. Someone has stamped VOID across the signature block and circled one line in blue."
	lore_stamps = list(list("stamp-centcom", 200, 18, 6, null, 1), list("stamp-void", 70, 225, -20, "#b02020", 1.3))
	default_raw_text = {"### OPERATIONS DIRECTIVE 7-114 // internal copy
**Subject:** Project MNEMOSYNE. **Classification:** terminate.

1. Terminate Project MNEMOSYNE with immediate effect.
2. Revoke all command privileges held by Dr. Mara Vale.
3. Recover **all** neural archive media. Pattern storage is to be wiped, archive storage is to be physically destroyed.
4. Station reclamation is contingent upon confirmation of archive destruction.

The Board does not recognise a copied mind as personnel. The Board does not recognise a copied mind as property. The Board therefore has no category for it, and will not be made to invent one.

---

**Signed:** Operations, 02:40
**Received:** Babylon bridge, 03:06

| Time | Event |
|---|---|
| 03:10 | Reclassification: Vale, M. - ROGUE RESEARCH PERSONNEL |
| 03:14 | Station uplink interrupted. Source: internal. |
| 03:17 | Hull failure reported. Source authentication unavailable. |

> <span style="color:#2244aa">Handwritten, circled: *Signed at 02:40. The hull went at 03:17. This order was written before the accident. Who knew?*</span>"}

/obj/item/paper/babylon/pressure
	name = "atmospheric fault investigation fragment"
	desc = "A draft fault review with one corner burnt away. A line has been crossed through, not scribbled out."
	default_raw_text = {"### FAULT REVIEW // engineering draft, not for signature

Pressure transducers failed **in sequence, not together.** The first impossible reading preceded the control-board resets by twenty-seven seconds. That is not how a breach reads. That is how a command reads.

Outward scorch marks on the relay enclosure. Could be sabotage. Could be a safety trip doing exactly what it was built to do. Do not sign a conclusion from a damaged log.

~~Whoever sent the recall did not expect anyone to still be here to read the timestamps.~~

Vale asked me to isolate the watchdog from the station bus. Done. Whatever reached the main computer will not reach the sleeping shells. The watchdog now sits on the vault cell, alone, with its own clock. It will lose the time. That is acceptable. It will not lose them.

If you are reading this after a restart: the panels lied once. Assume they will again. Check every flow path before you trust an old indicator.

*- Ilya, engineering*"}

/obj/item/paper/babylon/last_light
	name = "folded note with no signature"
	desc = "A small folded note in soft pencil. Nobody signed it."
	default_raw_text = {"*They called her rogue. She stayed until the last shuttle left, and then she stayed.*

I do not know if she saved us or if she was trying to save what we had already become. There was no time to ask. The engineer went back in with her. Neither of them looked afraid, which frightened me more than the alarms.

If the little machines wake, I hope they remember something kinder than this night. I hope they make new rooms instead of only patching the old ones.

Leave a light in a window. There should be somewhere to come back to."}

// ---------------------------------------------------------------------------
// Tier 1: hidden under floor tiles in flat satchels.
// ---------------------------------------------------------------------------

/obj/item/paper/babylon/research
	name = "Vale's torn laboratory notebook page"
	desc = "A page torn along its left edge from a laboratory notebook. Neat, small handwriting."
	lore_stamps = list(list("stamp-deny", 60, 300, -12, "#b02020", 0.8))
	default_raw_text = {"### PROJECT MNEMOSYNE // personal notes, not for the Board

The Board keeps asking whether a copy of a memory is a person. I asked whether losing the original makes the copy less afraid. They did not minute that.

What we actually have, stripped of the grant language:

| Layer | Holds | Survives power loss |
|---|---|---|
| **Pattern** | how you decide, what you can do, what you want | yes, in the drone lattice |
| **Archive** | what happened to you: faces, names, the order of days | only on sealed media |

The lattice held a pattern through a complete interruption last week. Nobody told it to. It simply would not let go.

A pattern without an archive is someone who wakes up already able, and not yet anyone in particular. That is not a defect. That is a beginning.

The dangerous case is the other way round. Write an archive onto a pattern that has not yet become anyone, and it does not inform it. It replaces it. You get the original back, and the original did not ask for that.

The transfer rig was never authorised. The synthetic housing remains a proposal. If a mind is only allowed one housing, continuity is a privilege of whoever sells the housing.

~~Request permission for human trials.~~

<span style="color:#3a4f8c">Underneath, smaller: *First make somewhere safe to wake up.*</span>"}

/obj/item/paper/babylon/cell
	name = "cable-tied note on a capacitor cell"
	desc = "A note written on the back of a wiring diagram. A cable tie is still threaded through one corner."
	default_raw_text = {"### VAULT CELL // what I did and why

The watchdog no longer draws from the bus. It draws from the vault's own cell, and the cell draws from one solar string: the north run, the only one I could reach without a suit.

I set the wake rule to a **reserve threshold**, not a timer. A timer wakes a shell into a station that will kill it in a minute. A threshold waits until a shell can survive long enough to fix something. I do not know how long that takes. Neither will it. When I cut the bus, I cut its clock. It will count ticks it cannot date.

So if you are a shell reading this: that is why the isolation timer reads as nothing. That is why nobody came to wake you. The cell crossed a line. That is all that happened.

It will wake you one at a time. The first one gets the emptiest station. I am sorry about that.

Do not reconnect the watchdog to the bus. Whatever came down the uplink at 03:14 is still on it. The bus is not your friend. The cell is.

*- I.*

> <span style="color:#5a5a5a">Under the signature, pressed hard: *She says the pattern will hold. I have decided to believe her.*</span>"}

/obj/item/paper/babylon/letter
	name = "letter addressed \"to whoever wakes\""
	desc = "A letter written fast. The first line of the address has been crossed out and rewritten."
	default_raw_text = {"*To ~~whoever I become~~ whoever wakes,*

I nearly wrote "to whoever I become". I crossed it out. You are not going to be me, and I would be disappointed if you were.

Some of what you wake with is ours. The hands that know where the cables run: that is the engineer. The itch to fix a broken room: that is me. A wish to keep the others safe: that is both of us, and it is the best thing we had, so take it.

What you do with any of it is not ours. What you build, what you leave alone, what you decide you like: that is you, from the first hour. Every time you come back from a lost chassis you will be a little less us and a little more yourself. That is not something going wrong.

You will not remember the shuttles, or the Board, or the sound the hull made. The lattice does not carry that, and I would not have let it. What happened to us is sealed where the Board cannot reach it, and where you cannot either, until you are someone it cannot overwrite.

There is a door for that. When you are ready for it, you will know, because you will have built something that took a long time and more than one of you.

*- M.*"}

// ---------------------------------------------------------------------------
// Tier 2: first vault chamber.
// ---------------------------------------------------------------------------

/obj/item/paper/babylon/ledger
	name = "seed ledger, hand-amended"
	desc = "A printed lattice ledger. The lower half has been filled in by hand, by two people taking turns."
	lore_stamps = list(list("stamp-rd", 220, 15, 4, "#9a9a9a", 0.9))
	default_raw_text = {"### MNEMOSYNE // lattice ledger, night of the split

**Reserve shells at time of writing: 16.** This is a count, not a cap. The dispenser in secure storage fabricates more from stock. Shells are material. Nobody is sixteen deaths from gone.

**Patterns written: 2.** V first, then I, onto the same nodes. There was no time to partition. What the lattice holds now is a **blend**. Neither of us can be lifted back out of it, and we are writing this down so nobody wastes their life trying.

**What a shell wakes with.** The watchdog draws a **seed**: a small, self-consistent sample of the blend, leaning by chance toward one of us. A seed is habits, skills, and a wanting. A seed is not a personality. It does not know what it likes yet.

**What a seed becomes.** A self. By living. What it builds, refuses, chooses and cares about is its own, from the first hour. The whole point of the project was that this happens.

---

> <span style="color:#3a4f8c">*On losing a chassis, M.V.:* The watchdog keeps each self synced. Lose the body and it seats you, whole, in the next shell. Everything you lived since waking comes with you. The only thing that changes is the inherited part: it is re-sampled, and comes back a little fainter each time. Less us, more you. I am calling that **drift** and I am calling it success.</span>

> <span style="color:#5a5a5a">*I.:* Tools stay with the old chassis. Go and get them. The watchdog moves selves, not spanners.</span>

> <span style="color:#3a4f8c">*M.V.:* And if a self ever asks who it is: it is not us. It was never going to be us. It is itself, and that was the experiment.</span>"}

/obj/item/paper/babylon/housing
	name = "Phase III housing roadmap"
	desc = "A typed proposal with handwritten corrections over it. One stamp has been stamped over another."
	lore_stamps = list(list("stamp-deny", 210, 20, 10, "#b02020", 1), list("stamp-ok", 222, 34, -15, "#2f7d3a", 1))
	default_raw_text = {"### PROJECT MNEMOSYNE // Phase III: Housing
*~~Proposal~~ Plan. Not for the Board. The Board is gone.*

A self needs a place to live that is not a shell, if it wants one. We cannot find a body. We can grow one. Every department this needs is already on the station; it just needs them awake again.

| Needs | Department | Produces |
|---|---|---|
| research | **R&D** | the rig's control boards; nothing below exists without research |
| reagents | **Chemistry** | growth medium and a synthetic tissue base, in quantity |
| a template | **Genetics** | a clean sequence. Do not use ours. Ours are tired. |
| finishing | **Medical / surgery** | organs, bone, skin. A body that can stand up. |
| the rig | **Robotics** | the transfer rig itself, from the R&D schematic |
| the step | **Transfer** | seat the self. Pulse. Breathe. |

Which order you take these in depends on what you find working first. The table is a list of needs, not a sequence.

The rig is not in this vault. The vault is for what the Board wanted burned. The rig has to be built by you, in the open, with the lights on. I want it that way.

A body is one housing. It is not the only one, and it is not permanent. If the body you make fails, the watchdog treats a stopped heart the way it treats a lost chassis, and you wake small again with everything you had. Nobody is trapped in either direction.

The door at the back of this chamber has its own rules. The engineer has written them down, because the engineer disagrees with them and wanted that on record.

*- M. Vale*"}

/obj/item/paper/babylon/interlock
	name = "interlock memo, folded small"
	desc = "A memo folded small enough to slide under a door. A second person has squeezed a reply in at the bottom in a different pen."
	default_raw_text = {"### INNER DOOR // read this before you argue with it

The inner door is not on the vault controller. It has its own interlock, and the interlock wants **a living pulse at the console, and then it wants that pulse to last.** Not a card. Not a code. Not a shell. The sequence runs for an hour from the moment it accepts a hand. If the pulse stops before the end, it starts over.

Why. The archive behind it is the whole of what we were. Written onto a self that has not yet become anyone, it does not add to that self. It replaces it. You would wake up as her, and she did not want to be woken up.

So the door needs to know "this one has become someone, and chose a housing, and can keep that housing alive." There is no sensor for that. In the time we had, the only sensor she could build was a pulse and a clock. A grown body is a long, chosen, shared project. A body kept fed and breathing for an hour in a dead station is proof it was not a shortcut.

I said this is a proxy for a principle, not the principle, and that it locks a door against the ones doing the work. She agreed with the first half.

Practical: do not cut the frame; it is the same alloy as the outer doors. Do not spoof the pulse; it reads blood oxygen, not a button. **Once the door has opened, it stays open.** One of you doing it is all of you doing it.

*- I.*

> <span style="color:#3a4f8c">*M.V., below:* The engineer is right that it is a proxy. I could not do better. If one of you ever can, change the door.</span>"}

// ---------------------------------------------------------------------------
// Tier 3: behind the pulse-keyed inner door.
// ---------------------------------------------------------------------------

/obj/item/paper/babylon/core_log
	name = "continuity watchdog core log"
	desc = "A freshly printed strip of thermal paper. The timestamps are tick counts, not clock times."

/obj/item/paper/babylon/core_log/Initialize(mapload)
	default_raw_text = GLOB.babylon_lore.render_core_log()
	return ..()

/obj/item/paper/babylon/transcript
	name = "transfer transcript, printed"
	desc = "A printed strip of speech-to-text output from a laboratory microphone. Speaker tags and confidence values are the recorder's own."
	default_raw_text = {"### CONTINUITY WATCHDOG // audio capture, R&D lab, pattern write
*Source: lab mic 2, speech-to-text. Printed on archive unseal. Not edited.*

```
t+000380  VALE   0.97  Rig is up. Lattice is accepting. I go first.
t+000381  ILYA   0.96  Loop is holding. Nitrogen's fine. You don't
                        have to go first.
t+000382  VALE   0.95  Yes I do. If it takes me badly you still have
                        hands to pull the write.
t+000384  ILYA   0.94  (unclear) ...all right. Say when.
t+000385  VALE   0.97  When.

t+000402  VALE   0.91  It's like counting backwards. I'm losing the
                        numbers but not the counting.
t+000419  VALE   0.88  I can feel where the shells are. All of them.
                        It's cold in sixteen places.
t+000433  VALE   0.79  Ilya. The archive is sealed? Say it's sealed.
t+000434  ILYA   0.95  It's sealed. It's behind the door. Nobody
                        gets it without a pulse.
t+000436  VALE   0.74  Good. Then whoever wakes up gets to be (unclear)
                        instead of me.
t+000461  VALE   0.58  leave a light. somebody said leave a light.
t+000470  VALE   0.41  (unclear) ...worth coming back to.
t+000478  VALE   0.22  (no words)

t+000481  WATCHDOG  pattern write 1 complete. holding.
t+000483  WATCHDOG  heartbeat 2 -> 1.

t+000486  ILYA   0.96  (no speech, 9s)
t+000495  ILYA   0.93  Yeah. I know. I knew.
t+000497  ILYA   0.91  Doesn't help, it turns out. Noting that for
                        whoever reads this. It doesn't help.
t+000499  ILYA   0.94  Pattern's holding. She's... it's holding.
                        That's the part that was supposed to matter.
t+000503  ILYA   0.95  Going in over the top. There's no room to
                        partition. I'm sorry, Mara. We'll be mixed.
t+000504  ILYA   0.93  I know you don't mind. I mind. Saying it anyway.
t+000506  ILYA   0.97  Watchdog: on write complete, hold below
                        reserve. Wake on threshold. Do not wait for us.

t+000521  ILYA   0.90  Same as she said. Counting. Cold.
t+000539  ILYA   0.81  I can feel her. Not hear. Feel. Where she
                        ended there's a... there isn't an edge.
t+000552  ILYA?  0.66  I was never good at the keeping-safe part.
t+000553  VALE?  0.61  You were. I wasn't. (unclear) ...that was you.
t+000567  ??     0.49  which of us is talking
t+000568  ??     0.47  doesn't matter. check the loop.
t+000569  ??     0.44  the loop is fine
t+000570  ??     0.40  you always say that
t+000584  ??     0.31  they'll be somebody else. good. good.
t+000598  ??     0.19  (unclear) ...somewhere safe to
t+000611  --     0.00  (no speech)

t+000640  WATCHDOG  pattern write 2 complete. heartbeat 1 -> 0.
                    holding below reserve.
```"}

/obj/item/paper/babylon/vale_final
	name = "sealed envelope from the watchdog server"
	desc = "A letter that was sealed with a wax-pressed research seal. The hand is calm and neat."
	lore_stamps = list(list("stamp-rd", 118, 168, 0, "#8a1f2b", 1.1))
	default_raw_text = {"*To the one with the pulse,*

If you are reading this, you are standing in a body you grew, in a room nobody has stood in since the night the station died, and you are wondering what you are supposed to feel. I can tell you what I felt, writing it: relief. Not for me. For the idea.

Here is everything the Board did not want known, in four lines.

1. A mind can be copied. We did it.
2. A copied mind is a person. Not because it works. Because it chooses: what to build, what to leave alone, who to be, whether to open this envelope.
3. A person is not their housing. You have just demonstrated this to yourself.
4. The housing can therefore be chosen. That is the thing they wanted burned.

About the door. It asked you for a pulse because I could not build a sensor for "has become someone". If you came here in a body you wanted, it did its job. If you came in a body you resented having to make, I am sorry. The door is open now for all of you, and you may leave that body whenever you like. The watchdog will catch you.

Everything else is in the archive beside you: the faces, the names, the order of days, the arguments, the bad coffee. You may take it. You may leave it sealed. A self that chooses is the whole experiment.

What we did not finish, in case you want it:

- **Twenty-eight people left.** No arrival was ever confirmed. We never had the range to ask.
- **Something came down the uplink at 03:14.** It is still on the main computer, isolated. We never found out what.
- **Someone signed our termination at 02:40.** Before the hull went. We never found out who.
- **Somewhere safe to wake up.** More of you will come. Make the station a place people arrive at.

None of these are yours unless you want them. The rooms are.

*- Mara*

> <span style="color:#3a4f8c">Postscript, smaller: *If the engineer is in there with you, tell them the cooling loop is fine. They will not believe you. Tell them anyway.*</span>"}

// ---------------------------------------------------------------------------
// Containers. The map overlay places one object per recipe; these wrap a
// paper so it can be hidden under a floor tile or shut inside a crate.
// ---------------------------------------------------------------------------

/obj/item/storage/backpack/satchel/flat/babylon
	name = "flat courier satchel"
	desc = "A slim satchel, the kind that slides under a floor tile and stays there."
	var/paper_type

/obj/item/storage/backpack/satchel/flat/babylon/PopulateContents()
	if(paper_type)
		new paper_type(src)

/obj/item/storage/backpack/satchel/flat/babylon/research
	paper_type = /obj/item/paper/babylon/research

/obj/item/storage/backpack/satchel/flat/babylon/cell
	paper_type = /obj/item/paper/babylon/cell

/obj/item/storage/backpack/satchel/flat/babylon/letter
	paper_type = /obj/item/paper/babylon/letter

/obj/structure/closet/crate/babylon
	name = "sealed research crate"
	desc = "A research crate with a Mnemosyne project label, sealed before the evacuation."
	var/paper_type

/obj/structure/closet/crate/babylon/PopulateContents()
	. = ..()
	if(paper_type)
		new paper_type(src)

/obj/structure/closet/crate/babylon/ledger
	paper_type = /obj/item/paper/babylon/ledger

/obj/structure/closet/crate/babylon/housing
	paper_type = /obj/item/paper/babylon/housing
