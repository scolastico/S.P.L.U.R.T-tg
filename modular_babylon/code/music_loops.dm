/*
 * Loop sets: a subfolder of a mood folder (music/space/drifting/) with an index.json. Instead
 * of one finished track it holds loops (stems) that the game layers into a track of its own:
 * a few loops play at once, each repeating, and every so often one joins, leaves or is swapped.
 * In the mood's rotation a loop set counts as one entry, next to the plain tracks.
 *
 * index.json (every key optional; times in seconds, a range as {"min": a, "max": b} or a number):
 *   title           name shown in the status tab (default: the folder name)
 *   weight          chance against the mood's other entries; plain tracks weigh 1 (default 1)
 *   layers          loops playing at once (default 1; at most BABYLON_LOOP_MAX_LAYERS)
 *   duration        how long the set plays before the mood picks again (default 180-300)
 *   change_every    time between changes of the playing loops (default 30-60)
 *   overlap         seconds a joining loop fades in while a leaving one fades out; 0 cuts
 *                   (default 4)
 *   sync            loops stay on the beat: a joining loop starts where it would be had it
 *                   played from the beginning (default true; false starts it from its start)
 *   always          loops that play the whole time (["pad.ogg"])
 *   never_together  groups of which at most one loop plays at a time ([["drums_a.ogg", "drums_b.ogg"]])
 *   loops           per loop: {"lead.ogg": {"volume": 70, "weight": 2}}; volume 0-100 (default
 *                   100), weight its chance to be picked (default 1, 0 = only through always)
 *   intro, outro    played once before the loops start and as they fade out at the end
 * Every other audio file in the folder is a loop. Problems are logged at world start; a set
 * whose index.json cannot be read or that holds no loops is skipped.
 */

/// Sound channels reserved for the loops of one player: two per layer, so a leaving and a
/// joining loop can overlap.
#define BABYLON_LOOP_MAX_LAYERS 6
#define BABYLON_LOOP_CHANNELS (BABYLON_LOOP_MAX_LAYERS * 2)
/// Fades change the volume this often (deciseconds).
#define BABYLON_LOOP_FADE_STEP 2

/datum/babylon_music
	/// Channels the loop sets play on, reserved when the first loop set is found.
	var/list/loop_channels

/// Loads the loop set in a mood's subfolder; added to the mood when it can play.
/datum/babylon_music/proc/load_loop_set(mood, folder_path)
	var/datum/babylon_loop_set/loop_set = new
	var/loaded = loop_set.load(folder_path)
	for(var/error in loop_set.errors)
		log_world("Babylon music: [folder_path]index.json: [error][loaded ? "" : "; the loop set is skipped"].")
	if(!loaded)
		return
	if(isnull(loop_channels))
		loop_channels = list()
		for(var/i in 1 to BABYLON_LOOP_CHANNELS)
			var/channel = SSsounds.reserve_sound_channel()
			if(channel)
				loop_channels += channel
	if(!tracks[mood])
		tracks[mood] = list()
	tracks[mood] += loop_set

/// A sound file's length in deciseconds, or 0 when unknown.
/proc/babylon_music_length(path)
	try
		return max(0, rustg_sound_length(path))
	catch
		return 0

/proc/babylon_music_audio(file_name)
	var/extension = LOWER_TEXT(copytext(file_name, findlasttext(file_name, ".") + 1))
	return extension in list("ogg", "mp3", "wav")

/datum/babylon_loop_set
	/// The folder, with a trailing slash.
	var/path
	var/title
	var/weight = 1
	/// Loop file -> volume (0-100).
	var/list/loops = list()
	/// Loop file -> chance to be picked; 0 only plays through always.
	var/list/loop_weights = list()
	var/list/always = list()
	/// Lists of loops of which at most one plays at a time.
	var/list/never_together = list()
	var/layers_min = 1
	var/layers_max = 1
	var/duration_min = 180 SECONDS
	var/duration_max = 300 SECONDS
	var/change_min = 30 SECONDS
	var/change_max = 60 SECONDS
	var/overlap = 4 SECONDS
	var/sync = TRUE
	var/intro
	var/outro
	/// What index.json got wrong, for the world log.
	var/list/errors = list()

/// Reads the folder and its index.json; FALSE when the set cannot play.
/datum/babylon_loop_set/proc/load(folder_path)
	path = folder_path
	var/folder_name = copytext(path, 1, length(path))
	title = babylon_music_title(copytext(folder_name, findlasttext(folder_name, "/") + 1))
	var/list/index
	try
		index = json_decode(file2text("[path]index.json"))
	catch(var/exception/error)
		errors += "not valid JSON ([error.name])"
		return FALSE
	if(!islist(index))
		errors += "must hold a JSON object"
		return FALSE
	if(istext(index["title"]) && length(trim(index["title"])))
		title = trim(index["title"])
	weight = round(setting(index, "weight", 1))
	intro = named_file(index, "intro")
	outro = named_file(index, "outro")
	var/list/loop_settings = islist(index["loops"]) ? index["loops"] : list()
	for(var/entry in flist(path))
		var/file_path = "[path][entry]"
		if(copytext(entry, -1) == "/" || !babylon_music_audio(entry) || file_path == intro || file_path == outro)
			continue
		var/list/own = islist(loop_settings[entry]) ? loop_settings[entry] : list()
		loops[file_path] = clamp(setting(own, "volume", 100, "[entry] volume"), 0, 100)
		loop_weights[file_path] = round(setting(own, "weight", 1, "[entry] weight"))
	for(var/entry in loop_settings)
		if(!("[path][entry]" in loops))
			errors += "loops: [entry] is not a loop in this folder"
	if(!length(loops))
		errors += "the folder holds no loops (.ogg, .mp3, .wav)"
		return FALSE
	var/list/layers = range_setting(index, "layers", 1, 1, 1)
	layers_max = clamp(round(layers[2]), 1, min(BABYLON_LOOP_MAX_LAYERS, length(loops)))
	layers_min = clamp(round(layers[1]), 1, layers_max)
	var/list/duration = range_setting(index, "duration", 180, 300, 1 SECONDS)
	duration_min = max(10 SECONDS, duration[1])
	duration_max = max(duration_min, duration[2])
	var/list/change = range_setting(index, "change_every", 30, 60, 1 SECONDS)
	change_min = max(1 SECONDS, change[1])
	change_max = max(change_min, change[2])
	overlap = setting(index, "overlap", 4) * (1 SECONDS)
	sync = isnull(index["sync"]) ? TRUE : !!index["sync"]
	for(var/entry in listify(index["always"], "always"))
		var/file_path = "[path][entry]"
		if(file_path in loops)
			always |= file_path
		else
			errors += "always: [entry] is not a loop in this folder"
	for(var/group in listify(index["never_together"], "never_together"))
		var/list/members = list()
		for(var/entry in listify(group, "never_together"))
			if("[path][entry]" in loops)
				members |= "[path][entry]"
			else
				errors += "never_together: [entry] is not a loop in this folder"
		if(length(members) > 1)
			never_together += list(members)
	for(var/loop in always)
		if(conflicts(loop, always))
			errors += "always: [babylon_music_title(loop)] is in a never_together group with another always loop"
			return FALSE
	if(length(always) > layers_max)
		layers_max = min(length(always), BABYLON_LOOP_MAX_LAYERS)
		layers_min = min(layers_min, layers_max)
		errors += "layers: more always loops than layers; playing up to [layers_max]"
	return TRUE

/// A number from index.json, at least 0, or the fallback.
/datum/babylon_loop_set/proc/setting(list/values, key, fallback, label = key)
	var/value = values[key]
	if(isnull(value))
		return fallback
	if(!isnum(value) || value < 0)
		errors += "[label] must be a number of at least 0"
		return fallback
	return value

/// list(min, max) from {"min": a, "max": b} or a single number, times scale.
/datum/babylon_loop_set/proc/range_setting(list/values, key, fallback_min, fallback_max, scale)
	var/value = values[key]
	var/low = fallback_min
	var/high = fallback_max
	if(isnum(value))
		low = value
		high = value
	else if(islist(value))
		low = isnull(value["min"]) ? (isnull(value["max"]) ? fallback_min : value["max"]) : value["min"]
		high = isnull(value["max"]) ? low : value["max"]
	else if(!isnull(value))
		errors += "[key] must be a number or {\"min\": ..., \"max\": ...}"
	if(!isnum(low) || !isnum(high) || low < 0 || high < low)
		errors += "[key] needs numbers with 0 <= min <= max"
		low = fallback_min
		high = fallback_max
	return list(low * scale, high * scale)

/datum/babylon_loop_set/proc/listify(value, key)
	if(isnull(value))
		return list()
	if(!islist(value))
		errors += "[key] must be a list"
		return list()
	return value

/datum/babylon_loop_set/proc/named_file(list/index, key)
	var/entry = index[key]
	if(isnull(entry))
		return null
	if(!istext(entry) || !fexists("[path][entry]") || !babylon_music_audio(entry))
		errors += "[key]: [entry] is not an audio file in this folder"
		return null
	return "[path][entry]"

/// Whether the loop shares a never_together group with one of the others.
/datum/babylon_loop_set/proc/conflicts(loop, list/others)
	for(var/list/group as anything in never_together)
		if(!(loop in group))
			continue
		for(var/other in others)
			if(other != loop && (other in group))
				return TRUE
	return FALSE

/// Up to count loops: the always loops, then keep, then random ones (not in exclude) that fit.
/datum/babylon_loop_set/proc/choose(count, list/keep = list(), list/exclude = list())
	var/list/chosen = always.Copy()
	for(var/loop in keep)
		if(!conflicts(loop, chosen))
			chosen |= loop
	var/list/candidates = list()
	for(var/loop in loops)
		if(loop_weights[loop] > 0 && !(loop in chosen) && !(loop in exclude))
			candidates[loop] = loop_weights[loop]
	while(length(chosen) < count)
		for(var/loop in candidates.Copy())
			if(conflicts(loop, chosen))
				candidates -= loop
		var/loop = pick_weight(candidates)
		if(!loop)
			break
		chosen += loop
		candidates -= loop
	return chosen

/// The next combination: a new count of layers, reached by adding or removing loops, or one
/// swapped when the count stays. The current one when nothing else fits.
/datum/babylon_loop_set/proc/next_layers(list/current)
	var/target = rand(layers_min, layers_max)
	var/list/removable = current - always
	var/list/keep = current.Copy()
	var/list/exclude = list()
	var/drop = target < length(current) ? length(current) - target : (target == length(current) ? 1 : 0)
	for(var/i in 1 to drop)
		if(!length(removable))
			break
		var/loop = pick_n_take(removable)
		keep -= loop
		exclude += loop
	var/list/next = choose(target, keep, exclude)
	return length(next) < min(target, length(current)) ? current.Copy() : next

/// One player's run of a loop set: the playing loops and when they change.
/datum/babylon_loop_player
	var/client/listener
	var/datum/babylon_loop_set/loop_set
	/// When the loops began; synced loops join where they would be from here.
	var/started_at
	var/ends_at
	var/next_change
	/// Set once the loops fade out; the run is over at this time.
	var/done_at
	/// Playing loop -> its channel.
	var/list/active = list()

/datum/babylon_loop_player/New(client/listener, datum/babylon_loop_set/loop_set, now)
	src.listener = listener
	src.loop_set = loop_set
	started_at = now
	if(loop_set.intro)
		send(sound(file(loop_set.intro), repeat = FALSE, wait = FALSE, volume = volume(100), channel = CHANNEL_LOBBYMUSIC))
		started_at += babylon_music_length(loop_set.intro)
	else
		send(sound(null, channel = CHANNEL_LOBBYMUSIC)) // A plain track of the last mood.
	ends_at = started_at + rand(loop_set.duration_min, loop_set.duration_max)
	next_change = started_at + rand(loop_set.change_min, loop_set.change_max)

/// Called every second; FALSE once the run is over.
/datum/babylon_loop_player/proc/advance(now)
	if(done_at)
		return now < done_at
	if(now >= ends_at)
		finish(now)
		return now < done_at
	if(now < started_at)
		return TRUE
	if(!length(active))
		set_layers(loop_set.choose(rand(loop_set.layers_min, loop_set.layers_max)), now)
	else if(now >= next_change)
		set_layers(loop_set.next_layers(active.Copy()), now)
		next_change = now + rand(loop_set.change_min, loop_set.change_max)
	return TRUE

/datum/babylon_loop_player/proc/set_layers(list/wanted, now)
	for(var/loop in active.Copy())
		if(!(loop in wanted))
			fade_out(loop)
	for(var/loop in wanted)
		if(!active[loop])
			start(loop, now)

/datum/babylon_loop_player/proc/start(loop, now)
	var/channel = listener ? listener.babylon_music_take_channel() : length(active) + 1
	if(!channel)
		return
	active[loop] = channel
	var/sound/layer = sound(file(loop), repeat = TRUE, wait = FALSE, channel = channel, volume = loop_set.overlap ? 0 : volume(loop_set.loops[loop]))
	if(loop_set.sync && now > started_at)
		var/loop_length = babylon_music_length(loop)
		if(loop_length > 0)
			layer.offset = MODULUS(now - started_at, loop_length) / (1 SECONDS)
	send(layer)
	if(loop_set.overlap)
		fade(channel, 0, volume(loop_set.loops[loop]), FALSE)

/datum/babylon_loop_player/proc/fade_out(loop)
	var/channel = active[loop]
	active -= loop
	if(loop_set.overlap)
		fade(channel, volume(loop_set.loops[loop]), 0, TRUE)
	else
		cut(channel)

/// The end of the run: the loops fade out while the outro plays.
/datum/babylon_loop_player/proc/finish(now)
	for(var/loop in active.Copy())
		fade_out(loop)
	var/outro_length = 0
	if(loop_set.outro)
		send(sound(file(loop_set.outro), repeat = FALSE, wait = FALSE, volume = volume(100), channel = CHANNEL_LOBBYMUSIC))
		outro_length = babylon_music_length(loop_set.outro)
	done_at = now + max(loop_set.overlap, outro_length, 1)

/// Stops the run: at once (muted), or fading out (the mood changed).
/datum/babylon_loop_player/proc/stop(immediate)
	for(var/loop in active.Copy())
		if(immediate)
			cut(active[loop])
			active -= loop
		else
			fade_out(loop)
	send(sound(null, channel = CHANNEL_LOBBYMUSIC))

/// A new server music volume: the playing loops follow it.
/datum/babylon_loop_player/proc/update_volume()
	for(var/loop in active)
		set_volume(active[loop], volume(loop_set.loops[loop]))

/datum/babylon_loop_player/proc/volume(loop_volume)
	return listener ? listener.babylon_music_volume() * loop_volume / 100 : loop_volume

/datum/babylon_loop_player/proc/send(sound/sent)
	if(listener)
		SEND_SOUND(listener, sent)

/datum/babylon_loop_player/proc/set_volume(channel, new_volume)
	var/sound/update = sound(null)
	update.channel = channel
	update.volume = new_volume
	update.status = SOUND_UPDATE
	send(update)

/datum/babylon_loop_player/proc/cut(channel)
	if(listener)
		listener.babylon_music_fades[num2text(channel)] = null
		listener.babylon_music_free_channel(channel)
	send(sound(null, channel = channel))

/datum/babylon_loop_player/proc/fade(channel, from_volume, to_volume, free_after)
	set waitfor = FALSE
	if(!listener)
		if(free_after)
			cut(channel)
		return
	var/client/owner = listener
	var/token = world.time + rand()
	owner.babylon_music_fades[num2text(channel)] = token
	var/steps = max(1, round(loop_set.overlap / BABYLON_LOOP_FADE_STEP))
	for(var/step in 1 to steps)
		sleep(BABYLON_LOOP_FADE_STEP)
		if(!owner || owner.babylon_music_fades[num2text(channel)] != token)
			return
		set_volume(channel, from_volume + (to_volume - from_volume) * step / steps)
	if(free_after)
		cut(channel)

/client
	/// The loop set run now playing, if any.
	var/datum/babylon_loop_player/babylon_music_loops
	/// Loop channels not in use (filled on first use).
	var/list/babylon_music_channels
	/// Channel -> the fade that may change it; a newer fade or a cut ends older ones.
	var/list/babylon_music_fades = list()

/client/proc/babylon_music_take_channel()
	if(isnull(babylon_music_channels))
		babylon_music_channels = GLOB.babylon_music.loop_channels?.Copy() || list()
	if(!length(babylon_music_channels))
		return null
	return pop(babylon_music_channels)

/client/proc/babylon_music_free_channel(channel)
	if(channel && islist(babylon_music_channels))
		babylon_music_channels |= channel

#undef BABYLON_LOOP_FADE_STEP
#undef BABYLON_LOOP_CHANNELS
#undef BABYLON_LOOP_MAX_LAYERS
