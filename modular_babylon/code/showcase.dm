// Visitors are observers (orbit, facing, view range, ghost vision ...), but everything they can
// do stays an allowlist: verbs, keybindings, clicks and topics. No possession, ghost roles,
// deadchat, machine UIs or leaving the station level.
/client
	var/babylon_showcase_visitor = FALSE

/proc/babylon_showcase_allowed_verb(verb_path)
	var/static/list/allowed = list(
		/client/verb/keyDown, /client/verb/keyUp, /client/verb/ooc, /client/verb/babylon_return_lobby,
		/mob/verb/say_verb, /mob/verb/whisper_verb,
		// Observer navigation and view, kept on the station level by abstract_move().
		/mob/dead/observer/verb/follow, /mob/dead/observer/verb/jumptomob, /mob/dead/observer/verb/dead_tele,
		/mob/dead/observer/verb/change_view_range, /mob/dead/observer/verb/add_view_range,
		/mob/dead/observer/verb/toggle_ghostsee, /mob/dead/observer/verb/toggle_darkness,
		// Client upkeep: without these a broken chat could not be repaired.
		/client/verb/fix_tgui_panel, /client/verb/refresh_tgui, /client/verb/fit_viewport, /client/verb/toggle_fullscreen,
	)
	return verb_path in allowed

/// TGUI windows a visitor may answer: the orbit menu and list prompts the server opened for
/// them (Jump to Mob, Teleport). Machine and other interfaces stay blocked.
/proc/babylon_showcase_window_allowed(mob/user, window_id)
	if(!istext(window_id))
		return FALSE
	for(var/datum/tgui/ui as anything in user?.tgui_open_uis)
		if(ui.window?.id == window_id && (ui.src_object == GLOB.orbit_menu || istype(ui.src_object, /datum/tgui_list_input)))
			return TRUE
	return FALSE

/client/proc/babylon_restrict_visitor_verbs()
	for(var/verb_path in verbs.Copy())
		if(!babylon_showcase_allowed_verb(verb_path))
			verbs -= verb_path
	if(mob)
		for(var/verb_path in mob.verbs.Copy())
			if(!babylon_showcase_allowed_verb(verb_path))
				mob.verbs -= verb_path

/proc/babylon_showcase_allowed_keybinding(datum/keybinding/binding)
	return istype(binding, /datum/keybinding/client/communication/say) || istype(binding, /datum/keybinding/client/communication/ooc) || istype(binding, /datum/keybinding/client/toggle_fullscreen) || istype(binding, /datum/keybinding/client/screenshot)

// No arbitrary atom links, machine windows, stat-panel actions or chunked
// messages. Chat transport is allowed, but its verb/channel is also checked.
/proc/babylon_showcase_topic_allowed(list/href_list)
	if(!href_list["tgui"])
		if(!length(href_list))
			return FALSE
		for(var/field in href_list)
			if(!(field in list("asset_cache_confirm_arrival", "asset_cache_preload_data")))
				return FALSE
		return TRUE
	var/message_type = href_list["type"]
	var/window_id = href_list["window_id"]
	if(babylon_showcase_window_allowed(usr, window_id))
		return TRUE
	if(!(window_id in list("browseroutput", "tgui_say")))
		return FALSE
	if(message_type in list("ready", "ping", "ping/set", "visible", "close", "suspend", "log", "chat/resend"))
		return TRUE
	if(window_id == "browseroutput" && (message_type in list("verbs/request_verbs", "requestMetadata")))
		return TRUE
	var/list/payload
	try
		payload = json_decode(href_list["payload"])
	catch
		return FALSE
	if(!islist(payload))
		return FALSE
	if(window_id == "browseroutput")
		if(message_type == "verbs/invoke")
			return text2path(payload["verb_type"]) in list(/mob/verb/say_verb, /mob/verb/whisper_verb, /client/verb/ooc)
		return message_type in list("verbs/request_verbs", "requestMetadata", "telemetry", "audio/setAdminMusicVolume")
	if(message_type in list("thinking", "typing"))
		return TRUE
	if(message_type in list("open", "entry", "save"))
		return payload["channel"] in list(SAY_CHANNEL, OOC_CHANNEL, WHIS_CHANNEL)
	return FALSE

/client/proc/babylon_visitor_click(atom/target)
	if(!(target in screen))
		return
	if(istype(target, /atom/movable/screen/babylon_visitor_return))
		babylon_return_lobby()
	else if(istype(target, /atom/movable/screen/babylon_visitor_orbit) && isobserver(mob))
		var/mob/dead/observer/visitor = mob
		visitor.follow()

/client/DblClick()
	if(babylon_showcase_visitor)
		return
	return ..()

/client/MouseWheel()
	if(babylon_showcase_visitor)
		return
	return ..()

/datum/babylon_save/proc/ensure_showcase_visitor(client/student)
	if(!student?.babylon_showcase_visitor || !student.fully_created)
		return
	if(!istype(student.mob, /mob/dead/observer/babylon_visitor))
		var/mob/previous = student.mob
		if(isnewplayer(previous))
			var/mob/dead/new_player/menu = previous
			menu.spawning = TRUE
			menu.hide_title_screen()
		var/mob/dead/observer/babylon_visitor/visitor = new(respawn_turf)
		visitor.name = "Visitor [student.key]"
		visitor.real_name = visitor.name
		visitor.key = student.key
		student.babylon_restrict_visitor_verbs()
		student.init_verbs()
		winset(student, "title_browser", "is-disabled=true;is-visible=false")
		winset(student, "status_bar", "is-visible=true")
		to_chat(student, span_notice("Showcase visit: everyone can see you. Explore with the movement keys, Orbit (the HUD button or the Orbit verb) and Jump to Mob, and use Say (T) or OOC (O) to chat. You cannot use equipment, operate machines or enter a body. Membership is required to build."))
		if(isnewplayer(previous))
			qdel(previous)

/mob/dead/observer/babylon_visitor
	name = "showcase visitor"
	desc = "A visible projection visiting Babylon. It cannot interact with the station."
	plane = GAME_PLANE
	layer = MOB_LAYER
	can_reenter_corpse = FALSE
	hud_type = /datum/hud/babylon_visitor

/mob/dead/observer/babylon_visitor/Initialize(mapload)
	. = ..()
	// Unlike other ghosts, visitors are seen by the people playing.
	set_invisibility(0)
	grant_all_languages()

/mob/dead/observer/babylon_visitor/Login()
	. = ..()
	client?.babylon_restrict_visitor_verbs()

/// Walking, jumping, teleporting and orbiting all end here: visitors stay on the station.
/mob/dead/observer/babylon_visitor/abstract_move(atom/destination)
	var/turf/target = get_turf(destination)
	if(!target || target.z != GLOB.babylon_save.station_z)
		return FALSE
	return ..()

/mob/dead/observer/babylon_visitor/Logout()
	. = ..()
	spawn(0)
		if(src && !client)
			key = null
			qdel(src)

/mob/dead/observer/babylon_visitor/can_interact_with(atom/target, treat_mob_as_adjacent)
	return FALSE

/mob/dead/observer/babylon_visitor/can_perform_action(atom/target, action_bitflags)
	return FALSE

/mob/dead/observer/babylon_visitor/ClickOn(atom/target, params)
	return

/mob/dead/observer/babylon_visitor/DblClickOn(atom/target, params)
	return

/mob/dead/observer/babylon_visitor/UnarmedAttack(atom/target, proximity, list/modifiers)
	return FALSE

/mob/dead/observer/babylon_visitor/RangedAttack(atom/target, list/modifiers)
	return FALSE

/mob/dead/observer/babylon_visitor/start_pulling()
	return FALSE

/mob/dead/observer/babylon_visitor/put_in_hands()
	return FALSE

/mob/dead/observer/babylon_visitor/ghostize(can_reenter_corpse = TRUE, forced = FALSE)
	return null

/mob/dead/observer/babylon_visitor/emote()
	return FALSE

/mob/dead/observer/babylon_visitor/whisper(message, bubble_type, list/spans = list(), sanitize = TRUE, datum/language/language, ignore_spam = FALSE, forced, filterproof)
	return say(message, message_range = 1)

// Chat goes to nearby clients only, never to speech-triggered machinery.
/mob/dead/observer/babylon_visitor/say(message, bubble_type, list/spans = list(), sanitize = TRUE, datum/language/language, ignore_spam = FALSE, forced, filterproof = FALSE, message_range = 7, datum/saymode/saymode, list/message_mods = list())
	if(!client || GLOB.say_disabled || !istext(message) || !try_speak(message))
		return
	message = trim(copytext_char(html_encode(message), 1, MAX_MESSAGE_LEN))
	if(!length(message))
		return
	log_say("SHOWCASE: [key_name(src)]: [message]")
	var/rendered = "<span class='game say'><b>[html_encode(name)]</b> says, \"[message]\"</span>"
	for(var/client/listener in GLOB.clients)
		if(listener.mob?.z == z && get_dist(src, listener.mob) <= clamp(message_range, 1, 7))
			to_chat(listener, rendered)
	return TRUE

/mob/dead/observer/babylon_visitor/Hear(atom/movable/speaker, message_language, raw_message, radio_freq, radio_freq_name, radio_freq_color, list/spans, list/message_mods = list(), message_range = 0)
	to_chat(src, compose_message(speaker, message_language, raw_message, radio_freq, radio_freq_name, radio_freq_color, spans, message_mods))
	return HEAR_HEARD | HEAR_UNDERSTOOD

/datum/hud/babylon_visitor/initialize_screen_objects()
	. = ..()
	add_screen_object("babylon_visitor_return", new /atom/movable/screen/babylon_visitor_return)
	add_screen_object("babylon_visitor_orbit", new /atom/movable/screen/babylon_visitor_orbit)

/atom/movable/screen/babylon_visitor_return
	name = "Return to lobby"
	icon = 'modular_babylon/icons/babylon_actions.dmi'
	icon_state = "return_lobby"
	screen_loc = "WEST:6,NORTH:0"

/atom/movable/screen/babylon_visitor_orbit
	name = "Orbit"
	icon = 'icons/hud/screen_ghost.dmi'
	icon_state = "orbit"
	screen_loc = "WEST:6,NORTH-1:0"
