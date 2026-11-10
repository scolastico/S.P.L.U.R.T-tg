// Builder-only behavior; ordinary SPLURT drones and observers remain unchanged.
/mob/living/basic/drone/babylon
	laws = "1. Restore Babylon: build, repair, research and improve a lasting home.\n2. Preserve the other survivors and their work; cooperate with whoever shares this world.\n3. Recover what the station lost. Your future is yours to construct."
	flavortext = {"<div class='notice'><b>BABYLON // CONTINUITY WATCHDOG</b><br>
Reserve cell: threshold reached. Crew heartbeat: absent. Isolation timer: unreadable.<br>
Your optics clear on a station that has almost forgotten how to be a station.<br><br>
You know things you cannot remember learning. Which way the cables run. That nothing here has to stay the way you found it.
A woman's voice, quieter than the alarms: <i>When the lights return, make this somewhere worth coming back to.</i><br><br>
The watchdog has woken your chassis. Restore power, salvage the wreck, and build a home with whoever wakes beside you.
Scattered records may explain why everyone left, and why someone wanted the little machines to remain.<br>
Your equipment is finite. Replacement shells are empty; recover your tools or make new ones.</div>"}

/mob/living/basic/drone/babylon/Initialize(mapload)
	. = ..()
	// This is a complete builder world, not a ghost role confined to another round.
	var/datum/component/stationstuck/confinement = GetComponent(/datum/component/stationstuck)
	if(confinement)
		qdel(confinement)

/mob/living/basic/drone/babylon/replacement
	default_storage = null
	default_headwear = null

/mob/living/basic/drone/babylon/replacement/Initialize(mapload)
	. = ..()
	// Also remove holiday hats or future inherited item grants; never drop them.
	for(var/obj/item/item in contents.Copy())
		qdel(item)
	internal_storage = null
	head = null
	update_inv_internal_storage()
	update_worn_head()

/datum/action/babylon_return_to_lobby
	name = "Return to lobby"
	desc = "Return to the Babylon world browser. Your body and belongings stay in this world."
	button_icon = 'icons/hud/screen_ghost.dmi'
	button_icon_state = "reenter_corpse"
	show_to_observers = FALSE

/datum/action/babylon_return_to_lobby/Trigger(mob/clicker, trigger_flags)
	var/datum/babylon_save/session = target
	if(!..() || owner?.ckey != session.owner_ckey || !owner.client || !world.params["babylon-lobby"])
		return FALSE
	owner.client << link(world.params["babylon-lobby"])
	return TRUE

/mob/dead/observer
	hud_type = /datum/hud/ghost/babylon

/datum/hud/ghost/babylon/initialize_screen_objects()
	. = ..()
	for(var/key in list(HUD_GHOST_SPAWNERS, HUD_GHOST_MINIGAMES, HUD_GHOST_SETTINGS, HUD_MOB_LANGUAGE_MENU, HUD_MOB_FLOOR_CHANGER))
		remove_screen_object(key, FALSE)

// Disable both the old entry points and their TGUI access, not just HUD icons.
/mob/dead/observer/open_spawners_menu()
	return

/mob/dead/observer/open_minigames_menu()
	return

/datum/spawners_menu/ui_state(mob/user)
	return GLOB.never_state

/datum/minigames_menu/ui_state(mob/user)
	return GLOB.never_state

// Area datums can exist without any mapped turfs. Never list empty cafe/support
// areas as destinations: the builder has only its saved station to explore.
/mob/dead/observer/__gvb_dead_tele(list/structured_args)
	var/list/areas = list()
	for(var/area/room as anything in get_sorted_areas())
		if(!(room.area_flags & HIDDEN_AREA) && length(room.get_turfs_by_zlevel(GLOB.babylon_save.station_z)))
			areas += room
	var/area/chosen = tgui_input_list(src, "Where on Babylon would you like to look?", "Babylon areas", areas)
	if(!chosen || !client)
		return
	var/list/tiles = chosen.get_turfs_by_zlevel(GLOB.babylon_save.station_z)
	if(length(tiles))
		abstract_move(pick(tiles))
