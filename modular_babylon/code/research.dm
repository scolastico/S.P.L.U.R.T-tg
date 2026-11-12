/*
 * Babylon research: no point bank and no queue.
 *
 * A techweb researches one node at a time. Selecting a node ("Research") makes it the target;
 * every point income (servers, experiments, anything through add_point_list) then goes
 * towards it, capped at its price, and research_points holds that progress. With no target,
 * income is discarded. Switching targets starts over, so points can never be banked.
 * Once the progress covers the price (and the node's required experiments are done), the
 * node is researched and the target is cleared. Overrides only; see UPSTREAM_HOOKS.md.
 */

/datum/techweb
	/// Babylon: id of the one node being researched, or null.
	var/babylon_target
	/// Who selected the target and where, for the research log once it is researched.
	var/babylon_target_by
	var/babylon_target_location

/// Selects the node to research; returns TRUE if it is (now) the target or was researched.
/datum/techweb/proc/babylon_select(id, mob/user, atom/research_source)
	var/datum/techweb_node/node = SSresearch.techweb_node_by_id(id)
	if(!node || researched_nodes[id] || !available_nodes[id] || hidden_nodes[id])
		return FALSE
	if(babylon_target == id)
		return TRUE
	babylon_target = id
	babylon_target_by = user ? "[user]" : "Unknown"
	var/atom/place = research_source || user
	babylon_target_location = place ? "[get_area(place)] ([place.x],[place.y],[place.z])" : "Unknown"
	babylon_reset_progress()
	babylon_try_finish(research_source)
	return TRUE

/datum/techweb/proc/babylon_reset_progress()
	if(!islist(research_points))
		research_points = list()
	for(var/type in SSresearch.point_types)
		research_points[type] = 0

/// Researches the target once its progress covers the price and its experiments are done.
/datum/techweb/proc/babylon_try_finish(atom/research_source)
	var/datum/techweb_node/node = babylon_target && SSresearch.techweb_node_by_id(babylon_target)
	if(!node || researched_nodes[babylon_target] || !available_nodes[babylon_target])
		babylon_target = null
		babylon_reset_progress()
		return FALSE
	if(!can_unlock_node(node))
		return FALSE
	babylon_target = null
	var/list/price = node.get_price(src)
	research_node(node, research_source = research_source)
	babylon_reset_progress()
	research_logs += list(list(
		"node_name" = node.display_name,
		"node_cost" = price[TECHWEB_POINT_TYPE_GENERIC] || 0,
		"node_researcher" = babylon_target_by || "Unknown",
		"node_research_location" = babylon_target_location || "Unknown",
	))
	return TRUE

/// All point income: towards the target, capped at what it still needs; otherwise discarded.
/datum/techweb/add_point_list(list/pointlist)
	var/datum/techweb_node/node = babylon_target && SSresearch.techweb_node_by_id(babylon_target)
	if(!node)
		// Also clears a balance from before Babylon's rules (new techweb, older saves); the
		// research tick calls this every few seconds.
		babylon_reset_progress()
		return
	var/list/price = node.get_price(src)
	var/list/towards_target = list()
	for(var/type in pointlist)
		var/still_needed = (price[type] || 0) - (research_points[type] || 0)
		if(still_needed > 0)
			towards_target[type] = min(pointlist[type], still_needed)
	. = ..(towards_target)
	babylon_try_finish()

/// A finished experiment can be the last requirement of the target.
/datum/techweb/complete_experiment(datum/experiment/completed_experiment)
	. = ..()
	babylon_try_finish()

/// No research queue.
/datum/techweb/enqueue_node(id, mob/user)
	return FALSE

// The console and the PDA app select the node instead of buying it with banked points.
/obj/machinery/computer/rdconsole/research_node(id, mob/user)
	if(!stored_research?.babylon_select(id, user, src))
		say("This node cannot be researched right now.")
		return FALSE
	return TRUE

/datum/computer_file/program/science/research_node(id, mob/user)
	return !!stored_research?.babylon_select(id, user, computer)

/obj/machinery/computer/rdconsole/ui_data(mob/user)
	. = ..()
	if(stored_research)
		.["babylon_research"] = list("target" = stored_research.babylon_target || "")

/datum/computer_file/program/science/ui_data(mob/user)
	. = ..()
	if(stored_research)
		.["babylon_research"] = list("target" = stored_research.babylon_target || "")
