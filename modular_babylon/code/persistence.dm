/datum/babylon_save/proc/preload_atom(atom/thing)
	if(!resume_data && fexists("data/babylon/resume-state.json"))
		resume_data = json_decode(file2text("data/babylon/resume-state.json"))
		for(var/list/record as anything in resume_data["records"])
			resume_records[record["id"]] = record
	var/list/record = resume_records[thing.babylon_save_id]
	if(!record)
		return
	var/list/fields = record["fields"]
	for(var/field in structural_fields)
		if((field in fields) && (field in thing.vars))
			thing.vars[field] = decode_value(fields[field])
	if((resume_data["version"] || 1) < 2)
		if(istype(thing, /obj/machinery/atmospherics/components/trinary))
			thing.vars["flipped"] = findtext(fields["icon_state"], "_f") > 0
		if(istype(thing, /obj/machinery/atmospherics/pipe/smart))
			// Smart-pipe dir describes existing neighbours, not allowed ports.
			// Version 1 omitted the port mask; use the RPD/dispenser default.
			// Inferring it from dir prevents adding branches after recovery.
			thing.vars["initialize_directions"] = ALL_CARDINALS

/datum/babylon_save/proc/encode_gas(datum/gas_mixture/gas)
	if(!gas)
		return null
	var/list/moles = list()
	for(var/gas_type, amount in gas.moles)
		moles["[gas_type]"] = amount
	return list("temperature" = gas.temperature, "volume" = gas.volume, "moles" = moles)

/datum/babylon_save/proc/restore_gas(datum/gas_mixture/gas, data)
	if(!gas || !data)
		return
	if(istext(data))
		gas.copy_from(SSair.parse_gas_string(data))
	else
		var/list/saved = data
		gas.moles.Cut()
		var/list/moles = saved["moles"]
		for(var/gas_type in moles)
			gas.moles[text2path(gas_type)] = moles[gas_type]
		gas.temperature = saved["temperature"]
		gas.volume = saved["volume"]
	gas.archive()

/datum/babylon_save/proc/material_container(atom/thing)
	if(!("materials" in thing.vars))
		return null
	var/datum/value = thing.vars["materials"]
	if(istype(value, /datum/remote_materials))
		var/datum/remote_materials/remote = value
		return remote.mat_container
	if(istype(value, /datum/material_container))
		return value
	return null

// A rebuilt lathe normally waits for roundstart to create local storage.
// Restore it now, before the simulation resumes, and keep its silo link.
/datum/remote_materials/proc/babylon_restore_container(obj/machinery/ore_silo/saved_silo)
	if(connection)
		LAZYREMOVE(SSticker.round_start_events, connection)
		connection = null
	if(saved_silo)
		saved_silo.connect_receptacle(src, parent)
	else if(!mat_container && allow_standalone)
		_MakeLocal()
	return mat_container

// An invalid material key must not abort UI generation or stock accounting.
// Valid material identities and amounts are left untouched.
/datum/material_container/proc/babylon_prune_invalid_materials()
	if(!islist(materials))
		return
	for(var/material in materials.Copy())
		if(!istype(material, /datum/material))
			materials.Remove(material)

/datum/babylon_save/proc/assign_id(atom/thing)
	if(!thing.babylon_save_id)
		thing.babylon_save_id = "bb[next_id++]"
	return thing.babylon_save_id

/datum/babylon_save/proc/encode_value(value)
	if(isnull(value) || isnum(value) || istext(value))
		return value
	if(ispath(value))
		return list("path" = "[value]")
	if(isatom(value))
		var/atom/thing = value
		return list("atom" = assign_id(thing))
	if(islist(value))
		var/list/result = list()
		var/list/values = value
		for(var/index in 1 to length(values))
			var/key = values[index]
			result += list(list("key" = encode_value(key), "value" = (!isnum(key) && !isnull(key)) ? encode_value(values[key]) : null))
		return list("entries" = result)
	return null

/datum/babylon_save/proc/decode_value(value)
	if(!islist(value))
		return value
	var/list/encoded = value
	if("path" in encoded)
		return text2path(encoded["path"])
	if("atom" in encoded)
		return restored_atoms[encoded["atom"]]
	if("sequence" in encoded)
		var/list/result = list()
		for(var/entry in encoded["sequence"])
			result += list(decode_value(entry))
		return result
	if("entries" in encoded)
		var/list/result = list()
		for(var/list/entry as anything in encoded["entries"])
			var/key = decode_value(entry["key"])
			result += list(key)
			if(!isnull(entry["value"]) && !isnum(key) && !isnull(key))
				result[key] = decode_value(entry["value"])
		return result
	return null

/datum/babylon_save/proc/capture(atom/thing, list/records, parent_id)
	var/save_id = assign_id(thing)
	var/list/record = list("id" = save_id, "type" = "[thing.type]", "parent" = parent_id, "x" = thing.x, "y" = thing.y, "fields" = list(), "references" = list())
	var/list/fields = record["fields"]
	var/list/capture_fields = capture_fields_by_type[thing.type]
	if(isnull(capture_fields))
		capture_fields = list()
		for(var/field in state_fields | extra_fields | structural_fields)
			if(field in thing.vars)
				capture_fields += field
		capture_fields_by_type[thing.type] = capture_fields
	for(var/field in capture_fields)
		var/value = thing.vars[field]
		if(isnull(value) || isnum(value) || istext(value) || ispath(value) || (field in list_fields))
			fields[field] = encode_value(value)
	if(istype(thing, /obj/machinery/portable_atmospherics))
		var/obj/machinery/portable_atmospherics/portable = thing
		// An explicit null distinguishes an intentionally detached device from
		// older checkpoints which never recorded this relationship.
		record["portable_port"] = encode_value(portable.connected_port)
	if(istype(thing, /obj/machinery/airalarm))
		var/obj/machinery/airalarm/alarm = thing
		var/list/thresholds = list()
		for(var/key in alarm.tlv_collection)
			var/datum/tlv/threshold = alarm.tlv_collection[key]
			thresholds += list(list("key" = encode_value(key), "type" = "[threshold.type]", "warning_min" = threshold.warning_min, "warning_max" = threshold.warning_max, "hazard_min" = threshold.hazard_min, "hazard_max" = threshold.hazard_max))
		record["alarm_thresholds"] = thresholds
		record["alarm_mode"] = alarm.selected_mode ? "[alarm.selected_mode.type]" : null
	if(istype(thing, /obj/machinery/atmospherics/components/unary/airlock_pump))
		var/obj/machinery/atmospherics/components/unary/airlock_pump/pump = thing
		var/list/settings = list()
		for(var/field in list("can_unwrench", "internal_pressure_target", "external_pressure_target", "cycle_pressure_target", "allowed_pressure_error", "min_distro_pressure", "docked_side_pressure", "volume_rate", "cycle_timeout", "airlock_pump_distance_limit", "airlock_group_distance_limit", "valid_airlock_typepath", "cycling_set_up", "open_airlock_on_cycle", "is_cycling_audible"))
			settings[field] = encode_value(pump.vars[field])
		record["cycle_settings"] = settings
		record["cycle_internal"] = encode_value(pump.internal_airlocks)
		record["cycle_external"] = encode_value(pump.external_airlocks)
		record["cycle_remaining"] = pump.on ? max(1, timeleft(pump.emergency_stop_timer)) : 0
	if(thing.wires)
		record["wires"] = list("colors" = thing.wires.colors.Copy(), "cut_wires" = thing.wires.cut_wires?.Copy())
	if(istype(thing, /obj/machinery/atmospherics/components/unary/vent_pump))
		var/obj/machinery/atmospherics/components/unary/vent_pump/vent = thing
		record["assigned_area"] = vent.assigned_area ? "[vent.assigned_area.type]" : null
	if(istype(thing, /obj/machinery/atmospherics/components/unary/vent_scrubber))
		var/obj/machinery/atmospherics/components/unary/vent_scrubber/scrubber = thing
		record["assigned_area"] = scrubber.assigned_area ? "[scrubber.assigned_area.type]" : null
	if(istype(thing, /obj/machinery/power/solar_control))
		var/obj/machinery/power/solar_control/control = thing
		record["solar_panels"] = encode_value(control.connected_panels)
		record["solar_tracker"] = encode_value(control.connected_tracker)
	if(istype(thing, /obj/machinery/power/apc))
		var/obj/machinery/power/apc/apc = thing
		record["has_terminal"] = !isnull(apc.terminal)
	var/list/references = record["references"]
	for(var/field in reference_fields)
		if(field in thing.vars)
			references[field] = encode_value(thing.vars[field])
	if(istype(thing, /obj/machinery/power/smes))
		var/obj/machinery/power/smes/smes = thing
		references["terminal"] = encode_value(smes.terminal)
	if(istype(thing, /obj/machinery/power/terminal))
		var/obj/machinery/power/terminal/terminal = thing
		references["master"] = encode_value(terminal.master)
	if(thing.reagents)
		var/list/chems = list()
		for(var/datum/reagent/chem as anything in thing.reagents.reagent_list)
			chems += list(list("type" = "[chem.type]", "volume" = chem.volume, "purity" = chem.purity))
		record["reagents"] = chems
	for(var/field in list("air_contents", "air1", "air2", "air3", "absorbed_gasmix"))
		if(field in thing.vars)
			var/datum/gas_mixture/mix = thing.vars[field]
			if(istype(mix))
				record[field] = encode_gas(mix)
	if(istype(thing, /obj/machinery/atmospherics/pipe))
		var/obj/machinery/atmospherics/pipe/pipe = thing
		if(pipe.parent?.air)
			record["pipeline_gas"] = encode_gas(pipe.parent.air)
	if(istype(thing, /obj/machinery/atmospherics/components))
		var/obj/machinery/atmospherics/components/device = thing
		var/list/airs = list()
		for(var/datum/gas_mixture/gas as anything in device.airs)
			airs += list(encode_gas(gas))
		record["device_airs"] = airs
	if(istype(thing, /obj/machinery))
		var/obj/machinery/machine = thing
		var/list/parts = list()
		for(var/datum/part as anything in machine.component_parts)
			if(istype(part, /datum/stock_part))
				parts += list(list("path" = "[part.type]"))
			else if(isatom(part))
				parts += list(encode_value(part))
		record["parts"] = parts
		if("materials" in machine.vars)
			var/datum/material_container/mats = material_container(machine)
			if(istype(machine.vars["materials"], /datum/remote_materials))
				var/datum/remote_materials/remote = machine.vars["materials"]
				record["material_silo"] = remote.silo ? assign_id(remote.silo) : null
			if(istype(mats))
				var/list/materials = list()
				for(var/datum/material/mat as anything in mats.materials)
					if(!mat)
						continue
					materials["[mat.type]"] = mats.materials[mat]
				record["materials"] = materials
	if(istype(thing, /obj/item/modular_computer))
		var/obj/item/modular_computer/computer = thing
		var/list/programs = list()
		for(var/datum/computer_file/file as anything in computer.stored_files)
			programs += "[file.type]"
		record["programs"] = programs
		record["active_program"] = computer.active_program?.filename
		var/list/background_programs = list()
		for(var/datum/computer_file/program/program as anything in computer.idle_threads)
			background_programs += program.filename
		record["background_programs"] = background_programs
	records += list(record)
	for(var/obj/child in thing.contents)
		if(QDELETED(child))
			continue
		// Containers hold more than items: the engine's secure crate holds the supermatter
		// shard, a machine. Saving only items dropped it from every world after its first save.
		if(isitem(child) || (istype(thing, /obj/structure/closet) && !istype(child, /obj/effect)))
			capture(child, records, save_id)
	return record

/datum/babylon_save/proc/metadata(atom/thing, is_turf = FALSE)
	var/list/entries = list()
	var/list/fields = metadata_fields_by_type[thing.type]
	if(isnull(fields))
		fields = list()
		for(var/field in structural_fields)
			if(field in thing.vars)
				fields += field
		metadata_fields_by_type[thing.type] = fields
	if(!is_turf)
		entries += "babylon_save_id = \"[assign_id(thing)]\""
	for(var/field in fields)
		var/value = thing.vars[field]
		if(isnull(value) || isnum(value) || istext(value) || ispath(value) || (field in list("req_access", "req_one_access")))
			entries += "[field] = [tgm_encode(value)]"
	if(is_turf && isopenturf(thing) && !isspaceturf(thing))
		var/turf/open/open = thing
		var/datum/gas_mixture/gas = open.return_air()
		entries += "initial_gas_mix = [tgm_encode(gas.to_string())]"
	return length(entries) ? "{\n\t[entries.Join(";\n\t")]\n\t}" : ""

/datum/babylon_save/proc/save_world()
	if(!ready || busy)
		return list("error" = "Babylon is not ready or a save is in progress")
	busy = TRUE
	checkpoint_processing = Master.processing
	checkpoint_started = REALTIMEOFDAY
	Master.processing = FALSE
	for(var/player_key in player_sessions)
		var/datum/babylon_save/player = player_sessions[player_key]
		if(!QDELETED(player.builder))
			ADD_TRAIT(player.builder, TRAIT_IMMOBILIZED, "babylon_checkpoint")
			ADD_TRAIT(player.builder, TRAIT_UI_BLOCKED, "babylon_checkpoint")
	sleep(1 TICKS)
	var/list/result
	try
		result = save_world_impl()
	catch(var/exception/error)
		result = list("error" = "Checkpoint failed: [error]")
		log_world("BABYLON SAVE ERROR: [error]")
	if(!result["ok"] && draining)
		draining = FALSE
	release_checkpoint()
	busy = FALSE
	return result

// Only snapshot capture is frozen. Serialization and disk writes use detached data.
/datum/babylon_save/proc/release_checkpoint()
	if(draining)
		return
	for(var/player_key in player_sessions)
		var/datum/babylon_save/player = player_sessions[player_key]
		if(!QDELETED(player.builder))
			REMOVE_TRAIT(player.builder, TRAIT_IMMOBILIZED, "babylon_checkpoint")
			REMOVE_TRAIT(player.builder, TRAIT_UI_BLOCKED, "babylon_checkpoint")
	Master.processing = checkpoint_processing

/datum/babylon_save/proc/save_world_impl()
	var/list/records = list()
	var/list/turfs = list()
	var/list/headers = list()
	var/list/dictionary = list()
	var/list/grid = list()
	var/key_index = 1
	var/list/empty_space_keys = list()
	// A drone can be inside a locker or vent. Save it at the enclosing tile
	// rather than silently dropping its body and inventory from the checkpoint.
	var/list/drones_by_turf = list()
	for(var/mob/living/basic/drone/babylon/drone in GLOB.mob_list)
		var/turf/tile = get_turf(drone)
		if(QDELETED(drone) || tile?.z != station_z)
			continue
		if(!drones_by_turf[tile])
			drones_by_turf[tile] = list()
		var/list/drones = drones_by_turf[tile]
		drones += drone
	// All map changes and room air are exported; nested items and live settings go in state.json.
	for(var/x in 1 to world.maxx)
		grid += "\n([x],1,1) = {\"\n"
		for(var/y in world.maxy to 1 step -1)
			var/turf/tile = locate(x, y, station_z)
			// Most of the 255x255 map is empty space. Reuse identical headers
			// instead of inspecting and encoding its vars 60,000 times.
			var/area/room = get_area(tile)
			var/space_signature
			if(isspaceturf(tile) && !(locate(/obj) in tile) && !drones_by_turf[tile])
				space_signature = "[tile.type]|[room.type]|[tile.dir]|[tile.name]|[tile.pixel_x]|[tile.pixel_y]|[tile.pixel_z]|[tile.layer]|[tile.plane]|[tile.alpha]|[tile.density]|[tile.opacity]|[tile.icon_state]"
				if(empty_space_keys[space_signature])
					grid += "[empty_space_keys[space_signature]]\n"
					continue
			if(!isspaceturf(tile))
				var/list/turf_data = list("x" = x, "y" = y, "temperature" = tile.temperature)
				if(isopenturf(tile))
					var/turf/open/open = tile
					turf_data["gas"] = encode_gas(open.return_air())
				turfs += list(turf_data)
			var/list/objects = list()
			for(var/obj/object in tile)
				if(QDELETED(object))
					continue
				if(istype(object, /obj/projectile))
					continue
				if(istype(object, /obj/machinery/power/terminal))
					var/obj/machinery/power/terminal/terminal = object
					if(istype(terminal.master, /obj/machinery/power/apc))
						continue
				if(istype(object, /obj/effect) && !istype(object, /obj/effect/decal) && !istype(object, /obj/effect/turf_decal))
					continue
				if(object.flags_1 & HOLOGRAM_1)
					continue
				objects += "[object.type][metadata(object)]"
				capture(object, records, null)
			for(var/mob/living/basic/drone/babylon/drone as anything in drones_by_turf[tile])
				if(!QDELETED(drone))
					objects += "[drone.type][metadata(drone)]"
					capture(drone, records, null)
			objects += "[tile.type][metadata(tile, TRUE)]"
			objects += "[room.type]"
			var/header = "(\n[objects.Join(",\n")])\n"
			var/key = dictionary[header]
			if(!key)
				key = calculate_tgm_header_index(key_index++, 3)
				dictionary[header] = key
				headers += "\"[key]\" = [header]"
			if(space_signature)
				empty_space_keys[space_signature] = key
			grid += "[key]\n"
		grid += "\"}\n"
		CHECK_TICK
	var/generation = "save-[time2text(world.realtime, "YYYYMMDD-hhmmss")]-[++save_count]"
	var/base = "data/babylon/saves/[generation]"
	var/map_text = "//[DMM2TGM_MESSAGE]\n[headers.Join()][grid.Join()]"
	var/list/state = list("version" = 5, "generation" = generation, "next_id" = next_id, "save_count" = save_count, "builder" = !QDELETED(builder) ? builder?.babylon_save_id : null, "records" = records, "turfs" = turfs)
	state["player"] = list("respawn_pending" = respawn_pending, "respawn_remaining" = max(0, respawn_ready_at - world.time), "spawn_x" = respawn_turf?.x, "spawn_y" = respawn_turf?.y, "profile" = respawn_pending ? drone_profile.Copy() : capture_drone_profile())
	// 7: non-item contents of closets and crates are saved (restore_lost_supermatter()).
	state["version"] = 7
	var/list/players = list()
	for(var/player_key in player_sessions)
		players[player_key] = player_snapshot(player_sessions[player_key])
	state["players"] = players
	var/datum/techweb/science/research = locate(/datum/techweb/science) in SSresearch.techwebs
	if(research)
		state["research"] = list("nodes" = research.researched_nodes.Copy(), "designs" = research.researched_designs.Copy(), "points" = research.research_points.Copy(), "target" = research.babylon_target, "target_by" = research.babylon_target_by, "target_location" = research.babylon_target_location)
	state["sun"] = list("azimuth" = SSsun.azimuth, "azimuth_mod" = SSsun.azimuth_mod, "base_rotation" = SSsun.base_rotation)
	state["lore"] = GLOB.babylon_lore.snapshot()
	checkpoint_capture_ms = (REALTIMEOFDAY - checkpoint_started) * 100
	release_checkpoint()
	CHECK_TICK
	rustg_file_write(map_text, "[base]/map.dmm")
	rustg_file_write(json_encode(state), "[base]/state.json")
	// latest.json is committed only after both generation files are present.
	if(!fexists("[base]/map.dmm") || !fexists("[base]/state.json"))
		busy = FALSE
		return list("error" = "Save files could not be written")
	last_save = generation
	rustg_file_write(json_encode(list("generation" = generation, "saved_at" = time2text(world.realtime, "YYYY-MM-DD hh:mm:ss"), "objects" = length(records))), "data/babylon/saves/latest.json")
	to_chat(world, span_notice("Babylon saved: [generation]."))
	return list("ok" = TRUE, "generation" = generation, "objects" = length(records), "capture_ms" = checkpoint_capture_ms, "total_ms" = (REALTIMEOFDAY - checkpoint_started) * 100)

/datum/babylon_save/proc/restore_world()
	if(!fexists("data/babylon/resume-state.json"))
		return
	var/list/state = resume_data || json_decode(file2text("data/babylon/resume-state.json"))
	var/list/sun = state["sun"]
	if(sun)
		SSsun.azimuth = sun["azimuth"]
		SSsun.azimuth_mod = sun["azimuth_mod"]
		SSsun.base_rotation = sun["base_rotation"]
	next_id = state["next_id"]
	save_count = state["save_count"] || 0
	last_save = state["generation"]
	var/list/records = state["records"]
	for(var/atom/thing in world)
		if(thing.babylon_save_id)
			restored_atoms[thing.babylon_save_id] = thing
	var/list/used_children = list()
	for(var/list/record as anything in records)
		var/save_id = record["id"]
		var/atom/thing = restored_atoms[save_id]
		if(record["parent"])
			var/atom/parent = restored_atoms[record["parent"]]
			if(!parent)
				continue
			var/path = text2path(record["type"])
			for(var/obj/candidate in parent.contents)
				if(candidate.type == path && !(candidate in used_children))
					thing = candidate
					break
			if(!thing)
				thing = new path(parent)
			else if(thing.loc != parent)
				var/atom/movable/child = thing
				child.forceMove(parent)
			used_children += thing
			thing.babylon_save_id = save_id
			restored_atoms[save_id] = thing
		if(!thing)
			continue
		var/list/fields = record["fields"]
		for(var/field in fields)
			if(field in thing.vars)
				thing.vars[field] = decode_value(fields[field])
		if(record["wires"] && thing.wires)
			var/list/wire_data = record["wires"]
			thing.wires.colors = wire_data["colors"]
			thing.wires.cut_wires = wire_data["cut_wires"]
		if(istype(thing, /obj/machinery/power/apc) && !record["has_terminal"])
			var/obj/machinery/power/apc/apc = thing
			QDEL_NULL(apc.terminal)
		if(thing.reagents && ("reagents" in record))
			thing.reagents.clear_reagents()
			for(var/list/chem as anything in record["reagents"])
				thing.reagents.add_reagent(text2path(chem["type"]), chem["volume"], added_purity = chem["purity"], no_react = TRUE)
		CHECK_TICK
	// Remove regenerated default inventory which was not in the saved inventory.
	for(var/list/record as anything in records)
		var/atom/thing = restored_atoms[record["id"]]
		if(!thing)
			continue
		if(istype(thing, /obj/item) || istype(thing, /obj/machinery) || istype(thing, /mob/living/basic/drone))
			for(var/obj/item/extra in thing.contents.Copy())
				if(!(extra in used_children))
					qdel(extra)
		var/list/references = record["references"]
		for(var/field in references)
			if(field in thing.vars)
				if(field != "connected_sensor")
					thing.vars[field] = decode_value(references[field])
		if((istype(thing, /obj/structure/frame/computer) || istype(thing, /obj/machinery)) && ("circuit" in thing.vars))
			var/obj/item/circuitboard/board = thing.vars["circuit"]
			if(QDELETED(board) || board.loc != thing)
				// Legacy saves retained the board as a child but omitted the
				// frame/machine's circuit reference. Preserve the construction
				// stage: circuit_added() would reset an already wired frame.
				thing.vars["circuit"] = null
				for(var/obj/item/circuitboard/candidate in thing.contents)
					if(!QDELETED(candidate) && (candidate in used_children))
						thing.vars["circuit"] = candidate
						break
		if(istype(thing, /obj/machinery/airalarm) && references["connected_sensor"])
			var/obj/machinery/airalarm/alarm = thing
			var/obj/machinery/air_sensor/sensor = decode_value(references["connected_sensor"])
			if(sensor && alarm.connected_sensor != sensor)
				if(alarm.connected_sensor)
					alarm.disconnect_sensor()
				alarm.connect_sensor(sensor)
		if(istype(thing, /obj/machinery))
			var/obj/machinery/machine = thing
			if(length(record["parts"]))
				var/list/parts = list()
				for(var/list/part as anything in record["parts"])
					if(part["path"])
						var/partpath = text2path(part["path"])
						parts += new partpath()
					else
						var/atom/part_atom = decode_value(part)
						if(part_atom)
							parts += part_atom
				machine.component_parts = parts
				machine.RefreshParts()
			// RefreshParts may reset operating settings. Reapply the snapshot
			// afterwards; connectivity was already restored by the map preloader.
			var/list/fields = record["fields"]
			for(var/field in fields)
				if(field in thing.vars)
					thing.vars[field] = decode_value(fields[field])
			if(record["materials"] && ("materials" in machine.vars))
				var/datum/material_container/mats = material_container(machine)
				if(istype(machine.vars["materials"], /datum/remote_materials))
					var/datum/remote_materials/remote = machine.vars["materials"]
					mats = remote.babylon_restore_container(restored_atoms[record["material_silo"]])
				if(istype(mats))
					for(var/matpath in record["materials"])
						var/datum/material/material = SSmaterials.get_material(text2path(matpath))
						if(istype(material))
							mats.materials[material] = record["materials"][matpath]
			machine.power_change()
		if(istype(thing, /obj/item/modular_computer) && record["programs"])
			var/obj/item/modular_computer/computer = thing
			for(var/program_type in record["programs"])
				var/path = text2path(program_type)
				var/datum/computer_file/program = new path()
				if(!computer.find_file_by_name(program.filename))
					computer.store_file(program)
				else
					qdel(program)
		if(istype(thing, /obj/machinery/atmospherics/components/unary/vent_pump))
			var/obj/machinery/atmospherics/components/unary/vent_pump/vent = thing
			vent.disconnect_from_area(vent.assigned_area)
			var/area/assigned = ("assigned_area" in record) ? locate(text2path(record["assigned_area"])) : get_area(vent)
			if(assigned)
				vent.assign_to_area(assigned)
		if(istype(thing, /obj/machinery/atmospherics/components/unary/vent_scrubber))
			var/obj/machinery/atmospherics/components/unary/vent_scrubber/scrubber = thing
			scrubber.disconnect_from_area(scrubber.assigned_area)
			var/area/assigned = ("assigned_area" in record) ? locate(text2path(record["assigned_area"])) : get_area(scrubber)
			if(assigned)
				scrubber.assign_to_area(assigned)
		if((state["version"] || 1) < 2)
			recover_legacy(thing, record)
		// update_icon() drops an atom's managed vis overlays and expects update_overlays() to add
		// them again. Objects that make theirs only in Initialize (holobarriers, plastic flaps)
		// kept alpha 0 without their overlay: invisible, though named and attackable.
		var/list/vis_overlays = thing.managed_vis_overlays?.Copy()
		thing.update_appearance()
		if(length(vis_overlays) && !length(thing.managed_vis_overlays) && ismovable(thing))
			var/atom/movable/shown = thing
			for(var/obj/effect/overlay/vis/overlay as anything in vis_overlays)
				if(QDELETED(overlay))
					continue
				shown.vis_contents += overlay
				LAZYADD(shown.managed_vis_overlays, overlay)
		// Rendering order is runtime-editable and update_appearance may reset it.
		for(var/field in list("layer", "plane", "pixel_x", "pixel_y", "pixel_z", "alpha"))
			if((field in record["fields"]) && (field in thing.vars))
				thing.vars[field] = decode_value(record["fields"][field])
		CHECK_TICK
	// Restore gases only after parts and network topology are complete.
	// copy_from preserves volume; version 2 also stores the actual volume.
	for(var/list/record as anything in records)
		var/atom/thing = restored_atoms[record["id"]]
		if(!thing)
			continue
		for(var/field in list("air_contents", "air1", "air2", "air3", "absorbed_gasmix"))
			if(record[field] && (field in thing.vars))
				var/datum/gas_mixture/mix = thing.vars[field]
				if(istype(mix))
					restore_gas(mix, record[field])
		if(record["pipeline_gas"] && istype(thing, /obj/machinery/atmospherics/pipe))
			var/obj/machinery/atmospherics/pipe/pipe = thing
			restore_gas(pipe.parent?.air, record["pipeline_gas"])
		if(record["device_airs"] && istype(thing, /obj/machinery/atmospherics/components))
			var/obj/machinery/atmospherics/components/device = thing
			var/list/airs = record["device_airs"]
			for(var/index in 1 to min(length(airs), length(device.airs)))
				var/datum/gas_mixture/mix = device.airs[index]
				restore_gas(mix, airs[index])
		CHECK_TICK
	for(var/list/record as anything in state["turfs"])
		var/turf/tile = locate(record["x"], record["y"], station_z)
		tile.temperature = record["temperature"]
		if(record["gas"] && isopenturf(tile))
			var/turf/open/open = tile
			restore_gas(open.return_air(), record["gas"])
		CHECK_TICK
	restore_portable_connections(records)
	SSmachines.makepowernets()
	restore_airlock_configuration(state)
	// Door animations and their sleeping procs cannot survive a process restart.
	// Settle at the saved physical position, then rebuild pump links without
	// running set_links' fresh-install open/close animations over the snapshot.
	for(var/list/record as anything in records)
		var/atom/thing = restored_atoms[record["id"]]
		if(istype(thing, /obj/machinery/door/airlock))
			var/obj/machinery/door/airlock/door = thing
			door.operating = FALSE
			door.delayed_close_requested = FALSE
			door.set_airlock_state(door.density ? AIRLOCK_CLOSED : AIRLOCK_OPEN)
			door.set_opacity(door.density && !door.glass)
			if(door.filler)
				door.filler.set_density(door.density)
				door.filler.set_opacity(door.opacity)
			if(door.density)
				door.flags_1 |= PREVENT_CLICK_UNDER_1
			else
				door.flags_1 &= ~PREVENT_CLICK_UNDER_1
			door.air_update_turf(TRUE, FALSE)
			if(!door.density && door.autoclose)
				door.autoclose_in(8 SECONDS)
		if(istype(thing, /obj/machinery/airalarm) && record["alarm_thresholds"])
			var/obj/machinery/airalarm/alarm = thing
			for(var/list/saved as anything in record["alarm_thresholds"])
				var/key = decode_value(saved["key"])
				var/threshold_type = text2path(saved["type"])
				var/datum/tlv/threshold = new threshold_type()
				for(var/field in list("warning_min", "warning_max", "hazard_min", "hazard_max"))
					threshold.vars[field] = saved[field]
				qdel(alarm.tlv_collection[key])
				alarm.tlv_collection[key] = threshold
			if(record["alarm_mode"])
				alarm.select_mode(alarm, text2path(record["alarm_mode"]), should_apply = FALSE)
		if(istype(thing, /obj/machinery/atmospherics/components/unary/airlock_pump))
			restore_cycle_pump(thing, record)

	for(var/list/record as anything in records)
		var/atom/thing = restored_atoms[record["id"]]
		if(istype(thing, /obj/machinery/power/solar_control))
			var/obj/machinery/power/solar_control/control = thing
			if("solar_panels" in record)
				var/list/panels = decode_value(record["solar_panels"])
				for(var/obj/machinery/power/solar/panel as anything in panels)
					panel.set_control(control)
				var/obj/machinery/power/tracker/tracker = decode_value(record["solar_tracker"])
				if(tracker)
					tracker.set_control(control)
			else
				control.search_for_connected()
			if("track" in record["fields"])
				control.track = record["fields"]["track"]
		if(istype(thing, /obj/item/modular_computer) && record["active_program"])
			programs_to_resume[thing] = record
	var/list/players = state["players"]
	if(!players)
		var/list/legacy_player = state["player"] || list()
		legacy_player["builder"] = state["builder"]
		players = list()
		players[owner_ckey] = legacy_player
	for(var/player_key in players)
		var/datum/babylon_save/player = player_sessions[player_key]
		if(!player)
			player = new
			player.owner_ckey = player_key
			player_sessions[player_key] = player
		restore_player(player, players[player_key])
	var/datum/techweb/science/research = locate(/datum/techweb/science) in SSresearch.techwebs
	var/list/research_data = state["research"]
	if(research && research_data)
		for(var/node in research_data["nodes"])
			research.research_node_id(node, TRUE, FALSE, FALSE)
		for(var/design in research_data["designs"])
			research.add_design_by_id(design)
		research.research_points = research_data["points"]
		research.recalculate_nodes()
		// research_points is the progress towards the saved target (research.dm). Older saves
		// have no target, so their banked points are dropped; an invalid target is cleared.
		research.babylon_target = research_data["target"]
		research.babylon_target_by = research_data["target_by"]
		research.babylon_target_location = research_data["target_location"]
		research.babylon_try_finish()
	GLOB.babylon_lore.restore(state["lore"])
	if((state["version"] || 1) < 7)
		restore_lost_supermatter()
	to_chat(world, span_notice("Babylon resumed from [last_save]."))

/// Saves before version 7 dropped the supermatter shard from the engine's secure crate, which
/// makes progression impossible. Such a world without any crystal gets the shard back there.
/// Only older saves are repaired: a crystal lost in play afterwards stays lost.
/datum/babylon_save/proc/restore_lost_supermatter()
	if(length(SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/power/supermatter_crystal)))
		return
	var/atom/destination
	var/list/engine = get_area_turfs(/area/ruin/space/bb13/engineering/engine, station_z)
	for(var/turf/tile as anything in engine)
		destination = locate(/obj/structure/closet/crate/secure/engineering) in tile
		if(destination)
			break
	if(!destination)
		for(var/turf/open/tile in engine)
			if(!tile.is_blocked_turf(TRUE))
				destination = tile
				break
	if(!destination)
		migration_notes |= "The supermatter shard was missing and no place in the engine room was free to return it."
		return
	var/obj/machinery/power/supermatter_crystal/shard/shard = new(destination)
	shard.warning_channel = null
	migration_notes |= "Returned the supermatter shard that older saves dropped from the engine's secure crate."
	log_world("Babylon: returned the lost supermatter shard to [destination] ([destination.x],[destination.y],[destination.z]).")

// Group membership is derived from the saved IDs after every door exists.
// Do not rely solely on the cached close_others list from a previous world.
/datum/babylon_save/proc/restore_portable_connections(list/records)
	// Both sides and their pipe networks/gases must exist before connect().
	// The native path also restores anchoring, offsets and atmos processing.
	for(var/list/record as anything in records)
		var/obj/machinery/portable_atmospherics/portable = restored_atoms[record["id"]]
		if(!istype(portable))
			continue
		var/obj/machinery/atmospherics/components/unary/portables_connector/port
		if("portable_port" in record)
			port = decode_value(record["portable_port"])
		else if(portable.anchored)
			// Before this field was saved, wrenching left only the anchored
			// flag. Recover a matching free connector on that same tile.
			for(var/obj/machinery/atmospherics/components/unary/portables_connector/candidate in get_turf(portable))
				if(!candidate.connected_device)
					port = candidate
					break
		if(!istype(port) || port.loc != get_turf(portable) || port.connected_device)
			continue
		if(portable.connect(port) && !("portable_port" in record))
			migration_notes |= "Recovered anchored portable-atmos connector attachment from legacy save."

/datum/babylon_save/proc/restore_cycle_pump(obj/machinery/atmospherics/components/unary/airlock_pump/pump, list/record)
	var/list/settings = record["cycle_settings"]
	if(settings)
		for(var/field in settings)
			pump.vars[field] = decode_value(settings[field])
		pump.internal_airlocks = decode_value(record["cycle_internal"]) || list()
		pump.external_airlocks = decode_value(record["cycle_external"]) || list()
	else
		// Older checkpoints lack pump settings. Find the existing pair without
		// closing the outer/opening the inner door as if installing a new pump.
		var/perpendicular_dirs = NSCOMPONENT(pump.dir) ? WEST|EAST : NORTH|SOUTH
		pump.internal_airlocks = pump.get_adjacent_airlocks(pump.find_density(get_turf(pump), pump.dir), perpendicular_dirs)
		pump.external_airlocks = pump.get_adjacent_airlocks(pump.find_density(get_turf(pump), REVERSE_DIR(pump.dir)), perpendicular_dirs)
		if(!length(pump.internal_airlocks))
			for(var/obj/machinery/door/airlock/door as anything in pump.external_airlocks)
				pump.internal_airlocks |= door.close_others
			pump.internal_airlocks -= pump.external_airlocks
		if(!length(pump.external_airlocks))
			for(var/obj/machinery/door/airlock/door as anything in pump.internal_airlocks)
				pump.external_airlocks |= door.close_others
			pump.external_airlocks -= pump.internal_airlocks
		pump.cycling_set_up = length(pump.internal_airlocks) && length(pump.external_airlocks)
		// The original Babylon wreck has no airlock pumps. Legacy pumps were
		// player-built; map loading incorrectly made them permanently secured.
		pump.can_unwrench = TRUE
		migration_notes |= "Recovered removable player-built airlock pump from legacy save."
	for(var/obj/machinery/door/airlock/door as anything in (pump.internal_airlocks + pump.external_airlocks))
		door.set_cycle_pump(pump)
		pump.RegisterSignal(door, COMSIG_QDELETING, TYPE_PROC_REF(/obj/machinery/atmospherics/components/unary/airlock_pump, unlink_airlock))
	pump.airlocks_animating = FALSE
	pump.check_turfs()
	if(pump.on && pump.cycling_set_up)
		if(isnull(pump.cycle_pressure_target))
			pump.cycle_pressure_target = pump.pump_direction == ATMOS_DIRECTION_RELEASING ? pump.internal_pressure_target : pump.external_pressure_target
		pump.emergency_stop_timer = addtimer(CALLBACK(pump, TYPE_PROC_REF(/obj/machinery/atmospherics/components/unary/airlock_pump, emergency_stop)), record["cycle_remaining"] || pump.cycle_timeout, TIMER_STOPPABLE|TIMER_UNIQUE|TIMER_OVERRIDE|TIMER_DELETE_ME)
	pump.update_appearance()

/datum/babylon_save/proc/restore_airlock_configuration(list/state)
	var/list/doors = list()
	for(var/list/record as anything in state["records"])
		var/obj/machinery/door/airlock/door = restored_atoms[record["id"]]
		if(istype(door))
			doors += door
	for(var/obj/machinery/door/airlock/door as anything in doors)
		if(door.closeOtherId)
			door.close_others = list()
		var/obj/item/electronics/airlock/electronics = door.electronics
		if(!electronics)
			continue
		var/list/fields = resume_records[electronics.babylon_save_id]?["fields"]
		// Old running builds already save the effective door name, access,
		// and group; infer missing board settings from that completed door.
		if(!fields || !("passed_name" in fields))
			electronics.passed_name = door.name
		if(!fields || !("passed_cycle_id" in fields))
			electronics.passed_cycle_id = door.closeOtherId
		if(!fields || !("one_access" in fields))
			electronics.one_access = !!length(door.req_one_access)
			electronics.accesses = electronics.one_access ? door.req_one_access.Copy() : (door.req_access?.Copy() || list())
		if(!fields || !("unres_sides" in fields))
			electronics.unres_sides = door.unres_sides
	for(var/obj/machinery/door/airlock/door as anything in doors)
		if(door.closeOtherId)
			door.update_other_id()
		if(door.cyclelinkeddir && !door.cyclelinkedairlock)
			door.cyclelinkairlock()

/datum/babylon_save/proc/recover_legacy(atom/thing, list/record)
	if(istype(thing, /obj/machinery/power/emitter))
		var/obj/machinery/power/emitter/emitter = thing
		emitter.active = FALSE
	if(istype(thing, /obj/machinery/power/supermatter_crystal))
		var/obj/machinery/power/supermatter_crystal/crystal = thing
		crystal.internal_energy = 0
		migration_notes |= "Legacy save did not contain crystal energy or emitter on/off state. Reactor recovered shut down."
	if(istype(thing, /obj/machinery/atmospherics/components/trinary/filter))
		var/obj/machinery/atmospherics/components/trinary/filter/filter = thing
		var/list/airs = record["device_airs"]
		if(length(airs) >= 2 && istext(airs[2]))
			var/datum/gas_mixture/output = SSair.parse_gas_string(airs[2])
			var/dominant
			var/highest = 0
			for(var/gas_type, amount in output.moles)
				if(amount > highest)
					highest = amount
					dominant = gas_type
			if(dominant)
				filter.filter_type = list(dominant)
				migration_notes |= "Legacy filter selections recovered from their saved output gases; verify before reactor startup."
