/datum/babylon_save/proc/boot()
	try
		boot_impl()
	catch(var/exception/error)
		boot_error = "[error]"
		log_world("BABYLON STARTUP ERROR: [error]")

/datum/babylon_save/proc/boot_impl()
	while(Master.init_stage_completed < INITSTAGE_MAX)
		sleep(1 SECONDS)
	station_z = SSmapping.levels_by_trait(ZTRAIT_STATION)[1]
	if(!prepared)
		CRASH("Babylon restoration did not complete before simulation startup")
	// Pick the original engineering spawn before removing all ghost-role props.
	for(var/obj/effect/mob_spawn/ghost_role/drone/derelict/babylon/shell in world)
		if(shell.z != station_z)
			continue
		if(!respawn_turf && istype(get_area(shell), /area/ruin/space/bb13/engineering/sec_eng))
			respawn_turf = get_turf(shell)
		qdel(shell)
	if(!valid_respawn_tile(respawn_turf))
		respawn_turf = find_respawn_tile()
	if(!builder && !respawn_pending && respawn_turf)
		builder = new(respawn_turf)
	if(!builder && !respawn_pending)
		for(var/turf/open/floor/tile in world)
			if(tile.z == station_z && istype(get_area(tile), /area/ruin/space/bb13/engineering/sec_eng))
				var/blocked = FALSE
				for(var/atom/movable/obstacle in tile)
					if(obstacle.density)
						blocked = TRUE
				if(!blocked)
					builder = new(tile)
					break
	if(!builder && !respawn_pending)
		CRASH("No safe Babylon drone spawn was found")
	if(builder)
		if(!respawn_turf)
			respawn_turf = get_turf(builder)
		if(builder.stat == DEAD && !respawn_pending)
			begin_respawn(builder)
		else if(!respawn_pending)
			install_drone_actions()
	SSticker.start_immediately = TRUE
	for(var/obj/item/modular_computer/computer as anything in programs_to_resume)
		var/list/record = programs_to_resume[computer]
		for(var/filename in record["background_programs"])
			var/datum/computer_file/program/program = computer.find_file_by_name(filename)
			if(program)
				computer.open_program(null, program, FALSE)
		var/datum/computer_file/program/program = computer.find_file_by_name(record["active_program"])
		if(program)
			computer.open_program(null, program, FALSE)
	ready = TRUE
	next_autosave_at = world.time + 15 MINUTES
	while(TRUE)
		if(!draining)
			for(var/client/student in GLOB.clients)
				if(student.babylon_showcase_visitor)
					ensure_showcase_visitor(student)
				else
					ensure_player(student.ckey)
				if(!busy)
					student.babylon_check_afk(afk_timeout)
			for(var/player_key in player_sessions)
				var/datum/babylon_save/player = player_sessions[player_key]
				tick_player(player, GLOB.directory[player_key])
			tick_survival()
		if(length(GLOB.clients) && world.time >= next_autosave_at - 30 SECONDS && !autosave_countdown_active && !draining)
			next_autosave_at = world.time + 15 MINUTES + 30 SECONDS
			INVOKE_ASYNC(src, PROC_REF(countdown_autosave))
		sleep(1 SECONDS)

// Keep the possession/reconnect loop responsive during the warning period.
// The authenticated control API may allow an unoccupied drone for isolated tests.
/datum/babylon_save/proc/countdown_autosave(allow_unoccupied = FALSE)
	if(autosave_countdown_active)
		return
	autosave_countdown_active = TRUE
	autosave_notices = list()
	var/remaining = 30
	for(var/seconds_left in list(30, 10, 5, 1))
		if(remaining > seconds_left)
			sleep((remaining - seconds_left) SECONDS)
		if(!allow_unoccupied && !length(GLOB.clients))
			autosave_countdown_active = FALSE
			return
		var/message = seconds_left == 1 ? "Babylon autosave now." : "Babylon autosave in [seconds_left] seconds."
		autosave_notices += list(list("remaining" = seconds_left, "at" = world.time, "message" = message))
		to_chat(world, span_notice(message))
		remaining = seconds_left
	// Give the client a full second to receive/render "now" before freezing.
	sleep(1 SECONDS)
	if((allow_unoccupied || length(GLOB.clients)) && !busy)
		save_world()
	autosave_countdown_active = FALSE

SUBSYSTEM_DEF(babylon_builder)
	name = "Babylon Saves"
	init_stage = INITSTAGE_LAST
	ss_flags = SS_NO_FIRE

/datum/controller/subsystem/babylon_builder/Initialize()
	var/datum/babylon_save/session = GLOB.babylon_save
	session.owner_ckey = ckey(world.params["babylon-owner"])
	if(!session.owner_ckey)
		session.boot_error = "Set babylon-owner=<BYOND ckey> in world parameters. A world owner is required."
		return SS_INIT_FAILURE
	session.player_sessions[session.owner_ckey] = session
	var/raw_afk_timeout = world.params["babylon-afk-timeout"]
	if(!isnull(raw_afk_timeout))
		var/seconds = text2num(raw_afk_timeout)
		if(isnull(seconds) || seconds < 0 || seconds != round(seconds))
			session.boot_error = "babylon-afk-timeout must be a nonnegative integer in seconds (0 disables AFK kicks)."
			return SS_INIT_FAILURE
		session.afk_timeout = seconds SECONDS
	// Babylon owns this policy, including ghosts and administrators.
	CONFIG_SET(flag/kick_inactive, FALSE)
	session.station_z = SSmapping.levels_by_trait(ZTRAIT_STATION)[1]
	try
		session.restore_world()
		session.prepared = TRUE
	catch(var/exception/error)
		session.boot_error = "Restore failed: [error]"
		return SS_INIT_FAILURE
	INVOKE_ASYNC(GLOB.babylon_save, TYPE_PROC_REF(/datum/babylon_save, boot))
	return SS_INIT_SUCCESS
