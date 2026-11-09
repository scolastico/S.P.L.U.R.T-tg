/mob/living/basic/drone/babylon/verb/save_babylon()
	set name = "Save Babylon"
	set category = "Babylon"
	if(ckey == GLOB.babylon_save.owner_ckey)
		GLOB.babylon_save.save_world()

/mob/living/basic/drone/babylon/verb/save_stop_babylon()
	set name = "Save and Stop Babylon"
	set category = "Babylon"
	if(ckey != GLOB.babylon_save.owner_ckey)
		return
	var/list/result = GLOB.babylon_save.save_world()
	if(result["ok"])
		world.Del()

/datum/world_topic/babylon_control
	keyword = "babylon_control"
	log = FALSE
	require_comms_key = TRUE

/datum/world_topic/babylon_control/Run(list/input)
	var/datum/babylon_save/session = GLOB.babylon_save
#ifdef BABYLON_TESTING
	if(input["action"] in list("inspect", "find", "call", "set_var", "spawn", "delete"))
		if(!session.ready)
			return list("error" = "Babylon is not ready")
		return GLOB.babylon_debug.admin_request(input["action"], json_decode(input["payload"] || "{}"))
#endif
	switch(input["action"])
		if("status")
			var/client/student = GLOB.directory[GLOB.babylon_save.owner_ckey]
			return list("ready" = session.ready, "error" = session.boot_error, "map" = SSmapping.current_map?.map_name, "last_save" = session.last_save, "busy" = session.busy, "paused" = !Master.processing, "migration_notes" = session.migration_notes, "station_z" = session.station_z, "world_size" = list(world.maxx, world.maxy, world.maxz), "connected" = !!student, "controlling_drone" = student && student.mob == session.builder, "lobby_visible" = student ? winget(student, "title_browser", "is-visible") : null, "builder" = session.builder ? list("x" = session.builder.x, "y" = session.builder.y, "z" = session.builder.z, "health" = session.builder.health) : null)
		if("save")
			return session.save_world()
		if("stop")
			var/list/result = session.save_world()
			if(result["ok"])
				addtimer(CALLBACK(session, TYPE_PROC_REF(/datum/babylon_save, stop_world)), 1 SECONDS)
			return result
	return list("error" = "Unknown action")

/datum/babylon_save/proc/stop_world()
	world.Del()
