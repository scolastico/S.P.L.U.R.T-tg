var/global/list/lobby_config

/world
	name = "Babylon 13 Lobby"
	mob = /mob/lobby
	maxx = 1
	maxy = 1
	maxz = 1
	view = 0
	fps = 5
	// A sleeping world stops refreshing its hub entry, so an empty lobby would
	// drop off the hub list until someone joined. Keep it awake.
	sleep_offline = 0
	// BYOND only registers with the hub set at compile time, so hub is fixed here.
	// The world announces itself while it starts, before New() can read the lobby
	// config. Announced with a wrong password, the hub treats it as unregistered and
	// lists it only while someone is connected; a later password change is not
	// re-announced until a player joins. So the lobby starts invisible with
	// upstream's (public) password, and New() sets the configured password before
	// making it visible (BABYLON_HUB_LISTED). Unlisted lobbies stay invisible.
	hub = "Exadv1.spacestation13"
	hub_password = "kMZy3U5jJHSiBQjr"
	visibility = 0

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
		return
	if(lobby_config["name"])
		name = lobby_config["name"]
	world.log << "Lobby started as [name] (hub listing [lobby_config["hub_listed"] ? "on" : "off"])"
	// Only the lobby is listed; child worlds run with -invisible and need a lobby ticket anyway.
	if(lobby_config["hub_listed"])
		if(lobby_config["hub"] && lobby_config["hub"] != hub)
			hub = lobby_config["hub"]
		hub_password = lobby_config["hub_password"]
		visibility = 1
	else
		hub_password = "SORRYNOPASSWORD"
		visibility = 0
	spawn(0)
		while(1)
			// A runtime error must not stop the hub status for the rest of the run.
			try
				update_hub_status()
			catch(var/exception/error)
				world.log << "Updating the hub status failed: [error] ([error.file]:[error.line])"
			sleep(300)

// The hub only counts clients connected to the lobby itself, so the status text
// carries the cluster-wide total including everyone playing in a child world.
/world/proc/update_hub_status()
	var/in_lobby = 0
	for(var/mob/lobby/M)
		if(M.client)
			in_lobby++
	var/in_worlds = 0
	var/running = 0
	var/admin_worlds = 0
	var/list/query = list("secret" = lobby_config["secret"], "action" = "summary")
	var/list/response = Export("[lobby_config["api"]]/api?[list2params(query)]")
	if(response && response["CONTENT"])
		try
			var/list/summary = json_decode(file2text(response["CONTENT"]))
			if(summary && summary["ok"])
				in_worlds = text2num("[summary["players"]]") || 0
				running = text2num("[summary["running_worlds"]]") || 0
				admin_worlds = text2num("[summary["admin_worlds"]]") || 0
		catch
			in_worlds = 0
	status = render_hub_status(in_lobby, in_worlds, running, admin_worlds)
	game_state = 0

/// Fills the BABYLON_HUB_STATUS template (see CLUSTER.md for the placeholders).
/// Admin worlds run outside the limit but are listed as ordinary running worlds here.
/world/proc/render_hub_status(in_lobby, in_worlds, running, admin_worlds = 0)
	var/all_running = running + admin_worlds
	var/text = lobby_config["hub_status"] || "<b>{name}</b>"
	var/list/values = list(
		"{name}" = html_encode(name),
		"{players}" = "[in_lobby + in_worlds]",
		"{lobby_players}" = "[in_lobby]",
		"{world_players}" = "[in_worlds]",
		"{running_worlds}" = "[all_running]",
		"{running_worlds_label}" = "[all_running] running world[all_running == 1 ? "" : "s"]",
		"{admin_worlds}" = "[admin_worlds]",
		"{max_running_worlds}" = "[lobby_config["max_running_worlds"]]",
		"{address}" = html_encode("[lobby_config["address"]]"),
	)
	for(var/key in values)
		text = replacetext(text, key, values[key])
	return text

/world/Topic()
	return null

/client/New(TopicData)
	// A world sends a player back with babylon_rejoin when its game window stayed hidden
	// (DreamSeeker's start splash bug, see the world's interface.dm): join it again at once.
	var/list/query = istext(TopicData) ? params2list(TopicData) : list()
	TopicData = null
	if(!ckey || findtext(ckey, "guest") == 1 || connection != "seeker")
		return null
	. = ..()
	var/rejoin = query["babylon_rejoin"]
	var/static/regex/world_id = regex(@"^[0-9a-f]{32}$")
	spawn(1)
		if(src)
			mob:show_browser()
			if(istext(rejoin) && world_id.Find(rejoin))
				world.log << "[ckey] returned to rejoin world [rejoin]"
				mob:run_action(list("action" = "join", "world" = rejoin, "spectate" = query["spectate"] == "1" ? "1" : null))

/mob/lobby
	var/busy = 0
	var/view_filter = "active"
	var/notice = ""
	var/list/cards = list()
	var/player_limit = 4
	var/browser_initialized = 0
	var/request_revision = 0
	var/last_browser_content = ""
	var/poll_generation = 0
	var/discord_invite = ""

// BYOND hands a returning player their old mob, so everything tied to the
// previous client connection (its browser page, a pending action, the poll
// loop) must be reset here, or the new client gets an empty grey window.
/mob/lobby/Login()
	..()
	// The lobby's main window has the game skin's id, "mainwindow": on a link() between the
	// lobby and a world, DreamSeeker swaps skins, and after BYOND's Members-ad countdown its
	// handover left the new main window hidden behind the start splash (testing whether the
	// same id avoids it).
	// The skin's static icon is not shown: the window exists before the client has the
	// resource. Set it at login, as the game worlds do.
	var/static/window_icon = 'modular_babylon/icons/babylon13_64.png'
	winset(src, "mainwindow", "icon=\ref[window_icon]")
	loc = locate(1, 1, 1)
	browser_initialized = 0
	last_browser_content = ""
	busy = 0
	request_revision++
	var/generation = ++poll_generation
	world.log << "[ckey] connected to the lobby"
	spawn(50)
		while(client && generation == poll_generation)
			// The page shows the restart screen when these stop: the server went away.
			src << output(null, "mainwindow.browser:lobbyAlive")
			if(!busy)
				// A runtime error must not stop this player's lobby from refreshing.
				try
					show_browser()
				catch(var/exception/error)
					world.log << "Refreshing the lobby of [ckey] failed: [error] ([error.file]:[error.line])"
			sleep(50)

/mob/lobby/Logout()
	world.log << "[ckey] left the lobby"
	browser_initialized = 0
	last_browser_content = ""
	poll_generation++
	..()

/mob/lobby/proc/api(action, list/payload)
	var/list/query = list("secret" = lobby_config["secret"], "actor" = ckey, "action" = action, "payload" = json_encode(payload || list()))
	var/list/response = world.Export("[lobby_config["api"]]/api?[list2params(query)]")
	if(!response || !response["CONTENT"])
		world.log << "Supervisor unavailable for [ckey] ([action])"
		return list("error" = "Supervisor unavailable. Please try again shortly.", "unavailable" = TRUE)
	var/list/result
	try
		result = json_decode(file2text(response["CONTENT"]))
	catch
		return list("error" = "Invalid supervisor response.")
	return result

/mob/lobby/proc/page_start()
	return "<!doctype html><html><head><meta charset='utf-8'><meta http-equiv='X-UA-Compatible' content='IE=edge'><style>[file2text('modular_babylon/lobby/style.css')]</style><script>[file2text('modular_babylon/lobby/loading.js')]</script></head><body>"

/// A number for the page; anything else from the supervisor becomes 0.
/proc/lobby_number(value)
	return isnum(value) ? value : 0

/mob/lobby/proc/loading_panel(world_name, stage)
	return "<div class='loading-shell'><section class='loading' role='status' aria-live='polite' aria-busy='true'><div class='spinner'></div><div class='brand'>BABYLON // WORLD MANAGEMENT</div><h1 id='loading-world'>[html_encode(world_name)]</h1><p id='loading-stage'>[html_encode(stage)]</p><small>Keep this client open while your request completes.</small></section></div>"

/// Shown instead of the world list while the server restarts (or its supervisor is
/// unreachable). loading.js shows the same screen when the lobby connection itself is gone.
/proc/lobby_restart_panel(title, message)
	return "<div class='loading-shell'><section class='loading' role='status' aria-live='polite'><div class='spinner'></div><div class='brand'>BABYLON 13</div><h1>[html_encode(title)]</h1><p>[html_encode(message)]</p><p class='muted'>Every world is saved before the server goes down, and nothing is lost. A restart usually takes a minute or two. Once the server is back, press Reconnect.</p><a class='button primary' href='byond://winset?command=.reconnect'>Reconnect</a></section></div>"

/mob/lobby/proc/show_loading(world_name, stage)
	if(client)
		src << output(list2params(list(world_name, stage)), "mainwindow.browser:showLobbyLoading")

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
	var/content
	if(result["restarting"])
		content = lobby_restart_panel("The server is restarting", result["server_notice"] || "The server is restarting.")
	else if(result["unavailable"])
		content = lobby_restart_panel("The server is unavailable", "The lobby cannot reach its world manager right now, usually because the server is restarting.")
	if(content)
		render_page(content, revision, complete)
		return
	content = "<div class='brand'>BABYLON 13</div><div class='top'><h1>Your station, your next chapter.</h1><a class='button primary' data-stage='Waiting for world settings...' onclick='return beginAction(this)' href='?src=\ref[src];action=create'>+ New game</a></div><nav class='tabs' aria-label='World categories'>"
	var/list/tabs = list("active" = "Active worlds", "mine" = "My worlds", "shared" = "Shared with me", "all" = "Browse worlds")
	for(var/tab in tabs)
		var/selected = view_filter == tab
		content += "<a class='[selected ? "active" : ""]' aria-current='[selected ? "page" : "false"]' data-stage='Loading worlds...' onclick='return beginAction(this)' href='?src=\ref[src];action=filter;filter=[tab]'>[tabs[tab]]</a>"
	content += "</nav><h2 class='page-heading'>[tabs[view_filter]]</h2>"
	var/list/descriptions = list("active" = "Worlds currently running, starting or stopping. Join an online world to continue building.", "mine" = "Worlds you own. Start an offline world, change its settings, or restore a saved checkpoint.", "shared" = "Worlds where you have membership. You can start these even when the owner is away.", "all" = "Worlds available to your account. Guests can join online worlds; owners, members and admins can start offline worlds.")
	content += "<p class='muted'>[descriptions[view_filter]]</p>"
	if(result["admin"])
		content += "<p><span class='badge'>Server administrator</span> <small>Your account can see private worlds, bypass their admission restrictions and the per-owner world limits, and spectate worlds as an invisible ghost without a drone.</small></p>"
	if(result["server_notice"])
		content += "<p class='notice' role='alert'><b>[html_encode(result["server_notice"])]</b></p>"
	content += discord_bar(result["discord"])
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
			// Everything from the supervisor is encoded for where it lands: text and attributes
			// with html_encode, link parameters with url_encode, numbers as numbers.
			var/id = url_encode("[card["id"]]")
			var/world_name = html_encode(card["name"])
			rendered += "<section class='card'><div class='card-head'><h2>[world_name]</h2><span class='badge [html_encode(card["state"])]'>[states[card["state"]] || "Unknown"]</span></div><p>[html_encode(card["description"] || "A Babylon station waiting to be rebuilt.")]</p><div class='meta'>Owner: [html_encode(card["owner"])] &nbsp; | &nbsp; Access: [html_encode(card["visibility"])] &nbsp; | &nbsp; [lobby_number(card["players"])]/[lobby_number(card["max_players"])] players online<br>Your role: <b>[html_encode(card["role"])]</b> &nbsp; | &nbsp; Last active: [html_encode(card["last_active"] || "Unknown")]<br>Last save: [html_encode(card["last_save"] || "None yet")]</div><div class='actions'>"
			if(card["role"] != "guest" || card["state"] != "stopped")
				var/join_label = card["state"] == "stopped" ? "Start and join" : (card["visibility"] == "showcase" && card["role"] == "guest" ? "Visit showcase" : "Join world")
				rendered += "<a class='button primary' data-world='[world_name]' data-stage='Preparing your connection...' onclick='return beginAction(this)' href='?src=\ref[src];action=join;world=[id]'>[join_label]</a>"
				// Admins can look around as an invisible ghost instead of leaving a drone behind.
				if(card["role"] == "admin")
					var/spectate_label = card["state"] == "stopped" ? "Start and spectate" : "Spectate"
					rendered += "<a class='button' data-world='[world_name]' data-stage='Preparing your connection...' onclick='return beginAction(this)' href='?src=\ref[src];action=join;spectate=1;world=[id]'>[spectate_label]</a>"
				if(card["visibility"] == "showcase" && card["role"] == "guest")
					rendered += "<small>Visible ghost visit: explore and chat only. Membership is required to build.</small>"
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
		var/expiry_text = expiry ? "Unused stopped worlds are deleted after [lobby_number(expiry)] days." : "Automatic world expiry is disabled."
		content += "<footer class='footer'>Server limits: [lobby_number(limits["max_running_worlds"])] running worlds; [lobby_number(limits["max_players_per_world"])] players per world; [lobby_number(limits["max_worlds_per_player"])] worlds and [lobby_number(limits["max_running_worlds_per_player"])] running worlds per owner.<br>Private worlds require membership. Your station continues from its last successful checkpoint.<br>[expiry_text]</footer>"
	render_page(content, revision, complete)

/mob/lobby/proc/render_page(content, revision, complete)
	if(!browser_initialized)
		// json_encode leaves "</script>" as is; inside the inline script it would end the script.
		var/initial = replacetext(json_encode(json_encode(list("html" = content, "view" = view_filter, "revision" = revision, "complete" = 1))), "</", "<\\/")
		var/shell = "[page_start()]<main id='browser-content'></main><div id='action-loading' style='display:none'>[loading_panel("Your world", "Working...")]</div><div id='connection-lost' style='display:none'>[lobby_restart_panel("Connection lost", "The connection to the server was lost, most likely because it is restarting.")]</div><script>renderLobby([initial]);</script></body></html>"
		src << browse(shell, "window=mainwindow.browser")
		browser_initialized = 1
	else if(complete || content != last_browser_content)
		src << output(list2params(list(json_encode(list("html" = content, "view" = view_filter, "revision" = revision, "complete" = complete)))), "mainwindow.browser:renderLobby")
	last_browser_content = content

/mob/lobby/Topic(href, list/params)
	if(usr != src)
		return
	run_action(params)

/mob/lobby/proc/run_action(list/params)
	if(!client || busy)
		return
	busy = 1
	request_revision++
	if(params["action"] == "join")
		var/list/card = cards[params["world"]]
		show_loading(card ? card["name"] : "Your world", "Contacting the supervisor and preparing your connection...")
		sleep(1)
	try
		handle_action(params)
	catch(var/exception/error)
		world.log << "Lobby action [params["action"]] by [ckey] failed: [error] ([error.file]:[error.line])"
		notice = "Request failed. Please try again."
	busy = 0
	if(client)
		show_browser(1)

/// Discord link state, requirements and the link/unlink/invite buttons.
/mob/lobby/proc/discord_bar(list/discord)
	if(!islist(discord) || !discord["link"])
		discord_invite = islist(discord) ? (discord["invite"] || "") : ""
		return discord_invite ? "<p class='muted'><a class='button' href='?src=\ref[src];action=discord_invite'>Join our Discord</a></p>" : ""
	discord_invite = discord["invite"] || ""
	var/list/required = list()
	if(discord["require_create"])
		required += "create"
	if(discord["require_join"])
		required += "join"
	var/requirement = length(required) ? "Required to [jointext(required, " and ")] worlds." : "Optional."
	var/invite = discord_invite ? "<a class='button' href='?src=\ref[src];action=discord_invite'>Open our Discord</a>" : ""
	if(discord["linked"])
		return "<div class='discord linked'><b>Discord:</b> linked as <b>[html_encode(discord["name"])]</b>. <span class='buttons'><a class='button' data-stage='Unlinking your Discord account...' onclick='return beginAction(this)' href='?src=\ref[src];action=discord_unlink'>Unlink</a>[invite]</span></div>"
	return "<div class='discord[length(required) ? " required" : ""]'><b>Discord:</b> not linked. [requirement] <span class='buttons'><a class='button primary' data-stage='Creating a link code...' onclick='return beginAction(this)' href='?src=\ref[src];action=discord_link'>Link Discord</a>[invite]</span></div>"

/mob/lobby/proc/handle_action(list/params)
	var/action = params["action"]
	notice = ""
	if(action == "filter")
		if(params["filter"] in list("active", "mine", "shared", "all"))
			view_filter = params["filter"]
		return
	if(action == "discord_invite")
		if(discord_invite)
			src << link(discord_invite)
		return
	if(action == "discord_link")
		var/list/code_result = api("discord_code")
		if(code_result["error"])
			notice = code_result["error"]
			return
		var/command = "/link code:[code_result["code"]]"
		world.log << "[ckey] requested a Discord link code"
		notice = "Your link code is [code_result["code"]]. Type [command] in our Discord within 10 minutes, then reopen this window."
		// An input box, so the command can be copied.
		input(src, "Type this command in our Discord within 10 minutes. You can copy it from this box.", "Link Discord", command) as null|text
		if(discord_invite && alert(src, "Open our Discord now?", "Link Discord", "Open Discord", "Not now") == "Open Discord")
			src << link(discord_invite)
		return
	if(action == "discord_unlink")
		if(alert(src, "Unlink your Discord account from [ckey]?", "Unlink Discord", "Unlink", "Cancel") != "Unlink")
			return
		var/list/unlink_result = api("discord_unlink")
		notice = unlink_result["error"] || "Your Discord account was unlinked."
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
		var/visibility = input(src, "Who can join? Private: members only. Showcase: members play, guests visit as visible ghosts who can only explore and chat. Password: guests need the password. Public: guests can play.", "Visibility", card ? card["visibility"] : "private") in list("private", "showcase", "password", "public")
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
		if(params["spectate"] == "1")
			payload["spectate"] = 1
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
				world.log << "[ckey] sent to world [card["name"]] ([params["world"]])"
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
