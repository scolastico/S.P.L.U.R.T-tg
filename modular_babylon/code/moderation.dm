// Babylon moderation: lobby admins are game admins, ahelps reach Discord, no mentors.
// Overrides only; see modular_babylon/UPSTREAM_HOOKS.md.

// --- Lobby admins (BABYLON_ADMINS) are full game admins in every world they join ---------

/// Called from babylon_admit() with the supervisor's authenticated answer, before the client
/// is registered: /client/New() then associates the datum like any other admin's.
/proc/babylon_grant_admin(target_ckey)
	if(!target_ckey || GLOB.admin_datums[target_ckey] || GLOB.deadmins[target_ckey])
		return // Already an admin here, or deadminned themselves this round.
	var/datum/admin_rank/rank = new("Babylon Admin", RANK_SOURCE_LOCAL, R_EVERYTHING, R_DBRANKS, R_EVERYTHING)
	new /datum/admins(list(rank), target_ckey, TRUE, TRUE)
	log_admin("[target_ckey] joined as a Babylon lobby admin and was made a game admin.")

// --- No mentors ----------------------------------------------------------------------

/datum/player_rank_controller/mentor/add_player(ckey)
	return

/// Upstream turns every admin into a mentor on connect.
/client/mentor_datum_set()
	return

/client/is_mentor(admin_bypass = TRUE)
	return FALSE

/client/mentor_client_procs(href_list)
	return FALSE

/datum/admin_help/convert_to_mentorhelp(key_name)
	return FALSE

/client/New(TopicData)
	. = ..()
	if(src)
		remove_verb(src, list(/client/verb/mentorhelp, /client/verb/mentorwho))

/client/__gvb_mentorhelp(list/structured_args)
	return

/client/__gvb_mentorwho(list/structured_args)
	return

// --- Adminhelps are relayed to Discord through the supervisor ------------------------

/// TRUE while a Discord reply is being delivered, so it is not relayed back as an in-game answer.
GLOBAL_VAR_INIT(babylon_relaying_reply, FALSE)

/proc/babylon_relay_ahelp(kind, ticket_id, player_ckey, player_key, message, sender)
	if(!world.params["babylon-world"] || !player_ckey)
		return
	var/list/query = list("action" = "ahelp", "kind" = kind, "ticket" = "[ticket_id]", "ckey" = player_ckey,
		"key" = player_key, "sender" = sender, "message" = copytext_char("[message]", 1, 2001))
	// The HTTP call blocks; never hold up the adminhelp itself.
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(babylon_supervisor_request), query)

/// New tickets and every further adminhelp of the player while the ticket is open.
/datum/admin_help/MessageNoRecipient(msg, urgent = FALSE)
	var/is_new = !(src in GLOB.ahelp_tickets.active_tickets)
	. = ..()
	babylon_relay_ahelp(is_new ? "new" : "message", id, initiator_ckey, initiator_key_name, msg)

/// The player answering an admin, in game or on Discord.
/datum/admin_help/reply_to_admins_notification(message)
	. = ..()
	babylon_relay_ahelp("reply", id, initiator_ckey, initiator_key_name, message)

/// An in-game admin's answer, so Discord sees the whole conversation.
/client/receive_ahelp(reply_to, message, span_class = "adminsay")
	. = ..()
	if(!GLOB.babylon_relaying_reply)
		babylon_relay_ahelp("admin", current_ticket?.id, ckey, key, message, usr?.key || "An admin")

/// A staff reply from Discord, delivered through the game's external admin PM.
/proc/babylon_discord_ahelp_reply(target, sender, message)
	if(!istext(target) || !istext(message) || !length(trim(message)))
		return list("ok" = FALSE, "result" = "Invalid reply")
	if(findtext(trim(LOWER_TEXT(message)), "ticket ") == 1)
		return list("ok" = FALSE, "result" = "Replies starting with 'ticket ' are ticket commands")
	GLOB.babylon_relaying_reply = TRUE
	var/result = TgsPm(target, message, istext(sender) && length(sender) ? "[sender] (Discord)" : "Discord")
	GLOB.babylon_relaying_reply = FALSE
	if(result == "Error: No client")
		result = "The player is no longer in this world"
	return list("ok" = result == "Message Successful", "result" = result)
