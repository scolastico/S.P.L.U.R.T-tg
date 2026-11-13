// World owners (and server admins) manage who may play in their world from the Babylon tab:
// members, kicks and world bans. Bans are stored by the supervisor and apply to this world only.

/client
	/// The player's role from the supervisor's admission answer: owner, admin, member or guest.
	var/babylon_world_role

/client/proc/babylon_world_manager()
	return world.params["babylon-world"] && (babylon_world_role in list("owner", "admin"))

/client
	/// TRUE once this world announced the player's arrival, so only they are announced leaving.
	var/babylon_announced = FALSE

/// Join and leave notices for everyone in the world (stealthed admins are not announced).
/client/proc/babylon_announce(message)
	if(!world.params["babylon-world"] || holder?.fakekey)
		return FALSE
	to_chat(world, span_notice(message))
	return TRUE

/client/Destroy()
	if(babylon_announced && !GLOB.babylon_save.draining)
		babylon_announce("[html_encode(key)] left the world.")
	return ..()

/client/New(TopicData)
	. = ..()
	// A rejected admission returns before the client is registered.
	if(src && (src in GLOB.clients))
		babylon_announced = babylon_announce(babylon_showcase_visitor ? "[html_encode(key)] is visiting the world." : (babylon_admin_spectator ? "[html_encode(key)] is spectating the world." : "[html_encode(key)] joined the world."))
	if(src && babylon_world_manager())
		add_verb(src, list(/client/proc/babylon_add_member, /client/proc/babylon_remove_member,
			/client/proc/babylon_kick_player, /client/proc/babylon_ban_player, /client/proc/babylon_unban_player))

/// Asks the supervisor; tells the player what went wrong and returns null on failure.
/client/proc/babylon_world_request(op, target, reason)
	var/list/result = babylon_supervisor_request(list("action" = "world_manage", "actor" = ckey, "op" = op, "target" = target, "reason" = reason))
	if(!result)
		to_chat(src, span_warning("The server did not answer. Try again."))
		return null
	if(!result["ok"])
		to_chat(src, span_warning(html_encode(result["error"] || "That did not work.")))
		return null
	return result

/// Other players in this world that this client may act on (the owner and admins are protected).
/client/proc/babylon_kickable_players()
	var/list/players = list()
	for(var/client/player as anything in GLOB.clients)
		if(player == src || (player.babylon_world_role in list("owner", "admin")))
			continue
		players[player.key] = player
	return players

/proc/babylon_remove_from_world(client/player, message)
	if(!player)
		return
	to_chat(player, span_userdanger(message))
	var/lobby = world.params["babylon-lobby"]
	if(lobby)
		player << link(lobby)
	// Let the notice and the lobby link reach the player before disconnecting.
	spawn(2 SECONDS)
		if(player)
			qdel(player)

/client/proc/babylon_add_member()
	set name = "Add member"
	set category = "Babylon"
	if(!babylon_world_manager())
		return
	var/target = tgui_input_text(mob, "BYOND account to add. Members can build and start this world, even when you are away.", "Add member", max_length = 30)
	if(!target || !babylon_world_request("member_add", target))
		return
	to_chat(src, span_notice("[html_encode(target)] is now a member of this world."))

/client/proc/babylon_remove_member()
	set name = "Remove member"
	set category = "Babylon"
	if(!babylon_world_manager())
		return
	var/list/listing = babylon_world_request("list")
	if(!listing)
		return
	if(!length(listing["members"]))
		to_chat(src, span_notice("This world has no members."))
		return
	var/target = tgui_input_list(mob, "Remove a member. They keep playing if the world is public, but can no longer start it.", "Remove member", listing["members"])
	if(!target || !babylon_world_request("member_remove", target))
		return
	to_chat(src, span_notice("[html_encode(target)] is no longer a member of this world."))

/client/proc/babylon_kick_player()
	set name = "Kick player"
	set category = "Babylon"
	if(!babylon_world_manager())
		return
	var/list/players = babylon_kickable_players()
	if(!length(players))
		to_chat(src, span_notice("There is nobody else to kick."))
		return
	var/target = tgui_input_list(mob, "Send a player back to the lobby. They can join again; ban them to keep them out.", "Kick player", players)
	var/client/player = players[target]
	if(!player || tgui_alert(mob, "Kick [target] from this world?", "Kick player", list("Kick", "Cancel")) != "Kick")
		return
	log_admin("BABYLON WORLD: [key_name(src)] kicked [key_name(player)].")
	babylon_remove_from_world(player, "You were kicked from this world by [key]. You can join again from the lobby.")
	to_chat(src, span_notice("[html_encode(target)] was kicked."))

/client/proc/babylon_ban_player()
	set name = "Ban player"
	set category = "Babylon"
	if(!babylon_world_manager())
		return
	var/list/players = babylon_kickable_players()
	var/other = "Someone not in this world..."
	var/target = tgui_input_list(mob, "Ban a player from this world only. They are kicked and can no longer join it.", "Ban player", players + other)
	if(!target)
		return
	if(target == other)
		target = tgui_input_text(mob, "BYOND account to ban from this world.", "Ban player", max_length = 30)
		if(!target)
			return
	var/reason = tgui_input_text(mob, "Reason (shown to them and in the ban list).", "Ban player", max_length = 200)
	if(isnull(reason) || !babylon_world_request("ban", target, reason))
		return
	log_admin("BABYLON WORLD: [key_name(src)] banned [target] from this world: [reason]")
	var/client/player = GLOB.directory[ckey(target)]
	if(player)
		babylon_remove_from_world(player, "You were banned from this world by [key][reason ? ": [reason]" : ""].")
	to_chat(src, span_notice("[html_encode(target)] is banned from this world."))

/client/proc/babylon_unban_player()
	set name = "Unban player"
	set category = "Babylon"
	if(!babylon_world_manager())
		return
	var/list/listing = babylon_world_request("list")
	if(!listing)
		return
	var/list/bans = list()
	for(var/list/ban in listing["bans"])
		bans["[ban["ckey"]] ([ban["reason"]])"] = ban["ckey"]
	if(!length(bans))
		to_chat(src, span_notice("Nobody is banned from this world."))
		return
	var/choice = tgui_input_list(mob, "Lift a ban from this world.", "Unban player", bans)
	if(!choice || !babylon_world_request("unban", bans[choice]))
		return
	log_admin("BABYLON WORLD: [key_name(src)] unbanned [bans[choice]] from this world.")
	to_chat(src, span_notice("[html_encode(bans[choice])] can join this world again."))
