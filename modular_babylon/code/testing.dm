// Authenticated integration-test helpers; excluded from production builds.
GLOBAL_DATUM_INIT(babylon_debug, /datum/babylon_debug, new)

// Exercises the same native HTTP export as the admission gate, without a client.
/datum/babylon_save/proc/test_supervisor_export(encoded_query)
	return babylon_supervisor_request(json_decode(encoded_query))

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
