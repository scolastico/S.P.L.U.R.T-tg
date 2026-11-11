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
	var/browser_initialized = 0
	var/request_revision = 0
	var/last_browser_content = ""

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

/mob/lobby/proc/page_start()
	return "<!doctype html><html><head><meta charset='utf-8'><meta http-equiv='X-UA-Compatible' content='IE=edge'><style>[file2text('modular_babylon/lobby/style.css')]</style><script>[file2text('modular_babylon/lobby/loading.js')]</script></head><body>"

/mob/lobby/proc/loading_panel(world_name, stage)
	return "<div class='loading-shell'><section class='loading' role='status' aria-live='polite' aria-busy='true'><div class='spinner'></div><div class='brand'>BABYLON // WORLD MANAGEMENT</div><h1 id='loading-world'>[html_encode(world_name)]</h1><p id='loading-stage'>[html_encode(stage)]</p><small>Keep this client open while your request completes.</small></section></div>"

/mob/lobby/proc/show_loading(world_name, stage)
	if(client)
		src << output(list2params(list(world_name, stage)), "lobby.browser:showLobbyLoading")

/mob/lobby/proc/operation_api(action, list/payload, world_name, stage)
	show_loading(world_name, stage)
	// Flush the loading panel before synchronous work starts.
	sleep(1)
	return api(action, payload)

/mob/lobby/proc/show_browser(complete = 0)
	var/revision = request_revision
	var/list/result = api("list")
	// An old poll must not overwrite a click, even if its action has finished.
	if(!client || busy || revision != request_revision)
		return
	var/content = "<div class='brand'>BABYLON 13</div><div class='top'><h1>Your station, your next chapter.</h1><a class='button primary' data-stage='Waiting for world settings...' onclick='return beginAction(this)' href='?src=\ref[src];action=create'>+ New game</a></div><nav class='tabs' aria-label='World categories'>"
	var/list/tabs = list("active" = "Active worlds", "mine" = "My worlds", "shared" = "Shared with me", "all" = "Browse worlds")
	for(var/tab in tabs)
		var/selected = view_filter == tab
		content += "<a class='[selected ? "active" : ""]' aria-current='[selected ? "page" : "false"]' data-stage='Loading worlds...' onclick='return beginAction(this)' href='?src=\ref[src];action=filter;filter=[tab]'>[tabs[tab]]</a>"
	content += "</nav><h2 class='page-heading'>[tabs[view_filter]]</h2>"
	var/list/descriptions = list("active" = "Worlds currently running, starting or stopping. Join an online world to continue building.", "mine" = "Worlds you own. Start an offline world, change its settings, or restore a saved checkpoint.", "shared" = "Worlds where you have membership. You can start these even when the owner is away.", "all" = "Worlds available to your account. Guests can join online worlds; owners, members and admins can start offline worlds.")
	content += "<p class='muted'>[descriptions[view_filter]]</p>"
	if(result["admin"])
		content += "<p><span class='badge'>Server administrator</span> <small>Your account can see private worlds and bypass their admission restrictions.</small></p>"
	if(notice)
		content += "<p class='notice' role='status'>[html_encode(notice)]</p>"
	if(result["error"])
		content += "<p class='notice'>[html_encode(result["error"])]</p>"
	else
		cards = list()
		var/rendered = ""
		var/visible = 0
		var/list/states = list("running" = "Online", "stopped" = "Offline", "starting" = "Starting", "stopping" = "Stopping", "error" = "Needs attention")
		for(var/list/card in result["worlds"])
			cards[card["id"]] = card
			if(view_filter == "active" && card["state"] == "stopped")
				continue
			if(view_filter == "mine" && card["owner"] != ckey)
				continue
			if(view_filter == "shared" && card["role"] != "member")
				continue
			visible++
			var/id = card["id"]
			var/world_name = html_encode(card["name"])
			rendered += "<section class='card'><div class='card-head'><h2>[world_name]</h2><span class='badge [html_encode(card["state"])]'>[states[card["state"]] || "Unknown"]</span></div><p>[html_encode(card["description"] || "A Babylon station waiting to be rebuilt.")]</p><div class='meta'>Owner: [html_encode(card["owner"])] &nbsp; | &nbsp; Access: [html_encode(card["visibility"])] &nbsp; | &nbsp; [card["players"]]/[card["max_players"]] players online<br>Your role: <b>[html_encode(card["role"])]</b> &nbsp; | &nbsp; Last active: [html_encode(card["last_active"] || "Unknown")]<br>Last save: [html_encode(card["last_save"] || "None yet")]</div><div class='actions'>"
			if(card["role"] != "guest" || card["state"] != "stopped")
				rendered += "<a class='button primary' data-world='[world_name]' data-stage='Preparing your connection...' onclick='return beginAction(this)' href='?src=\ref[src];action=join;world=[id]'>[card["state"] == "stopped" ? "Start and join" : "Join world"]</a>"
			else
				rendered += "<small>An owner, member or admin must start this world.</small>"
			if(card["role"] == "owner" || card["role"] == "admin")
				if(card["state"] == "stopped")
					rendered += "<a class='button' data-world='[world_name]' data-stage='Waiting for world settings...' onclick='return beginAction(this)' href='?src=\ref[src];action=edit;world=[id]'>Edit settings</a><a class='button' data-world='[world_name]' data-stage='Waiting for membership details...' onclick='return beginAction(this)' href='?src=\ref[src];action=member;world=[id]'>Members</a><a class='button' data-world='[world_name]' data-stage='Loading saved checkpoints...' onclick='return beginAction(this)' href='?src=\ref[src];action=rollback;world=[id]'>Saved checkpoints / rollback</a>"
					rendered += "<a class='button danger' data-world='[world_name]' data-stage='Waiting for deletion confirmation...' onclick='return beginAction(this)' href='?src=\ref[src];action=delete;world=[id]'>Delete world</a>"
				else
					rendered += "<a class='button danger' data-world='[world_name]' data-stage='Waiting for shutdown confirmation...' onclick='return beginAction(this)' href='?src=\ref[src];action=stop;world=[id]'>Save and force stop</a>"
			if(card["error"])
				rendered += "<p class='notice'>[html_encode(card["error"])]</p>"
			rendered += "</div></section>"
		content += "<div class='count'>Showing [visible] world[visible == 1 ? "" : "s"]</div>"
		if(!visible)
			var/list/empty = list("active" = "No worlds are active. Open My worlds or Browse worlds to find a station to start.", "mine" = "You have no worlds yet. Choose New game to create your first station.", "shared" = "No worlds have been shared with your account yet. Ask an owner to add you as a member.", "all" = "No worlds are available. Create one with New game, or ask an owner for membership.")
			content += "<div class='empty'>[empty[view_filter]]</div>"
		else
			content += rendered
		var/list/limits = result["limits"]
		player_limit = limits["max_players_per_world"]
		var/expiry = result["delete_unused_worlds_after_days"]
		var/expiry_text = expiry ? "Unused stopped worlds are deleted after [expiry] days." : "Automatic world expiry is disabled."
		content += "<footer class='footer'>Server limits: [limits["max_running_worlds"]] running worlds; [limits["max_players_per_world"]] players per world; [limits["max_worlds_per_player"]] worlds and [limits["max_running_worlds_per_player"]] running worlds per owner.<br>Private worlds require membership. Your station continues from its last successful checkpoint.<br>[expiry_text]</footer>"
	if(!browser_initialized)
		var/initial = json_encode(json_encode(list("html" = content, "view" = view_filter, "revision" = revision, "complete" = 1)))
		var/shell = "[page_start()]<main id='browser-content'></main><div id='action-loading' style='display:none'>[loading_panel("Your world", "Working...")]</div><script>renderLobby([initial]);</script></body></html>"
		src << browse(shell, "window=lobby.browser")
		browser_initialized = 1
	else if(complete || content != last_browser_content)
		src << output(list2params(list(json_encode(list("html" = content, "view" = view_filter, "revision" = revision, "complete" = complete)))), "lobby.browser:renderLobby")
	last_browser_content = content

/mob/lobby/Topic(href, list/params)
	if(usr != src || !client || busy)
		return
	busy = 1
	request_revision++
	if(params["action"] == "join")
		var/list/card = cards[params["world"]]
		show_loading(card ? card["name"] : "Your world", "Contacting the supervisor and preparing your connection...")
		sleep(1)
	try
		handle_action(params)
	catch
		notice = "Request failed. Please try again."
	busy = 0
	if(client)
		show_browser(1)

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
		var/list/result = operation_api(action, payload, name, action == "create" ? "Creating your world..." : "Saving world settings...")
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
			show_loading(card["name"], "Starting world and restoring its checkpoint...")
			sleep(20)
		notice = "Startup is taking longer than expected. Check the world status and try Join again."
	else if(action == "rollback")
		var/list/history = operation_api("checkpoints", payload, card["name"], "Loading saved checkpoints...")
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
		var/list/result = operation_api("rollback", payload, card["name"], "Restoring checkpoint and removing newer saves...")
		notice = result["error"] || "Checkpoint restored. Newer checkpoints deleted: [result["deleted"]]. Join to continue from this point."
	else if(action == "delete")
		if(card["role"] != "owner" && card["role"] != "admin")
			return
		if(alert(src, "Permanently delete [card["name"]]? This deletes the entire world and ALL saved checkpoints for everyone. This cannot be undone.", "Delete world", "Cancel", "Delete permanently") != "Delete permanently")
			return
		payload["confirm_delete"] = 1
		var/list/result = operation_api("delete", payload, card["name"], "Deleting world and all saved checkpoints...")
		notice = result["error"] || "World permanently deleted."
	else if(action == "stop")
		if(alert(src, "Save and stop this world now? All remaining players will be returned to the lobby.", "Force stop", "Cancel", "Stop world") != "Stop world")
			return
		var/list/result = operation_api("stop", payload, card["name"], "Saving the final checkpoint and stopping the world...")
		if(result["error"])
			notice = result["error"]
			return
		var/deadline = world.time + 1800
		while(client && world.time < deadline)
			var/list/status = api("list")
			if(status["error"])
				notice = status["error"]
				return
			var/list/current
			for(var/list/item in status["worlds"])
				if(item["id"] == id)
					current = item
					break
			if(!current || current["state"] == "stopped")
				notice = "World saved and stopped."
				return
			if(current["error"] || current["state"] == "error")
				notice = current["error"] || "The world could not stop. Check its status before trying again."
				return
			sleep(10)
		notice = "Shutdown is still in progress. Check the world status before joining again."
	else if(action == "member")
		var/who = input(src, "BYOND account to grant or remove access", "Membership") as null|text
		if(!who)
			return
		var/role = input(src, "Membership change", "Membership") in list("member", "remove")
		if(!role)
			return
		payload["member"] = who
		payload["role"] = role
		var/list/result = operation_api("member", payload, card["name"], "Updating world membership...")
		notice = result["error"] || "Membership updated."

/mob/lobby/verb/open_lobby()
	set name = "Open Babylon lobby"
	show_browser(1)
