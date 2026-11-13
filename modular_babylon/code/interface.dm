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
	// The outermost /client/New override: everything above has returned. A stuck join without
	// this line means New() never returned, which keeps DreamSeeker on its start splash.
	log_world("Babylon: [key] finished connecting ([mob?.type]).")
	babylon_watch_game_window()

/// Some first joins stay on DreamSeeker's "Your game will begin shortly" splash although the
/// world is done: the game window never appears. Watches for it, logs what happens and shows
/// the window if it is still hidden after 10 seconds.
/client/proc/babylon_watch_game_window()
	set waitfor = FALSE
	var/started = world.time
	for(var/attempt in 1 to 30)
		sleep(2 SECONDS)
		if(!src)
			return
		if(winget(src, "mainwindow", "is-visible") == "true")
			if(attempt > 1)
				log_world("Babylon: [key]'s game window appeared after [DisplayTimeText(world.time - started)].")
			return
		if(attempt == 5)
			log_world("Babylon: [key]'s game window is still hidden after 10 seconds; showing it.")
			winset(src, "mainwindow", "is-visible=true")
	log_world("Babylon: [key]'s game window never appeared within a minute (mob [mob?.type]).")

/// The top bar keeps Menu, Settings, Fullscreen and Reconnect in upstream's own button slots:
/// Settings moves into Character's slot and Fullscreen into Settings', Reconnect stays at the
/// right edge. The slots are read from the client (winget), so they are in its real pixels
/// whatever its window size and display scaling; computed sizes overflowed narrow windows.
/client/proc/babylon_setup_top_bar()
	set waitfor = FALSE
	var/character_slot = winget(src, "infobuttons.hotkeys", "pos;size;anchor1;anchor2")
	var/settings_slot = winget(src, "infobuttons.settings", "pos;size;anchor1;anchor2")
	if(!src)
		return
	winset(src, null, "infobuttons.hotkeys.is-visible=false;infobuttons.relays.is-visible=false;infobuttons.wiki.is-visible=false")
	if(character_slot && settings_slot)
		winset(src, "infobuttons.settings", character_slot)
		winset(src, "infobuttons.fullscreen-toggle", settings_slot)
	// The game window (and the Windows taskbar) shows the Babylon drone instead of SPLURT's icon.
	// The shared skin.dmf is not changed; the file reference compiles the icon into the .rsc.
	// A call of its own, so an icon the client rejects cannot undo the top bar changes.
	var/static/window_icon = 'modular_babylon/icons/babylon13_64.png'
	winset(src, "mainwindow", "icon=\ref[window_icon]")

/mob
	/// Babylon: the mob's name without its player's key, so the key is only ever added once.
	var/babylon_base_name

/// Drones, ghosts and showcase visitors show who controls them: "derelict drone (611) (Key)".
/// Names that already contain the key (ghosts named after their player) stay as they are.
/mob/proc/babylon_show_player_key()
	if(!world.params["babylon-world"] || !key)
		return
	if(!istype(src, /mob/living/basic/drone) && !isobserver(src))
		return
	var/suffix = " ([key])"
	if(!babylon_base_name)
		babylon_base_name = name
		// A name restored from a save may already end with this player's key.
		var/cut = length(name) - length(suffix)
		if(cut > 0 && copytext(name, cut + 1) == suffix)
			babylon_base_name = copytext(name, 1, cut + 1)
	var/shown = findtext(babylon_base_name, key) ? babylon_base_name : "[babylon_base_name][suffix]"
	if(name == shown)
		return
	fully_replace_character_name(real_name, shown)
	name = shown

/mob/Login()
	. = ..()
	babylon_show_player_key()
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

/// The image has no .git, so rust-g returns "failed to open repository" text for every git
/// lookup. The revision comes from the image instead (BABYLON_COMMIT and friends, set by CI),
/// and anything that is not a commit hash is dropped rather than shown as one.
/datum/getrev/New()
	..()
	// Not static: this datum is created during global init, before static vars are set up.
	var/regex/hash = regex(@"^[0-9a-f]{7,40}$")
	var/build_commit = world.GetConfig("env", "BABYLON_COMMIT")
	if(istext(build_commit) && hash.Find(build_commit))
		commit = build_commit
		originmastercommit = build_commit
		date = world.GetConfig("env", "BABYLON_COMMIT_DATE")
	if(!istext(commit) || !hash.Find(commit))
		commit = null
	if(!istext(originmastercommit) || !hash.Find(originmastercommit))
		originmastercommit = null
	if(!commit && !originmastercommit)
		date = null

/// The repository players can read the code at: the build's, or the configured GitHub URL.
/proc/babylon_repository_url()
	var/repository = world.GetConfig("env", "BABYLON_REPOSITORY")
	if(istext(repository) && findtext(repository, "https://") == 1)
		return repository
	return CONFIG_GET(string/githuburl)

/// Babylon's revision info: BYOND version, repository, commit and build date. No round ID or
/// antagonist settings, which Babylon does not have.
/client/__gvb_showrevinfo(list/structured_args)
	var/list/msg = list()
	msg += "<b>BYOND Version:</b> [world.byond_version].[world.byond_build]"
	if(DM_VERSION != world.byond_version || DM_BUILD != world.byond_build)
		msg += "<b>Compiled with BYOND Version:</b> [DM_VERSION].[DM_BUILD]"
	var/repository = babylon_repository_url()
	if(repository)
		msg += "<b>Repository:</b> <a href=\"[html_encode(repository)]\">[html_encode(repository)]</a>"
	var/datum/getrev/revdata = GLOB.revdata
	if(revdata?.commit)
		var/short = copytext(revdata.commit, 1, 12)
		msg += "<b>Commit:</b> [repository ? "<a href=\"[html_encode(repository)]/commit/[revdata.commit]\">[short]</a>" : short]"
		if(revdata.date)
			msg += "<b>Built from a commit of:</b> [html_encode(revdata.date)]"
	else
		msg += "No commit information (a local build)."
	to_chat(src, fieldset_block("Server Revision Info", span_infoplain(jointext(msg, "<br>")), "boxed_message"), type = MESSAGE_TYPE_INFO)
