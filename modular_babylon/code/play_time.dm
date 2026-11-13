// Play time: how long the world and each of its players have been played. Both are saved in
// the world's checkpoint (state.json), so restoring an older checkpoint restores their play
// time too. Shown in the Status tab and by the continuity watchdog server (examine and the
// printed core log).

/// Seconds of real time one world tick may add at most. The loop runs every second; a longer
/// gap (a save pausing the world, a stalled server) is not counted as play.
#define BABYLON_PLAY_TIME_MAX_STEP (10 SECONDS)

/datum/babylon_save
	/// Deciseconds played. The world's own record: time with at least one player in it.
	/// A player's record (in player_sessions): time connected to this world as a player.
	var/play_time = 0
	/// REALTIMEOFDAY of the last counting step, or null before the first.
	var/play_time_counted_at

/datum/babylon_save/tick_world()
	. = ..()
	count_play_time()

/datum/babylon_save/proc/count_play_time()
	var/now = REALTIMEOFDAY
	var/step = isnull(play_time_counted_at) ? 0 : clamp(now - play_time_counted_at, 0, BABYLON_PLAY_TIME_MAX_STEP)
	play_time_counted_at = now
	if(!step || draining || !ready)
		return
	var/anyone = FALSE
	for(var/player_key in player_sessions)
		var/client/student = babylon_ready_client(GLOB.directory[player_key])
		// Visitors and spectating admins watch; they are not playing this world.
		if(!student || student.babylon_showcase_visitor || student.babylon_admin_spectator)
			continue
		var/datum/babylon_save/player = player_sessions[player_key]
		player.play_time += step
		anyone = TRUE
	if(anyone)
		play_time += step

/// "3h 07m", "45m" or "under a minute".
/proc/babylon_play_time_text(deciseconds)
	var/minutes = round(max(0, deciseconds) / (1 MINUTES))
	if(minutes < 1)
		return "under a minute"
	var/hours = round(minutes / 60)
	minutes %= 60
	return hours ? "[hours]h [minutes < 10 ? "0" : ""][minutes]m" : "[minutes]m"

/// The player's own play time on this world, or null for someone without a session.
/proc/babylon_player_play_time(ckey)
	var/datum/babylon_save/player = GLOB.babylon_save?.player_sessions[ckey]
	return player?.play_time

/mob/get_status_tab_items()
	. = ..()
	if(!world.params["babylon-world"] || !GLOB.babylon_save)
		return
	. += "World play time: [babylon_play_time_text(GLOB.babylon_save.play_time)]"
	var/own = babylon_player_play_time(ckey)
	if(!isnull(own))
		. += "Your play time: [babylon_play_time_text(own)]"

/// The watchdog's view: every self seated in this world and how long it has been awake.
/proc/babylon_play_time_report(limit = 10)
	var/list/sessions = GLOB.babylon_save?.player_sessions
	if(!length(sessions))
		return list()
	var/list/times = list()
	for(var/player_key in sessions)
		var/datum/babylon_save/player = sessions[player_key]
		times[player_key] = player.play_time
	sortTim(times, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
	var/list/lines = list()
	for(var/player_key in times)
		if(length(lines) >= limit)
			lines += " ... and [length(times) - limit] more"
			break
		// Padded to a column; the core log is a monospaced code block.
		var/padding = max(1, 28 - length(player_key))
		lines += " [player_key][copytext("                            ", 1, padding + 1)] [babylon_play_time_text(times[player_key])]"
	return lines

#undef BABYLON_PLAY_TIME_MAX_STEP
