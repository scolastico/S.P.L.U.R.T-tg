// Isolated local Babylon builder. Compiled only into babylon.dmb.
GLOBAL_DATUM_INIT(babylon_save, /datum/babylon_save, new)

/world
	maxx = 255
	maxy = 255
	maxz = 1
	sleep_offline = FALSE

/datum/controller/master
	sleep_offline_after_initializations = FALSE

// This standalone building session has no random encounters or event tracks.
/datum/controller/subsystem/events
	ss_flags = SS_NO_FIRE

/datum/controller/subsystem/gamemode
	ss_flags = SS_NO_FIRE

/atom
	var/babylon_save_id = null

/datum/babylon_save
	var/ready = FALSE
	var/busy = FALSE
	var/last_save = null
	var/boot_error = null
	var/save_count = 0
	var/next_id = 1
	var/station_z
	var/owner_ckey
	var/mob/living/basic/drone/babylon/builder
	var/list/restored_atoms = list()
	var/list/resume_data
	var/list/resume_records = list()
	var/list/migration_notes = list()
	var/prepared = FALSE
	var/checkpoint_processing
	var/checkpoint_started
	var/checkpoint_capture_ms = 0
	var/list/programs_to_resume = list()
	var/list/capture_fields_by_type = list()
	var/list/metadata_fields_by_type = list()
	var/next_autosave_at = 0
	var/autosave_countdown_active = FALSE
	var/list/autosave_notices = list()
	var/turf/respawn_turf
	var/respawn_pending = FALSE
	var/respawn_ready_at = 0
	var/list/drone_profile = list()
	var/datum/action/babylon_self_destruct/destruct_action
	var/datum/action/babylon_respawn/respawn_action
	var/list/structural_fields = list("dir", "name", "pixel_x", "pixel_y", "pixel_z", "layer", "plane", "alpha", "anchored", "density", "opacity", "amount", "icon_state", "cable_layer", "cable_color", "linked_dirs", "banned_links", "piping_layer", "pipe_color", "initialize_directions", "flipped", "welded", "hide", "id_tag", "door_id", "mineral", "glass", "heat_proof_finished", "state", "d_state", "req_access", "req_one_access", "closeOtherId", "pipe_layer", "p_init_dir")
	var/list/extra_fields = list("passed_name", "passed_cycle_id", "one_access", "unres_sides", "unres_latch", "shell", "autoclose", "normalspeed", "autoname", "cyclelinkeddir", "picked", "colour", "icon_living", "icon_dead", "track", "azimuth_target", "azimuth_current", "azimuth_rate", "power_tier", "needs_to_turn", "needs_to_update_solar_exposure", "chamber_id", "inlet_id", "outlet_id", "fan_overclocked", "active", "filter_type", "transfer_rate", "volume_rate", "flipped", "initialize_directions", "layer", "plane", "alpha", "pixel_z", "hide", "pump_direction", "pressure_checks", "external_pressure_bound", "internal_pressure_bound", "widenet", "research_disabled", "working", "internal_energy", "external_power_trickle", "external_power_immediate", "external_damage_immediate", "activation_logged", "absorption_ratio", "gas_percentage", "gas_heat_modifier", "gas_heat_resistance", "gas_powerloss_inhibition", "gas_power_transmission_rate", "gas_heat_power_generation", "waste_multiplier", "final_countdown", "disable_damage", "disable_gas", "disable_power_change", "production_speed", "closeOtherId", "pipe_layer", "p_init_dir", "color", "deconstruction_state", "disable_process", "damage", "power_transmission", "safeties", "direction", "accesses", "filter_types", "scrubbing", "fuel_type", "loading", "chargecount")
	var/list/state_fields = list("name", "desc", "dir", "pixel_x", "pixel_y", "density", "opacity", "anchored", "amount", "atom_integrity", "max_integrity", "panel_open", "opened", "locked", "welded", "bolts", "safe", "operating", "chargemode", "coverlocked", "has_electronics", "lighting", "equipment", "environ", "aidisabled", "shorted", "on", "enabled", "use_power", "target_pressure", "pressure_setting", "release_pressure", "valve_open", "input_level", "input_attempt", "output_level", "output_attempt", "charge", "maxcharge", "fuel", "lit", "welding", "max_fuel", "state", "d_state", "glass", "heat_proof_finished", "mineral", "created_name", "base_name", "cell_type", "cable_layer", "cable_color", "linked_dirs", "banned_links", "piping_layer", "pipe_color", "init_dir", "frequency", "id", "id_tag", "door_id", "siphoned_power", "siphon_max", "probability_mod", "health", "maxHealth", "real_name", "visualAppearance", "active_hand_index", "machine_stat", "stat", "mode", "temperature", "target_temperature", "thermostat", "build_type", "amount_per_transfer_from_this", "volume", "custom_price", "credits", "power_charge", "power_charge_max", "moles", "icon_state", "req_access", "req_one_access", "maximum_volume")
	var/list/reference_fields = list("cell", "electronics", "internal_storage", "head", "held_items", "stored_id", "inserted_disk", "connected_sensor", "cyclelinkedairlock", "close_others", "closeOther")
	var/list/list_fields = list("req_access", "req_one_access", "accesses", "filter_types", "filter_type", "scrubbing", "ore_chance", "gas_percentage")

// Apply saved physical configuration BEFORE Initialize creates cable/pipe nodes.
// Version 1 maps omitted these assignments due to an unparenthesized `in`.
