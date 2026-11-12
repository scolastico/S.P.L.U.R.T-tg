/*
 * Babylon has no storyteller yet: no round-start vote, no event rolls and no antagonists.
 *
 * SPLURT starts a storyteller vote when DEFAULT_STORYTELLER is unset (Babylon's own config
 * does not set it), and other code expects a storyteller to exist. So every Babylon world
 * runs the inert storyteller below instead of none at all. A Babylon-specific storyteller
 * replaces it later; the overrides here keep any other one from being picked.
 */

/datum/storyteller/babylon
	name = "Babylon"
	desc = "Babylon's storyteller. It does not run events or antagonists yet."
	welcome_text = "The station is quiet."
	disable_distribution = TRUE
	guarantees_roundstart_crewset = FALSE
	antag_divisor = 0
	votable = FALSE

/datum/vote/storyteller/can_be_initiated(mob/by_who, forced = FALSE)
	..()
	return "Babylon has no storyteller vote."

/// Whatever is requested (config, vote, admin), Babylon only runs its own storyteller.
/datum/controller/subsystem/gamemode/set_storyteller(passed_type, forced, force_ckey)
	if(passed_type != /datum/storyteller/babylon)
		log_dynamic("Babylon ignored a request for storyteller [passed_type].")
	return ..(/datum/storyteller/babylon, forced, force_ckey)

/// Selects the Babylon storyteller silently, without the vote results or a chat and Discord announcement.
/datum/controller/subsystem/gamemode/init_storyteller()
	if(storyteller?.type != /datum/storyteller/babylon)
		set_storyteller(/datum/storyteller/babylon)

/// tgstation's own random events stay off too, even with ALLOW_RANDOM_EVENTS set or toggled by an admin.
/datum/controller/subsystem/events/spawnEvent(datum/round_event_control/excluded_event)
	return
