// Authenticated integration-test helpers; excluded from production builds.
GLOBAL_DATUM_INIT(babylon_debug, /datum/babylon_debug, new)

// Exercises the same native HTTP export as the admission gate, without a client.
/datum/babylon_save/proc/test_supervisor_export(encoded_query)
	return babylon_supervisor_request(json_decode(encoded_query))

/datum/babylon_save/proc/test_afk_policy()
	var/datum/babylon_afk/policy = new
	var/list/result = list()
	result["active"] = isnull(policy.update(839 SECONDS, 15 MINUTES))
	result["warning_boundary"] = policy.update(840 SECONDS, 15 MINUTES) == "warn"
	result["warning_once"] = isnull(policy.update(850 SECONDS, 15 MINUTES))
	result["activity_cancels_warning"] = isnull(policy.update(1 SECONDS, 15 MINUTES)) && !policy.warned
	result["warning_rearmed"] = policy.update(840 SECONDS, 15 MINUTES) == "warn"
	result["kick_boundary"] = policy.update(15 MINUTES, 15 MINUTES) == "kick"
	result["kick_once"] = isnull(policy.update(901 SECONDS, 15 MINUTES))
	result["activity_cancels_kick"] = isnull(policy.update(0, 15 MINUTES)) && !policy.kick_pending
	result["kick_rearmed"] = policy.update(15 MINUTES, 15 MINUTES) == "kick"
	result["disabled"] = isnull(policy.update(100 MINUTES, 0)) && !policy.kick_pending && !policy.warned
	result["short_timeout_warning"] = policy.update(1 SECONDS, 10 SECONDS) == "warn"
	result["short_timeout_kick"] = policy.update(10 SECONDS, 10 SECONDS) == "kick"
	qdel(policy)
	return result

/datum/babylon_save/proc/test_builder_experience()
	var/mob/living/basic/drone/babylon/replacement/empty = new(respawn_turf)
	var/item_count = 0
	for(var/obj/item/item in empty.contents)
		item_count++
	var/list/result = list("replacement_items" = item_count, "replacement_storage" = !!empty.internal_storage, "replacement_head" = !!empty.head, "station_confinement" = !!empty.GetComponent(/datum/component/stationstuck))
	qdel(empty)
	var/mob/dead/observer/ghost = new(respawn_turf)
	var/datum/hud/ghost/babylon/hud = new(ghost)
	result["spawners_hidden"] = !hud.screen_objects[HUD_GHOST_SPAWNERS]
	result["minigames_hidden"] = !hud.screen_objects[HUD_GHOST_MINIGAMES]
	result["dnr_present"] = !!hud.screen_objects[HUD_GHOST_DNR]
	result["reenter_present"] = !!hud.screen_objects[HUD_GHOST_REENTER_CORPSE]
	result["physical_cafe_turfs"] = length(get_area_turfs(/area/centcom/holding/cafe, subtypes = TRUE))
	var/papers = 0
	for(var/obj/item/paper/babylon/paper in world)
		papers++
	result["lore_papers"] = papers
	result["return_before_destruct"] = builder.actions.Find(return_action) && builder.actions.Find(return_action) < builder.actions.Find(destruct_action)
	qdel(hud)
	qdel(ghost)
	return result

/datum/babylon_save/proc/test_showcase_visitor()
	var/roster_before = length(player_sessions)
	var/turf/start = respawn_turf
	var/turf/destination = get_step(start, EAST)
	var/mob/dead/observer/babylon_visitor/visitor = new(start)
	var/obj/structure/closet/crate/crate = new(destination)
	var/obj/item/screwdriver/tool = new(start)
	var/list/result = list()
	result["visible_to_living"] = !visitor.invisibility && visitor.alpha > 0
	result["observer_without_body"] = isobserver(visitor) && !visitor.can_reenter_corpse && !visitor.mind
	result["no_inventory"] = !length(visitor.contents) && !visitor.put_in_hands(tool) && tool.loc == start
	result["no_physical_actions"] = !visitor.can_perform_action(crate, NONE) && !visitor.can_interact_with(crate) && !visitor.start_pulling(crate)
	visitor.ClickOn(crate, "left=1")
	visitor.UnarmedAttack(crate, TRUE)
	result["cannot_open_crate"] = !crate.opened
	result["no_possession"] = isnull(visitor.ghostize(can_reenter_corpse = TRUE))
	result["no_emote_actions"] = !visitor.emote("boo")
	visitor.Move(destination, EAST)
	result["passes_through_solids"] = visitor.loc == destination && crate.density
	result["faces_movement"] = visitor.dir == EAST
	var/turf/outside = locate(1, 1, station_z == 1 ? 2 : 1)
	visitor.Move(outside, NORTH)
	visitor.forceMove(outside)
	result["station_only"] = outside && visitor.loc == destination
	result["observer_tools_allowed"] = babylon_showcase_allowed_verb(/mob/dead/observer/verb/follow) && babylon_showcase_allowed_verb(/client/verb/fix_tgui_panel)
	result["ghost_powers_blocked"] = !babylon_showcase_allowed_verb(/mob/dead/observer/verb/reenter_corpse) && !babylon_showcase_allowed_verb(/mob/dead/observer/verb/observe)
	result["unknown_window_blocked"] = !babylon_showcase_window_allowed(visitor, "tgui-window-1")
	result["no_player_roster"] = length(player_sessions) == roster_before
	result["raw_machine_link_blocked"] = !babylon_showcase_topic_allowed(list("src" = REF(crate), "open" = 1))
	result["machine_ui_blocked"] = !babylon_showcase_topic_allowed(list("tgui" = TRUE, "window_id" = "tgui1", "type" = "act", "payload" = "{}"))
	result["chunk_bypass_blocked"] = !babylon_showcase_topic_allowed(list("tgui" = TRUE, "window_id" = "browseroutput", "type" = "oversizedPayloadRequest", "payload" = "{}"))
	result["forged_verb_blocked"] = !babylon_showcase_topic_allowed(list("tgui" = TRUE, "window_id" = "browseroutput", "type" = "verbs/invoke", "payload" = json_encode(list("verb_type" = "/mob/dead/observer/proc/reenter_corpse"))))
	result["chat_ready_allowed"] = babylon_showcase_topic_allowed(list("tgui" = TRUE, "window_id" = "browseroutput", "type" = "ready"))
	result["chat_metadata_without_payload"] = babylon_showcase_topic_allowed(list("tgui" = TRUE, "window_id" = "browseroutput", "type" = "requestMetadata"))
	result["chat_verbs_without_payload"] = babylon_showcase_topic_allowed(list("tgui" = TRUE, "window_id" = "browseroutput", "type" = "verbs/request_verbs"))
	result["chat_entry_allowed"] = babylon_showcase_topic_allowed(list("tgui" = TRUE, "window_id" = "tgui_say", "type" = "entry", "payload" = json_encode(list("channel" = SAY_CHANNEL, "entry" = "Hello"))))
	result["say_verb_allowed"] = babylon_showcase_topic_allowed(list("tgui" = TRUE, "window_id" = "browseroutput", "type" = "verbs/invoke", "payload" = json_encode(list("verb_type" = "/mob/verb/say_verb"))))
	result["invalid_chat_payload_blocked"] = !babylon_showcase_topic_allowed(list("tgui" = TRUE, "window_id" = "tgui_say", "type" = "entry", "payload" = "not json"))
	result["unsafe_channel_blocked"] = !babylon_showcase_topic_allowed(list("tgui" = TRUE, "window_id" = "tgui_say", "type" = "entry", "payload" = json_encode(list("channel" = ME_CHANNEL, "entry" = "boo"))))
	result["asset_link_cannot_smuggle_action"] = !babylon_showcase_topic_allowed(list("asset_cache_confirm_arrival" = 1, "src" = REF(crate), "open" = 1))
	qdel(visitor)
	qdel(crate)
	qdel(tool)
	return result

/datum/babylon_debug/proc/resolve_target(reference)
	switch(reference)
		if("builder")
			return GLOB.babylon_save.builder
		if("session")
			return GLOB.babylon_save
		if("master")
			return Master
		if("air")
			return SSair
		if("machines")
			return SSmachines
	if(!istext(reference))
		return null
	return locate(reference)

/datum/babylon_debug/proc/pack_value(value, depth = 0)
	if(isnull(value) || isnum(value) || istext(value))
		return value
	if(ispath(value))
		return list("typepath" = "[value]")
	if(islist(value))
		var/list/values = value
		var/list/entries = list()
		if(depth < 2)
			for(var/index in 1 to min(length(values), 50))
				var/key = values[index]
				entries += list(list("entry" = pack_value(key, depth + 1), "value" = istext(key) ? pack_value(values[key], depth + 1) : null))
		return list("length" = length(values), "entries" = entries)
	if(istype(value, /datum))
		var/datum/object = value
		var/list/description = list("ref" = REF(object), "type" = "[object.type]")
		if(isatom(object))
			var/atom/thing = object
			description["name"] = thing.name
			description["x"] = thing.x
			description["y"] = thing.y
			description["z"] = thing.z
		return description
	return "[value]"

/datum/babylon_debug/proc/unpack_value(value)
	if(!islist(value))
		return value
	var/list/encoded = value
	if("ref" in encoded)
		return resolve_target(encoded["ref"])
	if("typepath" in encoded)
		return text2path(encoded["typepath"])
	if("turf" in encoded)
		var/list/coordinates = encoded["turf"]
		if(length(coordinates) == 3)
			return locate(coordinates[1], coordinates[2], coordinates[3])
		return null
	var/list/decoded = list()
	for(var/index in 1 to length(encoded))
		decoded += list(unpack_value(encoded[index]))
	return decoded

/datum/babylon_debug/proc/admin_request(action, list/request)
	var/datum/target = resolve_target(request["target"] || "builder")
	if(action == "find")
		var/type_filter = text2path(request["type"])
		if(!ispath(type_filter, /atom))
			return list("error" = "find requires an atom type path")
		var/list/matches = list()
		var/limit = clamp(text2num("[request["limit"]]") || 30, 1, 100)
		for(var/atom/thing in world)
			if(istype(thing, type_filter))
				matches += list(pack_value(thing))
				if(length(matches) >= limit)
					break
		return list("matches" = matches, "limit" = limit)
	if(action == "spawn")
		var/spawn_type = text2path(request["type"])
		var/atom/location = unpack_value(request["location"])
		if(!location && isatom(target))
			location = get_turf(target)
		if(!ispath(spawn_type, /atom/movable) || !isatom(location))
			return list("error" = "spawn requires a movable atom type and an atom location")
		var/atom/movable/created = new spawn_type(location)
		return list("ok" = TRUE, "object" = pack_value(created))
	if(!istype(target) || QDELETED(target))
		return list("error" = "Target missing, deleted, or not a datum")
	if(action == "inspect")
		var/list/result = list("object" = pack_value(target))
		var/list/fields = request["vars"]
		if(islist(fields))
			var/list/values = list()
			for(var/field in fields)
				if(field in target.vars)
					values[field] = pack_value(target.vars[field])
			result["vars"] = values
		else
			var/list/names = list()
			for(var/field in target.vars)
				names += field
			result["var_names"] = names
		return result
	if(action == "set_var")
		var/field = request["var"]
		if(!(field in target.vars))
			return list("error" = "Unknown variable")
		target.vars[field] = unpack_value(request["value"])
		return list("ok" = TRUE, "value" = pack_value(target.vars[field]))
	if(action == "call")
		var/procedure = request["proc"]
		if(!istext(procedure) || !hascall(target, procedure))
			return list("error" = "Unknown procedure")
		var/list/arguments = unpack_value(request["args"] || list())
		if(!islist(arguments))
			return list("error" = "args must be an array")
		return list("ok" = TRUE, "result" = pack_value(call(target, procedure)(arglist(arguments))))
	if(action == "delete")
		qdel(target)
		return list("ok" = TRUE)
	return list("error" = "Unknown admin action")

// Reproduce an invalid material identity without changing real stock.
/datum/material_container/proc/babylon_test_invalid_material()
	materials[null] = 0
	return TRUE

// Guards the safe-for-work build (sfw.dm): every check must be TRUE.
/datum/babylon_save/proc/test_moderation()
	var/list/result = list()
	SSplayer_ranks.mentor_controller?.add_player("babylonsmokementor")
	result["no_mentors_loaded"] = !GLOB.mentor_datums["babylonsmokementor"]
	babylon_grant_admin("babylonsmokeadmin")
	var/datum/admins/granted = GLOB.admin_datums["babylonsmokeadmin"]
	result["lobby_admin_granted"] = !!granted?.check_for_rights(R_EVERYTHING)
	GLOB.admin_datums -= "babylonsmokeadmin"
	result["reply_needs_the_player"] = babylon_discord_ahelp_reply("babylonsmokeabsent", "Mod", "Hello")["result"] == "The player is no longer in this world"
	result["ticket_commands_refused"] = !babylon_discord_ahelp_reply("babylonsmokeabsent", "Mod", "ticket close")["ok"]
	var/mob/living/basic/drone/babylon/named = new(respawn_turf)
	var/base = named.name
	named.key = "Smoke Namer"
	named.babylon_show_player_key()
	named.babylon_show_player_key()
	result["drone_shows_player_key"] = named.name == "[base] (Smoke Namer)"
	named.key = null
	qdel(named)
	result["station_named_after_world"] = station_name() == world.params["babylon-name"]
	var/build_commit = world.GetConfig("env", "BABYLON_COMMIT")
	result["revision_from_build"] = build_commit ? GLOB.revdata.commit == build_commit : isnull(GLOB.revdata.commit)
	result["closing_needs_a_ticket"] = babylon_discord_ahelp_close(987654, "Mod")["result"] == "That ticket does not exist in this world"
	result["ooc_allowed_during_round"] = GLOB.ooc_allowed && SSticker.current_state >= GAME_STATE_PLAYING
	result["ooc_logged"] = !!CONFIG_GET(flag/log_ooc)
	return result

/datum/babylon_save/proc/test_research()
	var/list/result = list()
	var/datum/techweb/science/web = locate(/datum/techweb/science) in SSresearch.techwebs
	var/list/candidates = list()
	for(var/id in web?.available_nodes)
		var/datum/techweb_node/node = SSresearch.techweb_node_by_id(id)
		var/list/price = node.get_price(web)
		if(!web.researched_nodes[id] && !web.hidden_nodes[id] && !length(node.required_experiments) && price[TECHWEB_POINT_TYPE_GENERIC] > 10 && length(price) == 1)
			candidates += node
	result["two_candidate_nodes"] = length(candidates) >= 2
	if(length(candidates) < 2)
		return result
	var/datum/techweb_node/first = candidates[1]
	var/datum/techweb_node/second = candidates[2]
	var/first_price = first.get_price(web)[TECHWEB_POINT_TYPE_GENERIC]
	var/saved_target = web.babylon_target
	web.babylon_target = null
	web.add_point_list(list(TECHWEB_POINT_TYPE_GENERIC = 5))
	result["no_target_no_bank"] = web.research_points[TECHWEB_POINT_TYPE_GENERIC] == 0
	result["queue_refused"] = !web.enqueue_node(first.id, null) && !length(web.research_queue_nodes)
	result["selected"] = web.babylon_select(first.id) && web.babylon_target == first.id
	web.add_point_list(list(TECHWEB_POINT_TYPE_GENERIC = 5))
	result["income_counts_for_target"] = web.research_points[TECHWEB_POINT_TYPE_GENERIC] == 5
	web.babylon_select(second.id)
	result["switching_resets_progress"] = web.research_points[TECHWEB_POINT_TYPE_GENERIC] == 0 && web.babylon_target == second.id
	web.babylon_select(first.id)
	web.add_point_list(list(TECHWEB_POINT_TYPE_GENERIC = first_price * 10))
	result["researched_when_paid"] = !!web.researched_nodes[first.id] && !web.babylon_target
	result["excess_not_banked"] = web.research_points[TECHWEB_POINT_TYPE_GENERIC] == 0
	web.unresearch_node(first)
	web.babylon_target = saved_target
	return result

/datum/babylon_save/proc/test_closet_contents()
	var/list/result = list()
	result["station_has_supermatter"] = length(SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/power/supermatter_crystal)) > 0
	var/obj/structure/closet/crate/secure/engineering/crate = new(respawn_turf)
	var/obj/machinery/power/supermatter_crystal/shard/shard = new(crate)
	shard.warning_channel = null
	var/list/records = list()
	capture(crate, records, null)
	var/saved = FALSE
	for(var/list/record as anything in records)
		if(record["type"] == "[shard.type]" && record["parent"])
			saved = TRUE
	result["machine_in_crate_saved"] = saved
	qdel(shard)
	qdel(crate)
	return result

/datum/babylon_save/proc/test_music_folders()
	var/list/result = list()
	var/datum/babylon_music/music = new
	music.root = "data/babylon_music_test/"
	fdel(music.root)
	for(var/track in list("space/a.ogg", "station/b.mp3", "derelict/c.wav", "engine/d.ogg", "loose.ogg", "station/notes.txt"))
		text2file("", "[music.root][track]")
	music.scan_folder("", 0)
	result["folders_scanned"] = length(music.tracks) == 4 && length(music.tracks["station"]) == 1
	var/turf/void
	for(var/turf/open/space/candidate in block(locate(1, 1, station_z), locate(world.maxx, 5, station_z)))
		void = candidate
		break
	result["space_folder"] = !!void && music.folder_for(void) == "space"
	// A floor away from the wreck's own generators; its air decides derelict or station.
	music.engine_radius = 3
	var/turf/open/floor/floor
	for(var/turf/open/floor/candidate in get_area_turfs(/area/ruin/space/bb13/hallway, station_z, TRUE))
		if(!music.near_engine(candidate))
			floor = candidate
			break
	result["floor_found"] = !!floor
	if(floor)
		var/datum/gas_mixture/air = floor.return_air()
		var/datum/gas_mixture/original = air.copy()
		air.remove_ratio(1)
		result["airless_room_is_derelict"] = music.folder_for(floor) == "derelict"
		air.copy_from(SSair.parse_gas_string(OPENTURF_DEFAULT_ATMOS))
		result["room_with_air_is_station"] = music.folder_for(floor) == "station"
		// Any generator, wherever it was built, plays engine music; packed in a crate it does not.
		var/obj/machinery/power/rtg/generator = new(floor)
		result["generator_plays_engine"] = music.folder_for(floor) == "engine"
		var/obj/machinery/power/solar/panel = new(floor)
		generator.forceMove(new /obj/structure/closet/crate(floor))
		result["crated_generator_and_solar_do_not"] = music.folder_for(floor) == "station"
		var/obj/structure/closet/crate/crate = generator.loc
		qdel(generator)
		qdel(crate)
		qdel(panel)
		music.tracks -= "derelict"
		air.remove_ratio(1)
		result["empty_derelict_falls_back_to_station"] = music.folder_for(floor) == "station"
		air.copy_from(original)
	// A short trip keeps the playing track; staying for the debounce time switches.
	music.debounce = 20 SECONDS
	var/list/pending = list(null, 0)
	var/list/steps = list(
		music.debounced(null, "station", pending, 0) == "station",
		music.debounced("station", "space", pending, 10) == "station",
		music.debounced("station", "station", pending, 20) == "station",
		music.debounced("station", "space", pending, 30) == "station",
		music.debounced("station", "space", pending, 30 + 19 SECONDS) == "station",
		music.debounced("station", "space", pending, 30 + 20 SECONDS) == "space",
	)
	result["debounce_keeps_then_switches"] = !(FALSE in steps)
	result["title_from_file_name"] = babylon_music_title("/music/space/Deep_Space Drift.v2.ogg") == "Deep Space Drift.v2"
	fdel(music.root)
	return result

/datum/babylon_save/proc/test_space_wrap()
	var/list/result = list()
	var/middle = round(world.maxy / 2)
	var/turf/open/west = locate(1, middle, station_z)
	var/turf/open/east = locate(world.maxx, middle, station_z)
	var/turf/open/north = locate(round(world.maxx / 2), world.maxy, station_z)
	result["west_edge_leads_east"] = istype(west) && west.destination_z == station_z && west.destination_x > world.maxx / 2
	result["east_edge_leads_west"] = istype(east) && east.destination_z == station_z && east.destination_x < world.maxx / 2
	result["north_edge_leads_south"] = istype(north) && north.destination_z == station_z && north.destination_y < world.maxy / 2
	// Drift west into the border: arrive on the east side, still drifting.
	var/obj/item/stack/rods/drifter = new(locate(TRANSITIONEDGE + 3, middle, station_z))
	drifter.newtonian_move(dir2angle(WEST), drift_force = 5 NEWTONS)
	for(var/attempt in 1 to 20)
		sleep(5)
		if(drifter.x > world.maxx / 2)
			break
	result["drift_wraps_to_the_other_side"] = drifter.z == station_z && drifter.x > world.maxx / 2
	result["drift_keeps_momentum"] = !!drifter.drift_handler
	qdel(drifter)
	return result

/datum/babylon_save/proc/test_no_storyteller()
	var/list/result = list()
	result["babylon_storyteller"] = SSgamemode.storyteller?.type == /datum/storyteller/babylon
	result["no_vote_running"] = !istype(SSvote.current_vote, /datum/vote/storyteller)
	result["vote_refused"] = !SSvote.initiate_vote(/datum/vote/storyteller, "Babylon test", forced = TRUE)
	SSgamemode.set_storyteller(/datum/storyteller/high, TRUE, "babylon-test")
	result["other_storyteller_refused"] = SSgamemode.storyteller?.type == /datum/storyteller/babylon
	result["no_scheduled_events"] = !length(SSgamemode.scheduled_events)
	return result

/datum/babylon_save/proc/test_sfw_content()
	var/list/result = list()
	result["erp_preferences_disabled"] = !!CONFIG_GET(flag/disable_erp_preferences)
	result["lewd_items_disabled"] = !!CONFIG_GET(flag/disable_lewd_items)
	var/mob/living/basic/drone/babylon/replacement/first = new(respawn_turf)
	var/mob/living/basic/mouse/second = new(respawn_turf)
	var/datum/component/interactable/menu = second.GetComponent(/datum/component/interactable)
	menu.build_interactions_list()
	var/listed_erp = FALSE
	for(var/datum/interaction/interaction as anything in menu.interactions)
		if(babylon_interaction_is_erp(interaction))
			listed_erp = TRUE
	result["no_erp_interactions_listed"] = !listed_erp
	var/allowed_erp = FALSE
	for(var/name in SSinteractions.interactions)
		var/datum/interaction/interaction = SSinteractions.interactions[name]
		if(babylon_interaction_is_erp(interaction) && menu.can_interact(interaction, first))
			allowed_erp = TRUE
	result["no_erp_interactions_allowed"] = !allowed_erp
	result["no_erp_ui_data"] = !("genitals" in menu.ui_data(first)) && !length(menu.ui_static_data(first))
	var/datum/emote/living/lewd/lewdmoan/emote = new
	result["no_lewd_emotes"] = !emote.can_run_emote(first, intentional = TRUE)
	qdel(emote)
	qdel(second)
	qdel(first)
	var/erp_designs = FALSE
	for(var/node_id in SSresearch.techweb_nodes)
		var/datum/techweb_node/node = SSresearch.techweb_nodes[node_id]
		for(var/design_id in node.design_ids)
			if(design_id in babylon_erp_design_ids())
				erp_designs = TRUE
	result["no_erp_designs"] = !erp_designs
	var/erp_reactions = FALSE
	for(var/reaction_path in GLOB.chemical_reactions_list)
		if(babylon_reaction_is_erp(GLOB.chemical_reactions_list[reaction_path]))
			erp_reactions = TRUE
	result["no_erp_reactions"] = !erp_reactions
	var/obj/item/toy/plush/bubbleplush/plush = new(respawn_turf)
	result["no_plush_toy_slot"] = !plush.plappable && !plush.atom_storage
	qdel(plush)
	return result
