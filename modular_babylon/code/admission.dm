// Trusted server-to-server API. Player input never supplies the actor or credential.
/proc/babylon_supervisor_request(list/query)
	var/api = world.params["babylon-api"]
	if(!api || !findtext(api, "http://127.0.0.1:"))
		return null
	query["run"] = world.params["babylon-run"]
	query["secret"] = world.params["babylon-secret"]
	var/list/response = world.Export("[api]/api?[list2params(query)]")
	if(!response || !response["CONTENT"])
		return null
	try
		return json_decode(file2text(response["CONTENT"]))
	catch
		return null

/client/proc/babylon_admit(topic_data)
	if(!world.params["babylon-world"])
		return ckey == ckey(world.params["babylon-owner"])
	if(!GLOB.babylon_save.ready || GLOB.babylon_save.draining || !ckey || findtext(ckey, "guest") == 1)
		return FALSE
	var/list/params = params2list(topic_data)
	var/ticket = params["babylon_ticket"]
	if(!istext(ticket) || length(ticket) > 128)
		return FALSE
	var/list/result = babylon_supervisor_request(list("action" = "redeem", "ticket" = ticket, "actor" = ckey))
	if(!result?["ok"] || result["world"] != world.params["babylon-world"] || result["run"] != world.params["babylon-run"] || !(result["mode"] in list("player", "showcase")))
		return FALSE
	// Only the authenticated supervisor response can grant a play mode.
	babylon_showcase_visitor = result["mode"] == "showcase"
	if(babylon_showcase_visitor)
		babylon_restrict_visitor_verbs()
	return TRUE

/client/verb/babylon_return_lobby()
	set name = "Return to Babylon lobby"
	set category = "Babylon"
	if(world.params["babylon-lobby"])
		src << link(world.params["babylon-lobby"])

/datum/babylon_save/proc/managed_stop()
	if(draining)
		return list("error" = "Already stopping")
	draining = TRUE
	to_chat(world, span_notice("This world is stopping. Saving progress and returning players to the lobby."))
	// save_world keeps both physics and player controls paused until process exit.
	var/list/result = save_world()
	if(!result["ok"])
		draining = FALSE
		return result
	for(var/client/player in GLOB.clients.Copy())
		if(world.params["babylon-lobby"])
			player << link(world.params["babylon-lobby"])
	// The master (including its timer subsystem) is paused after the snapshot.
	// BYOND spawn still runs, so exit cannot depend on a subsystem timer here.
	spawn(3 SECONDS)
		stop_world()
	return result

/datum/babylon_save/proc/player_for_drone(mob/living/basic/drone/babylon/drone)
	for(var/player_key in player_sessions)
		var/datum/babylon_save/player = player_sessions[player_key]
		if(player.builder == drone)
			return player
	return null

/datum/babylon_save/proc/ensure_player(player_key)
	player_key = ckey(player_key)
	if(!player_key)
		return null
	var/client/student = GLOB.directory[player_key]
	if(student?.babylon_showcase_visitor)
		return null
	var/datum/babylon_save/player = player_sessions[player_key]
	if(player)
		return player
	var/turf/spawn_point = find_respawn_tile()
	if(!spawn_point)
		return null
	player = new
	player.owner_ckey = player_key
	player.station_z = station_z
	player.respawn_turf = spawn_point
	player.builder = new(spawn_point)
	player_sessions[player_key] = player
	return player

/datum/babylon_save/proc/player_snapshot(datum/babylon_save/player)
	return list("builder" = !QDELETED(player.builder) ? player.builder.babylon_save_id : null, "respawn_pending" = player.respawn_pending, "respawn_remaining" = max(0, player.respawn_ready_at - world.time), "spawn_x" = player.respawn_turf?.x, "spawn_y" = player.respawn_turf?.y, "profile" = player.respawn_pending ? player.drone_profile.Copy() : player.capture_drone_profile())

/datum/babylon_save/proc/restore_player(datum/babylon_save/player, list/snapshot)
	player.station_z = station_z
	player.builder = restored_atoms[snapshot["builder"]]
	player.respawn_pending = snapshot["respawn_pending"]
	player.respawn_ready_at = player.respawn_pending ? world.time + snapshot["respawn_remaining"] : 0
	player.drone_profile = snapshot["profile"] || list()
	if(snapshot["spawn_x"] && snapshot["spawn_y"])
		player.respawn_turf = locate(snapshot["spawn_x"], snapshot["spawn_y"], station_z)
	var/mob/living/basic/drone/babylon/drone = player.builder
	if(!drone)
		return
	var/list/hands = drone.held_items.Copy()
	drone.held_items = new /list(length(hands))
	for(var/index in 1 to length(hands))
		var/obj/item/item = hands[index]
		if(item)
			drone.put_in_hand(item, index, forced = TRUE)
	if(!("picked" in resume_records[drone.babylon_save_id]["fields"]))
		drone.picked = TRUE
	drone.update_held_items()
	drone.update_inv_internal_storage()
	drone.update_worn_head()

/datum/babylon_save/proc/tick_player(datum/babylon_save/player, client/student)
	if(student?.babylon_showcase_visitor)
		return
	player.station_z = station_z
	player.ready = ready
	if(!player.respawn_turf)
		player.respawn_turf = respawn_turf
	if(!player.respawn_pending && QDELETED(player.builder))
		player.begin_respawn()
	if(player.builder?.stat == DEAD && !player.respawn_pending)
		player.begin_respawn(player.builder)
	if(player.respawn_pending)
		player.update_respawn_player(student)
	else if(student && student.mob != player.builder)
		var/mob/previous = student.mob
		if(isnewplayer(previous))
			var/mob/dead/new_player/lobby = previous
			lobby.spawning = TRUE
			lobby.hide_title_screen()
		player.builder.PossessByPlayer(student.ckey)
		player.install_drone_actions()
		if(previous && isnewplayer(previous))
			qdel(previous)
	if(student)
		winset(student, "title_browser", "is-disabled=true;is-visible=false")
		winset(student, "status_bar", "is-visible=true")
