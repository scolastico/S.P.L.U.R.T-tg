// Babylon's game window: a smaller top bar, the world's name as the station's, no round ID,
// and no verbs for systems Babylon does not have (antags, OPFOR, round end, votes, jobs ...).

/client/New(TopicData)
	. = ..()
	if(!src)
		return
	babylon_setup_top_bar()
	remove_verb(src, list(
		/client/verb/check_antag_tickets,
		/client/verb/antag_tickets_info,
		/client/verb/show_character_directory,
		/client/verb/map_vote_tally_count,
		/client/verb/linkforumaccount,
		/client/verb/verify_in_discord,
		/client/verb/notify_restart,
		/client/verb/go2relay,
		/client/verb/policy,
		/client/verb/checkachievements,
		/client/proc/show_previous_roundend_report,
		/client/proc/show_servers_last_roundend_report,
	))
	// Antag and security OOC channels; admins keep them.
	if(!holder)
		remove_verb(src, list(/client/verb/aooc, /client/verb/sooc))

/// The top bar keeps Menu, Settings, Fullscreen and Reconnect, spread over the 640px pane
/// (skin.dmf has seven buttons of 88px at 14% steps; Character, Relays and Wiki are hidden).
/client/proc/babylon_setup_top_bar()
	var/list/settings = list("infobuttons.hotkeys.is-visible=false", "infobuttons.relays.is-visible=false", "infobuttons.wiki.is-visible=false")
	var/list/kept = list("options", "settings", "fullscreen-toggle", "reconnect")
	for(var/index in 1 to length(kept))
		var/button = "infobuttons.[kept[index]]"
		settings += "[button].pos=[2 + (index - 1) * 160],5"
		settings += "[button].size=156x27"
		settings += "[button].anchor1=[(index - 1) * 25],0"
		settings += "[button].anchor2=[index * 25],100"
	winset(src, null, jointext(settings, ";"))
	// The game window (and the Windows taskbar) shows the Babylon drone instead of SPLURT's icon.
	// The shared skin.dmf is not changed; the file reference compiles the icon into the .rsc.
	// A call of its own, so an icon the client rejects cannot undo the top bar changes.
	var/static/window_icon = 'modular_babylon/icons/babylon13_64.png'
	winset(src, "mainwindow", "icon=\ref[window_icon]")

/mob/Login()
	. = ..()
	remove_verb(src, list(
		/mob/verb/opposing_force,
		/mob/verb/request_internet_sound,
		/mob/verb/abandon_mob,
		/mob/verb/vote,
		/mob/verb/adjust_degradation,
		/mob/verb/refresh_death_consequences,
		/mob/proc/view_exploitables_verb,
		/mob/living/verb/reflexes_verb,
		/mob/dead/observer/verb/join_soulcatcher,
	))

/// The world's name (from the lobby) is the station's name. It is player-written and
/// station_name() lands in chat HTML across the code base, so markup characters are dropped.
/proc/babylon_apply_world_name()
	var/raw = world.params["babylon-name"]
	if(!istext(raw))
		return
	var/static/regex/markup = regex("\[<>&\"\]", "g")
	var/clean = trim(markup.Replace(raw, ""))
	if(length(clean))
		set_station_name(copytext_char(clean, 1, 61))

/// The status tab without the round ID; Babylon worlds have no rounds.
/datum/controller/subsystem/statpanels/set_status_tab(client/target)
	if(!global_data)
		return
	var/list/shown = list()
	for(var/entry in global_data)
		if(istext(entry) && findtext(entry, "Round ID:") == 1)
			continue
		shown += list(entry)
	target.stat_panel.send_message("update_stat", list(
		"global_data" = shown,
		"other_str" = target.mob?.get_status_tab_items(),
	))

/// Tells the pause screen it is a Babylon world: no round ID, no "No Admins Online!".
/datum/escape_menu/send_init()
	. = ..()
	send_update(list("babylon" = TRUE))
