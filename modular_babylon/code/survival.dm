// Babylon survival: hunger and thirst are lethal for living crew. Upstream
// only slows a starving human down; here a grown body has to be kept fed and
// watered, which is what the inner vault interlock asks players to prove.

/// Damage per second at zero nutrition or zero water; ramps up from zero at the threshold.
#define BABYLON_NEED_DAMAGE_PER_SECOND 0.25
#define BABYLON_NEED_WARNING_INTERVAL (30 SECONDS)

/mob/living/carbon/human
	var/babylon_need_warning_at = 0

/datum/babylon_save/proc/tick_survival()
	for(var/mob/living/carbon/human/person as anything in GLOB.human_list)
		if(QDELETED(person) || person.stat == DEAD || person.z != station_z)
			continue
		var/list/complaints = list()
		if(!HAS_TRAIT(person, TRAIT_NOHUNGER) && person.nutrition < NUTRITION_LEVEL_STARVING)
			var/severity = 1 - clamp(person.nutrition / NUTRITION_LEVEL_STARVING, 0, 1)
			person.adjust_brute_loss(BABYLON_NEED_DAMAGE_PER_SECOND * severity, updating_health = TRUE, forced = TRUE)
			complaints += "starving"
		if(!HAS_TRAIT(person, TRAIT_NOTHIRST) && person.water_level < THIRST_LEVEL_PARCHED)
			var/severity = 1 - clamp(person.water_level / THIRST_LEVEL_PARCHED, 0, 1)
			person.adjust_tox_loss(BABYLON_NEED_DAMAGE_PER_SECOND * severity, updating_health = TRUE, forced = TRUE)
			complaints += "dehydrated"
		if(length(complaints) && world.time - person.babylon_need_warning_at >= BABYLON_NEED_WARNING_INTERVAL)
			person.babylon_need_warning_at = world.time
			to_chat(person, span_userdanger("You are [complaints.Join(" and ")]. Your body is failing. Eat and drink, or the watchdog will have to catch you."))

#undef BABYLON_NEED_DAMAGE_PER_SECOND
#undef BABYLON_NEED_WARNING_INTERVAL
