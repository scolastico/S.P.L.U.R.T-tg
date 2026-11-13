// Babylon's players are drones; no one joins as a pAI or a station AI and ghosts cannot take
// either over. Everything that only exists to house one is removed from Babylon worlds:
// pAI cards (mapped in the starting wreck, printable, sold by the PDA vendor, maintenance
// loot) and AI cores (plasteel recipe, core board). Older saves lose theirs at load.
// The Soulcatcher's "Enter Soulcatcher" ghost button goes too: nothing can be played there.

/// Research designs that only build a pAI or an AI core.
/proc/babylon_unplayable_design(datum/design/design)
	var/static/list/unplayable = typecacheof(list(/obj/item/pai_card, /obj/item/circuitboard/aicore))
	return istype(design) && ispath(design.build_path) && is_type_in_typecache(design.build_path, unplayable)

// Research: removed with the other designs Babylon has no use for (research.dm).

// Plasteel: no "AI core" recipe.
/obj/item/stack/sheet/plasteel/get_main_recipes()
	var/list/recipes = ..()
	for(var/datum/stack_recipe/recipe in recipes.Copy())
		if(ispath(recipe.result_type, /obj/structure/ai_core))
			recipes -= recipe
	return recipes

// The PDA vendor's premium pAI cards.
/obj/machinery/vending/modularpc/Initialize(mapload)
	premium -= /obj/item/pai_card
	return ..()

// Whatever still creates one (the wreck, older saves, loot tables, gifts) gets nothing.
/obj/item/pai_card/Initialize(mapload)
	. = ..()
	return INITIALIZE_HINT_QDEL

/obj/structure/ai_core/Initialize(mapload)
	. = ..()
	return INITIALIZE_HINT_QDEL

/datum/action/innate/join_soulcatcher/Grant(mob/grant_to)
	return
