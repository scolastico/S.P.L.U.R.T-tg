// Babylon's players are drones; no one joins as a pAI, a station AI or a cyborg/mech brain,
// and ghosts cannot take any of them over. Everything that only exists to house one is
// removed from Babylon worlds: pAI cards (mapped in the starting wreck, printable, sold by
// the PDA vendor, maintenance loot), AI cores (plasteel recipe, core board), and MMIs and
// positronic brains (mech fabricator). Older saves lose theirs at load. They may return
// later with a Babylon way in (moving a drone's mind) instead of ghosts.
// The Soulcatcher's "Enter Soulcatcher" ghost button goes too: nothing can be played there.

/// Research designs that only build a pAI, an AI core, an MMI or a positronic brain.
/proc/babylon_unplayable_design(datum/design/design)
	var/static/list/unplayable = typecacheof(list(/obj/item/pai_card, /obj/item/circuitboard/aicore, /obj/item/mmi))
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

// MMIs and positronic brains, except those that are part of a mob or an organ (a cyborg
// creates its own, a synthetic's brain organ holds one): deleting those would break them.
/obj/item/mmi/Initialize(mapload)
	. = ..()
	if(!ismob(loc) && !isorgan(loc))
		return INITIALIZE_HINT_QDEL

/datum/action/innate/join_soulcatcher/Grant(mob/grant_to)
	return
