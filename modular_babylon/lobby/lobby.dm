var/global/list/lobby_config

/world
	name = "Babylon 13 Lobby"
	mob = /mob/lobby
	maxx = 1
	maxy = 1
	maxz = 1
	view = 0
	fps = 5
	sleep_offline = 1

/world/New()
	..()
	var/config_file = world.params["lobby-config"] || "babylon-lobby-config.json"
	if(!fexists(config_file))
		world.log << "Missing lobby-config JSON file."
		del(world)
		return
	lobby_config = json_decode(file2text(config_file))
	if(!lobby_config["secret"] || !findtext(lobby_config["api"], "http://127.0.0.1:"))
		world.log << "Lobby requires a loopback API and private lobby credential."
		del(world)

/world/Topic()
	return null

/client/New(TopicData)
	TopicData = null
	if(!ckey || findtext(ckey, "guest") == 1 || connection != "seeker")
		return null
	. = ..()
	spawn(1)
		if(src)
			mob:show_browser()

/mob/lobby
	var/busy = 0
	var/view_filter = "active"
	var/notice = ""
	var/list/cards = list()
	var/player_limit = 4

/mob/lobby/Login()
	..()
	loc = locate(1, 1, 1)
	spawn(50)
		while(client)
			if(!busy)
				show_browser()
			sleep(50)

/mob/lobby/proc/api(action, list/payload)
	var/list/query = list("secret" = lobby_config["secret"], "actor" = ckey, "action" = action, "payload" = json_encode(payload || list()))
	var/list/response = world.Export("[lobby_config["api"]]/api?[list2params(query)]")
	if(!response || !response["CONTENT"])
		return list("error" = "Supervisor unavailable. Please try again shortly.")
	var/list/result
	try
		result = json_decode(file2text(response["CONTENT"]))
	catch
		return list("error" = "Invalid supervisor response.")
	return result

/mob/lobby/proc/show_browser()
	var/list/result = api("list")
	if(!client)
		return
	var/content = {"<!doctype html><html><head><meta charset='utf-8'><meta http-equiv='X-UA-Compatible' content='IE=edge'><style>
body{background:#171d28;color:#e4eaf5;font:16px Segoe UI,Arial;padding:24px}a{color:#9ad9ff;margin-right:16px}section{background:#253044;padding:18px;margin:14px 0;border-radius:8px}small{color:#bbc8da}h1{margin:0 0 12px}.notice{color:#ffd890}p{line-height:1.5}
</style></head><body><h1>Babylon 13</h1><p>Build a station. Continue whenever you like.</p>"}
	content += "<p><a href='?src=\ref[src];action=create'>New game</a> <a href='?src=\ref[src];action=filter;filter=active'>Active worlds</a> <a href='?src=\ref[src];action=filter;filter=mine'>My worlds</a> <a href='?src=\ref[src];action=filter;filter=shared'>Shared with me</a> <a href='?src=\ref[src];action=filter;filter=all'>Browse all</a></p>"
	if(notice)
		content += "<p class='notice'>[html_encode(notice)]</p>"
	if(result["error"])
		content += "<p>[html_encode(result["error"])]</p>"
	else
		cards = list()
		for(var/list/card in result["worlds"])
			cards[card["id"]] = card
			if(view_filter == "active" && card["state"] == "stopped")
				continue
			if(view_filter == "mine" && card["owner"] != ckey)
				continue
			if(view_filter == "shared" && card["role"] != "member")
				continue
			var/id = card["id"]
			content += "<section><b>[html_encode(card["name"])]</b><p>[html_encode(card["description"])]</p><small>Owner: [html_encode(card["owner"])] | [html_encode(card["visibility"])] | [html_encode(card["state"])] | [card["players"]]/[card["max_players"]] players | Your role: [html_encode(card["role"])]<br>Last save: [html_encode(card["last_save"] || "None yet")]</small><p>"
			content += "<a href='?src=\ref[src];action=join;world=[id]'>Join</a>"
			if(card["role"] == "owner" || card["role"] == "admin")
				if(card["state"] == "stopped")
					content += "<a href='?src=\ref[src];action=edit;world=[id]'>Edit settings</a><a href='?src=\ref[src];action=member;world=[id]'>Members</a><a href='?src=\ref[src];action=rollback;world=[id]'>Saved checkpoints / rollback</a>"
				else
					content += "<a href='?src=\ref[src];action=stop;world=[id]'>Force stop / return players to lobby</a>"
			if(card["error"])
				content += "<p class='notice'>[html_encode(card["error"])]</p>"
			content += "</p></section>"
		var/list/limits = result["limits"]
		player_limit = limits["max_players_per_world"]
		content += "<small>Server limits: [limits["max_running_worlds"]] running worlds; [limits["max_players_per_world"]] players per world; [limits["max_worlds_per_player"]] worlds and [limits["max_running_worlds_per_player"]] running worlds per owner.</small>"
	content += "</body></html>"
	src << browse(content, "window=lobby.browser")

/mob/lobby/Topic(href, list/params)
	if(usr != src || !client || busy)
		return
	busy = 1
	try
		handle_action(params)
	catch
		notice = "Request failed. Please try again."
	busy = 0
	if(client)
		show_browser()

/mob/lobby/proc/handle_action(list/params)
	var/action = params["action"]
	notice = ""
	if(action == "filter")
		if(params["filter"] in list("active", "mine", "shared", "all"))
			view_filter = params["filter"]
		return
	var/id = params["world"]
	var/list/card = cards[id]
	if(action != "create" && !card)
		return
	var/list/payload = list("world" = id)
	if(action == "create" || action == "edit")
		var/name = input(src, "World name", "Babylon", card ? card["name"] : "My Babylon") as null|text
		if(isnull(name))
			return
		var/description = input(src, "Description", "Babylon", card ? card["description"] : "") as null|message
		if(isnull(description))
			return
		var/visibility = input(src, "Who can join? Private worlds require membership. Password worlds are listed and locked.", "Visibility", card ? card["visibility"] : "private") in list("private", "password", "public")
		if(!visibility)
			return
		payload["name"] = name
		payload["description"] = description
		payload["visibility"] = visibility
		if(visibility == "password")
			var/password = input(src, "World password (blank keeps the existing password when editing)", "Password") as null|password
			if(isnull(password))
				return
			if(password || action == "create")
				payload["password"] = password
		var/maximum = input(src, "Maximum players (limited by server configuration)", "Capacity", card ? card["max_players"] : player_limit) as null|num
		if(isnull(maximum))
			return
		payload["max_players"] = maximum
		var/list/result = api(action, payload)
		notice = result["error"] || "World settings saved."
		view_filter = "mine"
	else if(action == "join")
		if(card["visibility"] == "password" && card["role"] == "guest")
			var/password = input(src, "World password", "Join world") as null|password
			if(isnull(password))
				return
			payload["password"] = password
		var/deadline = world.time + 3600
		while(client && world.time < deadline)
			var/list/result = api("join", payload)
			if(result["error"])
				notice = result["error"]
				return
			if(result["address"])
				src << link(result["address"])
				notice = "Connection offered. If you cancelled it, click Join again."
				return
			notice = "Starting world and restoring checkpoint…"
			show_browser()
			sleep(20)
		notice = "Startup is taking longer than expected. Check the world status and try Join again."
	else if(action == "rollback")
		var/list/history = api("checkpoints", payload)
		if(history["error"])
			notice = history["error"]
			return
		var/list/options = list()
		for(var/list/point in history["checkpoints"])
			var/label = "[point["generation"]][point["current"] ? " (current)" : ""]"
			options[label] = point["generation"]
		if(!length(options))
			notice = "This world has no saved checkpoints yet."
			return
		var/choice = input(src, "Choose a saved checkpoint to restore. Newest checkpoints are listed first.", "Restore world") as null|anything in options
		if(!choice)
			return
		if(alert(src, "Restore [choice]? This rewinds the entire world for everyone. ALL NEWER CHECKPOINTS WILL BE PERMANENTLY DELETED. This cannot be undone.", "Confirm rollback", "Cancel", "Restore and delete newer") != "Restore and delete newer")
			return
		payload["generation"] = options[choice]
		payload["expected_latest"] = history["latest"]
		payload["confirm_delete_newer"] = 1
		var/list/result = api("rollback", payload)
		notice = result["error"] || "Checkpoint restored. Newer checkpoints deleted: [result["deleted"]]. Join to continue from this point."
	else if(action == "stop")
		if(alert(src, "Save and stop this world now? All remaining players will be returned to the lobby.", "Force stop", "Cancel", "Stop world") != "Stop world")
			return
		var/list/result = api("stop", payload)
		notice = result["error"] || "Stop requested. The final checkpoint is saved before shutdown."
	else if(action == "member")
		var/who = input(src, "BYOND account to grant or remove access", "Membership") as null|text
		if(!who)
			return
		var/role = input(src, "Membership change", "Membership") in list("member", "remove")
		if(!role)
			return
		payload["member"] = who
		payload["role"] = role
		var/list/result = api("member", payload)
		notice = result["error"] || "Membership updated."

/mob/lobby/verb/open_lobby()
	set name = "Open Babylon lobby"
	show_browser()
