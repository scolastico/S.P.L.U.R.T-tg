// Server administrators can enter a world as a spectator: an ordinary admin ghost (invisible to
// players) instead of a drone, so checking on a world leaves no empty admin drone behind. Only
// the supervisor's admission answer grants it, for admin tickets that asked to spectate.

/client
	/// Admitted as a spectator: no drone is created or possessed for this client.
	var/babylon_admin_spectator = FALSE

/// Turns the client's new-player mob into a spectator ghost once, after it finished connecting.
/// Later the admin may possess or aghost as they like; the world never takes them over.
/datum/babylon_save/proc/ensure_admin_spectator(client/student)
	if(!student?.babylon_admin_spectator || !student.fully_created || !isnewplayer(student.mob))
		return
	var/mob/dead/new_player/menu = student.mob
	menu.spawning = TRUE
	menu.hide_title_screen()
	var/mob/dead/observer/babylon_spectator/spectator = new(respawn_turf)
	spectator.name = student.key
	spectator.real_name = student.key
	spectator.key = student.key
	winset(student, "title_browser", "is-disabled=true;is-visible=false")
	winset(student, "status_bar", "is-visible=true")
	to_chat(student, span_notice("Spectating as an admin ghost: players cannot see you and no drone was created for you. To build, return to the lobby and join the world normally."))
	qdel(menu)

/mob/dead/observer/babylon_spectator
	can_reenter_corpse = FALSE

/// Leaving the world (or the ghost) deletes it, so spectating leaves nothing behind.
/mob/dead/observer/babylon_spectator/Logout()
	. = ..()
	spawn(0)
		if(src && !client)
			key = null
			qdel(src)
