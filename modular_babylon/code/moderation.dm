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

/datum/admin_help
	/// TRUE inside MessageNoRecipient, which also calls reply_to_admins_notification.
	var/babylon_in_message = FALSE

/proc/babylon_relay_ahelp(kind, ticket_id, player_ckey, player_key, message, sender)
	if(!world.params["babylon-world"] || !player_ckey)
		return
	var/list/query = list("action" = "ahelp", "kind" = kind, "ticket" = "[ticket_id]", "ckey" = player_ckey,
		"key" = player_key, "sender" = sender, "message" = copytext_char("[message]", 1, 2001))
	// The HTTP call blocks; never hold up the adminhelp itself.
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(babylon_supervisor_request), query)

/// A new ticket: relayed, then the player learns how many admins are online on Discord.
/datum/admin_help/proc/babylon_relay_new_ticket(message)
	set waitfor = FALSE
	var/list/response
	if(world.params["babylon-world"])
		response = babylon_supervisor_request(list("action" = "ahelp", "kind" = "new", "ticket" = "[id]", "ckey" = initiator_ckey,
			"key" = initiator?.key || initiator_ckey, "message" = copytext_char("[message]", 1, 2001)))
	if(!initiator)
		return
	var/online = text2num("[response?["admins_online"]]") || 0
	var/notice = "Created an adminhelp for you."
	if(online > 0)
		notice += " Currently [online] admin[online == 1 ? " is" : "s are"] online."
	to_chat(initiator, span_notice(notice), confidential = TRUE)

/// New tickets and every further adminhelp of the player while the ticket is open.
/datum/admin_help/MessageNoRecipient(msg, urgent = FALSE)
	var/is_new = !(src in GLOB.ahelp_tickets.active_tickets)
	babylon_in_message = TRUE
	. = ..()
	babylon_in_message = FALSE
	if(is_new)
		babylon_relay_new_ticket(msg)
	else
		babylon_relay_ahelp("message", id, initiator_ckey, initiator?.key || initiator_ckey, msg)

/// The player answering an admin, in game or on Discord (not the echo of their own ahelp).
/datum/admin_help/reply_to_admins_notification(message)
	. = ..()
	if(!babylon_in_message)
		babylon_relay_ahelp("reply", id, initiator_ckey, initiator?.key || initiator_ckey, message)

/// Upstream tells the player that no in-game admin is online and that the ahelp went to IRC
/// or Discord. In Babylon a world rarely has an admin, so babylon_relay_new_ticket() tells the
/// player how many are online on Discord instead. There is no TGS/IRC relay or webhook here.
/datum/admin_help/send_message_to_tgs(message, urgent = FALSE)
	var/present = 0
	for(var/client/admin in GLOB.admins)
		if(check_rights_for(admin, R_BAN) && !admin.is_afk())
			present++
	heard_by_no_admins = present <= 0
	log_admin_private("Ticket #[id]: [key_name(initiator)]: [name] - heard by [present] non-AFK admins who have +BAN.")
	if(urgent)
		to_chat(initiator, span_boldwarning("Notified admins to prioritize your ticket"), confidential = TRUE)

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

/// Closes a ticket from Discord. Upstream's Close() (and Skyrat's ticket counter) read usr,
/// which is null outside an admin's click, so this does the same state change without it.
/proc/babylon_discord_ahelp_close(ticket_id, sender)
	var/datum/admin_help/ticket = GLOB.ahelp_tickets.TicketByID(text2num("[ticket_id]"))
	if(!ticket)
		return list("ok" = FALSE, "result" = "That ticket does not exist in this world")
	if(ticket.state != AHELP_ACTIVE)
		return list("ok" = FALSE, "result" = "That ticket is already closed")
	var/closer = "[istext(sender) && length(sender) ? sender : "Discord"] (Discord)"
	ticket.RemoveActive()
	ticket.state = AHELP_CLOSED
	ticket.previously_closed = TRUE
	GLOB.ahelp_tickets.ListInsert(ticket)
	ticket.AddInteraction("<font color='red'>Closed by [closer].</font>", player_message = "<font color='red'>Ticket closed!</font>")
	message_admins("Ticket #[ticket.id] closed by [closer].")
	log_admin_private("Ticket #[ticket.id] closed by [closer].")
	if(ticket.initiator)
		to_chat(ticket.initiator, span_notice("Your adminhelp has been closed by an admin."), confidential = TRUE)
	return list("ok" = TRUE, "result" = "Closed")
