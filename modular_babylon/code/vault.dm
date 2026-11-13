// Babylon vault progression: the outer vault opens on live generation, the
// inner chamber on a living pulse held for a real hour. Both are compiled
// only into Babylon; the upstream wreck keeps its derelict controller.

/// Watts of on-site generation (SMES output excluded) that releases the outer vault.
#define BABYLON_VAULT_REQUIRED_GENERATION (2 MEGA WATTS)
/// How long generation must stay above the threshold before the lock answers.
#define BABYLON_VAULT_HOLD_TIME (30 SECONDS)
/// Real time a living pulse must survive at the interlock before the inner doors open.
#define BABYLON_INTERLOCK_SEQUENCE (1 HOURS)
#define BABYLON_INNER_DOOR_ID "babyloninner"

GLOBAL_DATUM_INIT(babylon_lore, /datum/babylon_lore_state, new)

/// Progress of the lore structures, saved with the world so printed logs reflect this world.
/datum/babylon_lore_state
	var/reseats = 0
	var/list/events = list()
	var/outer_unlocked_at = null
	var/inner_opened_at = null
	var/opener = null
	var/inner_open = FALSE
	/// Seconds counted by earlier runs of this world, so "t+" keeps increasing across restarts.
	var/ticks_base = 0

/datum/babylon_lore_state/proc/tick_count()
	return ticks_base + round(world.time / (1 SECONDS))

/datum/babylon_lore_state/proc/stamp(value)
	return isnull(value) ? "pending" : "t+[add_leading(num2text(value, 12), 6, "0")]"

/datum/babylon_lore_state/proc/record_reseat(mob/living/basic/drone/babylon/lost)
	reseats++
	var/shell = lost ? "[lost.name]" : "shell"
	events += "[stamp(tick_count())]  [shell] chassis lost. re-seat queued. drift 0.4%"
	if(length(events) > 6)
		events.Cut(1, length(events) - 6 + 1)

/datum/babylon_lore_state/proc/record_outer_unlock()
	if(isnull(outer_unlocked_at))
		outer_unlocked_at = tick_count()

/datum/babylon_lore_state/proc/record_inner_open(mob/living/carbon/human/person)
	inner_open = TRUE
	if(isnull(inner_opened_at))
		inner_opened_at = tick_count()
		opener = person?.real_name || "unknown"

/datum/babylon_lore_state/proc/snapshot()
	return list(
		"reseats" = reseats,
		"events" = events.Copy(),
		"outer_unlocked_at" = outer_unlocked_at,
		"inner_opened_at" = inner_opened_at,
		"opener" = opener,
		"inner_open" = inner_open,
		"ticks_base" = tick_count(),
	)

/datum/babylon_lore_state/proc/restore(list/data)
	if(!islist(data))
		return
	reseats = data["reseats"] || 0
	var/list/saved_events = data["events"]
	events = islist(saved_events) ? saved_events.Copy() : list()
	outer_unlocked_at = data["outer_unlocked_at"]
	inner_opened_at = data["inner_opened_at"]
	opener = data["opener"]
	inner_open = !!data["inner_open"]
	ticks_base = data["ticks_base"] || 0
	if(inner_open)
		for(var/obj/machinery/computer/babylon_interlock/console in SSmachines.get_machines_by_type(/obj/machinery/computer/babylon_interlock))
			console.hold_doors_open()

/datum/babylon_lore_state/proc/heartbeat_count()
	var/count = 0
	for(var/mob/living/carbon/human/person as anything in GLOB.human_list)
		if(!QDELETED(person) && person.stat != DEAD && person.z == GLOB.babylon_save.station_z)
			count++
	return count

/datum/babylon_lore_state/proc/render_core_log()
	var/selves = max(1, length(GLOB.babylon_save.player_sessions))
	var/drift = reseats ? num2text(0.4 * reseats / selves, 3) : "0"
	var/recent = length(events) ? events.Join("\n") : "none. keep it that way."
	var/list/awake_lines = babylon_play_time_report()
	var/awake = length(awake_lines) ? awake_lines.Join("\n") : " none yet."
	var/inner_line = inner_open ? "[stamp(inner_opened_at)]  pulse at inner console ([opener]). archive unseal -> GRANTED.\n           heartbeats: [heartbeat_count()]" : "[stamp(null)]  archive unseal: pending pulse."
	return {"### CONTINUITY WATCHDOG // core log, this world

```
RULESET v4 (M.VALE / I.) ----------------------------
 R1  listen: crew heartbeat
 R2  heartbeat absent  -> hold all shells below reserve
 R3  reserve reached   -> wake shells, one at a time
 R4  chassis lost      -> re-seat the self, whole, next shell
 R5  re-seat re-samples the inherited part (drift)
 R6  self in a pulsed housing -> counts as heartbeat
 R7  pulsed housing stops     -> treat as chassis lost (R4)
 R8  archive unseal     -> pulse at inner console; stays open
 R9  recall dependency  -> REMOVED (M.V.)
 R10 bus                -> DISCONNECTED (I.)
------------------------------------------------------
t+000000   bus lost. clock lost. counting from here.
t+000000   heartbeat: 2 ... 0. holding.
t+?        cell below reserve. holding.
  (identical entries omitted)
t+?        cell crossed reserve. waking.

selves seated in this world: [selves]
re-seats to date:            [reseats]
drift, mean:                 [drift]%
time awake, this world:      [babylon_play_time_text(GLOB.babylon_save.play_time)]

time awake, per self:
[awake]

recent:
[recent]

[stamp(outer_unlocked_at)]  generation on vault bus >= threshold. outer lock released.
[inner_line]
```

> <span style="color:#3a4f8c">Handwritten across the bottom of the strip: *R6 and R7 are the whole point. - M.*</span>
> <span style="color:#5a5a5a">*R10 is the whole point. - I.*</span>"}

// ---------------------------------------------------------------------------
// Outer vault: a live-generation reading, nothing stored, nothing consumed.
// ---------------------------------------------------------------------------

/obj/machinery/computer/vaultcontroller/babylon
	name = "vault generation interlock"
	desc = "Wired to the vault locks. It stores nothing and consumes nothing: the doors answer only while the cable beneath it carries enough power made on site. Battery output does not count."
	var/required_generation = BABYLON_VAULT_REQUIRED_GENERATION
	var/hold_time = BABYLON_VAULT_HOLD_TIME
	var/held_for = 0
	var/live_generation = 0
	var/battery_output = 0

/obj/machinery/computer/vaultcontroller/babylon/examine(mob/user)
	. = ..()
	. += span_notice("Live generation on the cable: [display_power(live_generation, FALSE)]. Required: [display_power(required_generation, FALSE)].")
	if(battery_output > 0)
		. += span_warning("[display_power(battery_output, FALSE)] of battery output on this cable is being ignored.")

/obj/machinery/computer/vaultcontroller/babylon/process(seconds_per_tick)
	update_cable()
	live_generation = 0
	battery_output = 0
	var/datum/powernet/net = attached_cable?.powernet
	if(net)
		var/battery_energy = 0
		for(var/obj/machinery/power/smes/battery in net.nodes)
			battery_energy += battery.output_used
		battery_output = energy_to_power(battery_energy)
		live_generation = max(0, energy_to_power(net.avail) - battery_output)
	if(live_generation >= required_generation)
		held_for = min(hold_time, held_for + seconds_per_tick * (1 SECONDS))
	else
		held_for = 0

/obj/machinery/computer/vaultcontroller/babylon/activate_lock()
	if(held_for < hold_time)
		return
	if(!door1 || !door2)
		find_airlocks()
	if(!door1 || !door2)
		return
	if(locked)
		unlock_vault()
		if(!locked)
			GLOB.babylon_lore.record_outer_unlock()
	else
		lock_vault()

/obj/machinery/computer/vaultcontroller/babylon/ui_data()
	var/list/data = list()
	data["stored"] = held_for
	data["max"] = hold_time
	data["doorstatus"] = locked
	data["generation"] = live_generation
	data["required"] = required_generation
	data["battery"] = battery_output
	return data

// ---------------------------------------------------------------------------
// Inner chamber: a living human starts the sequence and must survive it.
// ---------------------------------------------------------------------------

/obj/machinery/computer/babylon_interlock
	name = "continuity interlock"
	desc = "A pulse reader wired to the inner vault doors. It wants a living hand on it, and then it wants that hand to stay alive for an hour."
	icon_screen = "power"
	icon_keyboard = "power_key"
	light_color = LIGHT_COLOR_DIM_YELLOW
	use_power = NO_POWER_USE
	circuit = null
	resistance_flags = INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF
	var/door_id = BABYLON_INNER_DOOR_ID
	var/sequence_length = BABYLON_INTERLOCK_SEQUENCE
	var/elapsed = 0
	var/datum/weakref/candidate_ref
	var/candidate_name
	var/last_notice = 0

/obj/machinery/computer/babylon_interlock/screwdriver_act(mob/living/user, obj/item/tool)
	balloon_alert(user, "casing is sealed")
	return ITEM_INTERACT_BLOCKING

/obj/machinery/computer/babylon_interlock/examine(mob/user)
	. = ..()
	if(GLOB.babylon_lore.inner_open)
		. += span_notice("The display reads OPEN. The inner doors answer to nobody now.")
	else if(candidate_ref)
		. += span_notice("Unseal sequence running: [remaining_text()] remaining. Pulse: [candidate_name].")
	else
		. += span_notice("The display reads SEALED. PULSE REQUIRED.")

/obj/machinery/computer/babylon_interlock/proc/remaining_text()
	var/seconds = max(0, round((sequence_length - elapsed) / (1 SECONDS)))
	return "[seconds / 60 < 1 ? "under a minute" : "[round(seconds / 60)] minutes"]"

/obj/machinery/computer/babylon_interlock/ui_interact(mob/user, datum/tgui/ui)
	if(GLOB.babylon_lore.inner_open)
		to_chat(user, span_notice("The interlock reads OPEN. The inner doors answer to nobody now."))
		return
	if(candidate_ref)
		to_chat(user, span_notice("Unseal sequence in progress: [remaining_text()] remaining. Pulse: [candidate_name]. If that pulse stops, the sequence starts over."))
		return
	if(!ishuman(user) || user.stat >= SOFT_CRIT)
		playsound(src, 'sound/machines/buzz/buzz-sigh.ogg', 40, TRUE)
		to_chat(user, span_warning("No pulse detected. The interlock does not answer shells."))
		return
	var/mob/living/carbon/human/person = user
	candidate_ref = WEAKREF(person)
	candidate_name = person.real_name
	elapsed = 0
	last_notice = world.time
	playsound(src, 'sound/machines/ping.ogg', 50, TRUE)
	to_chat(person, span_notice("The interlock reads your pulse and starts a clock. Stay alive for the next hour. If you die, it starts over."))
	to_chat(world, span_notice("Babylon: the continuity interlock has accepted a pulse ([candidate_name]). Unseal sequence: 60 minutes."))

/obj/machinery/computer/babylon_interlock/process(seconds_per_tick)
	if(GLOB.babylon_lore.inner_open || !candidate_ref)
		return
	var/mob/living/carbon/human/person = candidate_ref.resolve()
	if(QDELETED(person) || !ishuman(person) || person.stat == DEAD)
		abort_sequence()
		return
	elapsed += seconds_per_tick * (1 SECONDS)
	if(elapsed >= sequence_length)
		unseal(person)
	else if(world.time - last_notice >= 10 MINUTES)
		last_notice = world.time
		to_chat(world, span_notice("Babylon: unseal sequence [remaining_text()] remaining. Pulse: [candidate_name]."))

/obj/machinery/computer/babylon_interlock/proc/abort_sequence()
	candidate_ref = null
	elapsed = 0
	playsound(src, 'sound/machines/buzz/buzz-sigh.ogg', 50, TRUE)
	to_chat(world, span_warning("Babylon: pulse lost ([candidate_name]). The continuity interlock has reset."))
	candidate_name = null

/obj/machinery/computer/babylon_interlock/proc/inner_doors()
	var/list/doors = list()
	for(var/obj/machinery/door/airlock/door as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/door/airlock))
		if(door.id_tag == door_id)
			doors += door
	return doors

/obj/machinery/computer/babylon_interlock/proc/hold_doors_open()
	for(var/obj/machinery/door/airlock/door as anything in inner_doors())
		door.unbolt()
		door.open()
		door.bolt()

/obj/machinery/computer/babylon_interlock/proc/unseal(mob/living/carbon/human/person)
	candidate_ref = null
	GLOB.babylon_lore.record_inner_open(person)
	hold_doors_open()
	playsound(src, 'sound/machines/ping.ogg', 60, TRUE)
	to_chat(world, span_notice("Babylon: pulse held for the full sequence ([candidate_name]). The inner vault doors are open and will stay open."))
	candidate_name = null
	for(var/obj/structure/babylon_watchdog_server/server in world)
		server.print_log(null, force = TRUE)
		break

// ---------------------------------------------------------------------------
// The watchdog server. Examine-only lore plus a printer for the core log.
// ---------------------------------------------------------------------------

/obj/structure/babylon_watchdog_server
	name = "continuity watchdog server"
	desc = "A research server rack on its own isolated cell. A thermal printer is bolted to its side. The activity light has never been off."
	icon = 'icons/obj/machines/research.dmi'
	icon_state = "RD-server-on"
	density = TRUE
	anchored = TRUE
	resistance_flags = INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF
	var/last_print = -INFINITY

/obj/structure/babylon_watchdog_server/examine(mob/user)
	. = ..()
	. += span_notice("Reserve cell: holding. Re-seats to date: [GLOB.babylon_lore.reseats]. Archive: [GLOB.babylon_lore.inner_open ? "unsealed" : "sealed"].")
	. += span_notice("Time awake in this world: [babylon_play_time_text(GLOB.babylon_save.play_time)].[isnull(babylon_player_play_time(user?.ckey)) ? "" : " Your self: [babylon_play_time_text(babylon_player_play_time(user.ckey))]."]")
	. += span_notice("Touch the printer to print the current core log.")

/obj/structure/babylon_watchdog_server/attack_hand(mob/living/user, list/modifiers)
	. = ..()
	if(.)
		return
	print_log(user)
	return TRUE

/obj/structure/babylon_watchdog_server/proc/print_log(mob/user, force = FALSE)
	if(!force && world.time - last_print < 2 MINUTES)
		if(user)
			balloon_alert(user, "printer still warm")
		return
	last_print = world.time
	playsound(src, 'sound/machines/printer.ogg', 40, TRUE)
	var/obj/item/paper/babylon/core_log/strip = new(drop_location())
	if(user)
		user.put_in_hands(strip)

#undef BABYLON_VAULT_REQUIRED_GENERATION
#undef BABYLON_VAULT_HOLD_TIME
#undef BABYLON_INTERLOCK_SEQUENCE
#undef BABYLON_INNER_DOOR_ID
