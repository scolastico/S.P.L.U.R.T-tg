// Connection state, deliberately excluded from world checkpoints.
/datum/babylon_afk
	var/last_inactivity = 0
	var/warned = FALSE
	var/kick_pending = FALSE

/datum/babylon_afk/proc/update(idle, timeout)
	if(!timeout || idle < last_inactivity)
		warned = FALSE
		kick_pending = FALSE
	last_inactivity = idle
	if(!timeout)
		return null
	if(idle >= timeout)
		if(!kick_pending)
			kick_pending = TRUE
			return "kick"
		return null
	if(idle >= max(0, timeout - 60 SECONDS) && !warned)
		warned = TRUE
		return "warn"
	return null

/client
	var/datum/babylon_afk/babylon_afk

/client/proc/babylon_check_afk(timeout)
	if(!babylon_afk)
		babylon_afk = new
	switch(babylon_afk.update(inactivity, timeout))
		if("warn")
			to_chat(src, span_userdanger("You are inactive. Babylon will disconnect you in [DisplayTimeText(max(0, timeout - inactivity))]. Move or interact with the game to stay connected."))
		if("kick")
			INVOKE_ASYNC(src, PROC_REF(babylon_disconnect_afk), timeout)

/client/proc/babylon_disconnect_afk(timeout)
	to_chat(src, span_userdanger("Disconnecting for inactivity. Your body and equipment remain in this world. Rejoin through the Babylon lobby to continue."))
	// Flush the notice and allow last-second input to cancel the disconnect.
	sleep(1 SECONDS)
	if(!src)
		return
	if(!timeout || inactivity < timeout || GLOB.babylon_save.draining || GLOB.babylon_save.busy)
		babylon_afk.kick_pending = FALSE
		return
	log_access("BABYLON AFK: [key_name(src)] disconnected after [DisplayTimeText(timeout)].")
	qdel(src)
