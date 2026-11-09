/datum/babylon_save/proc/capture_drone_profile()
	var/list/profile = list()
	if(!builder)
		return drone_profile.Copy()
	for(var/field in list("name", "real_name", "visualAppearance", "picked", "colour", "icon_living", "icon_dead"))
		profile[field] = builder.vars[field]
	return profile

/datum/babylon_save/proc/install_drone_actions()
	QDEL_NULL(destruct_action)
	QDEL_NULL(return_action)
	install_return_action(builder)
	destruct_action = new(src)
	destruct_action.Grant(builder)

/datum/babylon_save/proc/install_return_action(mob/player)
	if(!world.params["babylon-lobby"] || !player)
		return
	if(!return_action)
		return_action = new(src)
	if(return_action.owner != player)
		return_action.Grant(player)

/datum/babylon_save/proc/begin_respawn(mob/living/basic/drone/babylon/dead_drone)
	if(respawn_pending)
		return
	if(dead_drone && dead_drone != builder)
		return
	drone_profile = capture_drone_profile()
	respawn_pending = TRUE
	respawn_ready_at = world.time + 60 SECONDS
	QDEL_NULL(destruct_action)
	to_chat(world, span_notice("Babylon drone lost. Respawn becomes available in 60 seconds."))

/datum/babylon_save/proc/update_respawn_player(client/student)
	if(!student)
		return
	if(!isobserver(student.mob))
		if(student.mob == builder && !QDELETED(builder))
			builder.ghostize(can_reenter_corpse = FALSE, forced = TRUE)
		else
			var/mob/previous = student.mob
			var/mob/dead/observer/ghost = new(respawn_turf)
			ghost.forceMove(respawn_turf)
			ghost.can_reenter_corpse = FALSE
			ghost.PossessByPlayer(student.ckey)
			if(isnewplayer(previous))
				qdel(previous)
	if(!respawn_action)
		respawn_action = new(src)
	install_return_action(student.mob)
	if(respawn_action.owner != student.mob)
		respawn_action.Grant(student.mob)
	var/seconds_left = ceil(max(0, respawn_ready_at - world.time) / (1 SECONDS))
	respawn_action.name = seconds_left ? "Respawn ([seconds_left]s)" : "Respawn drone"
	respawn_action.desc = seconds_left ? "New drone available in [seconds_left] seconds." : "Return in a new drone at the engineering spawn."
	respawn_action.build_all_button_icons()

/datum/babylon_save/proc/respawn_builder(mob/requester)
	if(requester && requester.ckey != owner_ckey)
		return FALSE
	if(!respawn_pending || world.time < respawn_ready_at || GLOB.babylon_save.busy || GLOB.babylon_save.draining)
		return FALSE
	var/turf/spawn_point = respawn_turf
	if(!valid_respawn_tile(spawn_point))
		spawn_point = find_respawn_tile()
	if(!spawn_point)
		to_chat(requester, span_warning("No engineering floor is available for respawn."))
		return FALSE
	var/mob/living/basic/drone/babylon/replacement/replacement = new(spawn_point)
	for(var/field in drone_profile)
		replacement.vars[field] = drone_profile[field]
	replacement.icon_state = replacement.icon_living
	// Never repeat the first-join appearance prompt after a replacement.
	replacement.picked = TRUE
	builder = replacement
	respawn_pending = FALSE
	respawn_ready_at = 0
	QDEL_NULL(respawn_action)
	install_drone_actions()
	var/client/student = GLOB.directory[owner_ckey]
	if(student)
		var/mob/previous = student.mob
		builder.PossessByPlayer(student.ckey)
		if(isobserver(previous) || isnewplayer(previous))
			qdel(previous)
	to_chat(builder, span_notice("New Babylon drone ready. Your previous inventory remains where it was dropped."))
	return TRUE

/datum/babylon_save/proc/valid_respawn_tile(turf/tile)
	if(!isopenturf(tile) || isspaceturf(tile) || tile.z != station_z || tile.density)
		return FALSE
	for(var/obj/obstacle in tile)
		if(obstacle.density)
			return FALSE
	return TRUE

/datum/babylon_save/proc/find_respawn_tile()
	for(var/turf/open/floor/tile in world)
		if(tile.z == station_z && istype(get_area(tile), /area/ruin/space/bb13/engineering/sec_eng) && valid_respawn_tile(tile))
			return tile
	return null

/datum/babylon_save/proc/vaporize_builder()
	if(QDELETED(builder) || builder.stat == DEAD || respawn_pending || GLOB.babylon_save.busy || GLOB.babylon_save.draining)
		return FALSE
	var/mob/living/basic/drone/babylon/doomed = builder
	var/turf/drop_point = get_turf(doomed)
	if(!drop_point)
		return FALSE
	// Drop containers intact: their contents must not be destroyed or duplicated.
	doomed.drop_all_held_items()
	for(var/obj/item/item in doomed.contents.Copy())
		doomed.doUnEquip(item, force = TRUE, newloc = drop_point)
		if(item.loc == doomed)
			item.forceMove(drop_point)
	doomed.death()
	if(doomed.client)
		doomed.ghostize(can_reenter_corpse = FALSE, forced = TRUE)
	doomed.dust_animation()
	QDEL_IN(doomed, 2 SECONDS)
	return TRUE

/mob/living/basic/drone/babylon/death(gibbed)
	. = ..()
	var/datum/babylon_save/player = GLOB.babylon_save?.player_for_drone(src)
	if(player)
		player.begin_respawn(src)

/mob/living/basic/drone/babylon/Destroy()
	var/datum/babylon_save/player = GLOB.babylon_save?.player_for_drone(src)
	if(GLOB.babylon_save?.ready && player)
		player.begin_respawn(src)
	return ..()

/datum/action/babylon_self_destruct
	name = "Self-destruct"
	desc = "Vaporize this drone, drop its inventory, and begin the 60-second respawn cooldown. Requires confirmation."
	button_icon = 'icons/mob/silicon/drone.dmi'
	button_icon_state = "drone_maint_dead"
	show_to_observers = FALSE

/datum/action/babylon_self_destruct/Trigger(mob/clicker, trigger_flags)
	var/datum/babylon_save/session = target
	if(!..() || owner?.ckey != session.owner_ckey || owner != session.builder)
		return FALSE
	if(tgui_alert(owner, "Vaporize your drone? All carried items will drop at your current position. You can respawn after 60 seconds.", "Confirm self-destruct", list("Cancel", "Self-destruct")) != "Self-destruct")
		return FALSE
	if(owner != session.builder || owner?.stat == DEAD)
		return FALSE
	return session.vaporize_builder()

/datum/action/babylon_respawn
	name = "Respawn drone"
	desc = "Return in a new Babylon drone when the cooldown finishes."
	button_icon = 'icons/mob/silicon/drone.dmi'
	button_icon_state = "drone_maint_grey"
	show_to_observers = FALSE

/datum/action/babylon_respawn/IsAvailable(feedback = FALSE)
	var/datum/babylon_save/session = target
	return ..() && session.respawn_pending && world.time >= session.respawn_ready_at

/datum/action/babylon_respawn/apply_button_icon(atom/movable/screen/movable/action_button/button, force = FALSE)
	. = ..()
	var/datum/babylon_save/session = target
	var/seconds_left = ceil(max(0, session.respawn_ready_at - world.time) / (1 SECONDS))
	button.maptext_x = 2
	button.maptext_y = 2
	button.maptext_width = 32
	button.maptext_height = 16
	button.maptext = MAPTEXT_TINY_UNICODE(seconds_left ? "[seconds_left]s" : "Ready")

/datum/action/babylon_respawn/Trigger(mob/clicker, trigger_flags)
	if(!..())
		return FALSE
	var/datum/babylon_save/session = target
	return session.respawn_builder(owner)

/mob/dead/observer/get_status_tab_items()
	. = ..()
	var/datum/babylon_save/session = GLOB.babylon_save.player_sessions[ckey]
	if(session?.ready && session.respawn_pending)
		var/seconds_left = ceil(max(0, session.respawn_ready_at - world.time) / (1 SECONDS))
		. += seconds_left ? "Babylon respawn: [seconds_left] seconds" : "Babylon respawn: READY — click Respawn drone"
