/*
 * Optional server-side music. The operator puts tracks into a folder on the server (a Docker
 * volume, BABYLON_MUSIC_DIRECTORY, default /music), never into the repository, so licensed
 * music stays server specific. Subfolders choose the mood a track plays in; players rebuild
 * the station as they like, so the mood follows what is around them, not the room's name:
 *
 *   space/      outside the hull
 *   engine/     within BABYLON_MUSIC_ENGINE_RADIUS tiles (default 10, 0 = off) of a power
 *               generator, wherever it was built; solar panels do not count
 *   derelict/   inside, where the air is too thin to breathe (not pressurized yet)
 *   station/    inside, with air
 *
 * An empty engine/ or derelict/ falls back to the derelict/station music. Tracks (.ogg, .mp3,
 * .wav) play one after another, with a pause between them, at the player's "Server music
 * volume" (its own preference, toggled from the OOC tab). A new mood takes over only once the
 * player has stayed in it for BABYLON_MUSIC_DEBOUNCE_SECONDS (default 20), so a quick trip
 * outside does not cut the track. The status tab names the playing track with a [?] that
 * explains, in chat, why players who record should mute it: each server picks its own tracks,
 * under licenses that need not cover recordings. Without the folder, nothing changes.
 */

#define BABYLON_MUSIC_GAP (30 SECONDS)

GLOBAL_DATUM_INIT(babylon_music, /datum/babylon_music, new)

/datum/babylon_music
	/// The music folder with a trailing slash, or null without music.
	var/root
	/// Folder ("space", "engine", "derelict", "station") -> list of track paths.
	var/list/tracks = list()
	var/scanned = FALSE
	/// Tiles around a power generator that play engine/ music; 0 turns it off.
	var/engine_radius = 10
	/// How long a player stays in a new mood before its music takes over.
	var/debounce = 20 SECONDS
	/// Machines that generate power. Solar panels (and storage such as SMES) are left out.
	var/static/list/engine_types = list(
		/obj/machinery/power/supermatter_crystal,
		/obj/machinery/power/energy_accumulator,
		/obj/machinery/power/port_gen,
		/obj/machinery/power/thermoelectric_generator,
		/obj/machinery/power/rtg,
		/obj/machinery/power/turbine/core_rotor,
		/obj/machinery/power/rbmk2,
		/obj/machinery/power/stirling_generator,
		/obj/machinery/power/colony_wind_turbine,
	)

/datum/babylon_music/proc/scan()
	scanned = TRUE
	engine_radius = babylon_music_setting("BABYLON_MUSIC_ENGINE_RADIUS", engine_radius)
	debounce = babylon_music_setting("BABYLON_MUSIC_DEBOUNCE_SECONDS", debounce / (1 SECONDS)) * (1 SECONDS)
	root = world.params["babylon-music"]
	if(!istext(root) || !length(root))
		root = null
		return
	if(copytext(root, -1) != "/")
		root += "/"
	scan_folder("", 0)
	var/count = 0
	for(var/folder in tracks)
		count += length(tracks[folder])
		if(!(folder in list("space", "engine", "derelict", "station")))
			log_world("Babylon music: [root][folder]/ is not a mood folder (space, engine, derelict, station); its tracks never play.")
	log_world("Babylon music: [count] track(s) in [length(tracks)] folder(s) under [root]; engine radius [engine_radius], debounce [debounce / (1 SECONDS)] s.")

/// A whole number from the environment, at least 0, or the fallback.
/proc/babylon_music_setting(name, fallback)
	var/value = text2num(world.GetConfig("env", name))
	return isnum(value) && value >= 0 ? round(value) : fallback

/datum/babylon_music/proc/scan_folder(relative, depth)
	if(depth > 6)
		return
	for(var/entry in flist("[root][relative]"))
		if(copytext(entry, -1) == "/")
			scan_folder("[relative][entry]", depth + 1)
			continue
		if(!relative) // Tracks belong in a folder that says where they play.
			continue
		var/extension = LOWER_TEXT(copytext(entry, findlasttext(entry, ".") + 1))
		if(!(extension in list("ogg", "mp3", "wav")))
			continue
		var/folder = LOWER_TEXT(copytext(relative, 1, length(relative)))
		if(!tracks[folder])
			tracks[folder] = list()
		tracks[folder] += "[root][relative][entry]"

/// The folder whose music fits where the listener is, or null for silence.
/datum/babylon_music/proc/folder_for(mob/listener)
	var/turf/place = get_turf(listener)
	if(!place)
		return null
	if(isspaceturf(place) || istype(get_area(place), /area/space))
		return tracks["space"] ? "space" : null
	if(tracks["engine"] && near_engine(place))
		return "engine"
	if(tracks["derelict"])
		var/datum/gas_mixture/air = place.return_air()
		if(!air || air.return_pressure() < WARNING_LOW_PRESSURE)
			return "derelict"
	return tracks["station"] ? "station" : null

/**
 * The folder to play now: `playing` until the player has stayed in the mood `folder` for the
 * debounce time, so a short trip elsewhere keeps the track. With nothing playing, a mood starts
 * at once. `pending` is list(folder, since), the mood the player is in; updated in place.
 */
/datum/babylon_music/proc/debounced(playing, folder, list/pending, now)
	if(folder != pending[1])
		pending[1] = folder
		pending[2] = now
	if(folder == playing || !playing)
		return folder
	return now >= pending[2] + debounce ? folder : playing

/// Whether a power generator stands (not packed in a crate) within engine_radius of the place.
/datum/babylon_music/proc/near_engine(turf/place)
	if(engine_radius <= 0)
		return FALSE
	for(var/engine_type in engine_types)
		for(var/obj/machinery/engine as anything in SSmachines.get_machines_by_type_and_subtypes(engine_type))
			if(engine.z == place.z && isturf(engine.loc) && get_dist(engine, place) <= engine_radius)
				return TRUE
	return FALSE

/client
	/// The music folder now playing for this client, its last track and when the next may start.
	var/babylon_music_folder
	var/babylon_music_track
	var/babylon_music_next = 0
	/// When the current track ends; the status tab names it until then.
	var/babylon_music_playing_until = 0
	/// The volume "Toggle Server Music" restores, remembered when it mutes.
	var/babylon_music_unmuted_volume
	/// The mood the player is in and since when: list(folder, world.time), see debounced().
	var/list/babylon_music_pending = list(null, 0)

/client/proc/babylon_music_volume()
	return prefs ? prefs.read_preference(/datum/preference/numeric/volume/babylon_server_music) : 0

/client/proc/babylon_stop_music()
	babylon_music_folder = null
	babylon_music_next = 0
	babylon_music_playing_until = 0
	SEND_SOUND(src, sound(null, channel = CHANNEL_LOBBYMUSIC))

/// Called every second by the world tick for each player.
/client/proc/babylon_update_music()
	var/datum/babylon_music/music = GLOB.babylon_music
	if(!music.scanned)
		music.scan()
	if(!length(music.tracks))
		return
	var/volume = babylon_music_volume()
	if(!volume)
		if(babylon_music_folder)
			babylon_stop_music()
		return
	var/folder = music.debounced(babylon_music_folder, music.folder_for(mob), babylon_music_pending, world.time)
	if(folder != babylon_music_folder)
		if(!folder)
			babylon_stop_music()
			return
		babylon_music_folder = folder
		babylon_music_next = 0 // The new mood's music starts now.
	if(!folder || world.time < babylon_music_next)
		return
	var/list/choices = music.tracks[folder].Copy()
	if(length(choices) > 1)
		choices -= babylon_music_track
	babylon_music_track = pick(choices)
	SEND_SOUND(src, sound(file(babylon_music_track), repeat = FALSE, wait = FALSE, volume = volume, channel = CHANNEL_LOBBYMUSIC))
	var/duration = 0
	try
		duration = rustg_sound_length(babylon_music_track)
	catch
		duration = 0
	babylon_music_playing_until = world.time + (duration > 0 ? duration : 3 MINUTES)
	babylon_music_next = babylon_music_playing_until + BABYLON_MUSIC_GAP

/// The server music's own volume, apart from upstream's jukeboxes; 0 turns it off.
/datum/preference/numeric/volume/babylon_server_music
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "babylon_server_music"
	savefile_identifier = PREFERENCE_PLAYER

/// Moving the slider changes the music now, or stops it at 0.
/datum/preference/numeric/volume/babylon_server_music/apply_to_client_updated(client/client, value)
	if(!client || !world.params["babylon-world"] || !client.babylon_music_folder)
		return
	if(!value)
		client.babylon_stop_music()
		return
	var/sound/update = sound(null)
	update.channel = CHANNEL_LOBBYMUSIC
	update.volume = value
	update.status = SOUND_UPDATE
	SEND_SOUND(client, update)

/// No title (lobby) music in Babylon worlds. Every join briefly has a new-player mob whose
/// Login() starts it, and possessing the drone never stopped it, so it played on (on the
/// server music's channel) until a server track replaced it; round end, the ticker and the
/// lobby volume preference start it too. Server music is the only music in a world.
/client/playtitlemusic(volume_multiplier = 1)
	set waitfor = FALSE // As upstream's: it waits for the ticker's music.
	if(world.params["babylon-world"])
		return
	return ..()

/// Quick mute for players who record or stream; unmuting restores the volume they had.
/client/verb/babylon_toggle_server_music()
	set name = "Toggle Server Music"
	set category = "OOC"
	set desc = "Mute or unmute the music this server plays in the world."
	if(!prefs)
		return
	var/datum/preference/music_volume = GLOB.preference_entries[/datum/preference/numeric/volume/babylon_server_music]
	var/volume = babylon_music_volume()
	if(volume)
		babylon_music_unmuted_volume = volume
	var/new_volume = volume ? 0 : (babylon_music_unmuted_volume || music_volume.create_default_value())
	if(!prefs.update_preference(music_volume, new_volume))
		return
	prefs.save_preferences()
	to_chat(src, span_notice(new_volume ? "Server music is on (volume [new_volume])." : "Server music is muted."))

/// A track's name as players see it: its file name without folder and extension.
/proc/babylon_music_title(path)
	var/title = "[path]"
	title = copytext(title, findlasttext(title, "/") + 1)
	var/dot = findlasttext(title, ".")
	if(dot > 1)
		title = copytext(title, 1, dot)
	return trim(replacetext(title, "_", " "))

/// The status tab names the playing track; its [?] explains server music in chat.
/mob/get_status_tab_items()
	. = ..()
	if(client?.babylon_music_folder && world.time < client.babylon_music_playing_until)
		. += list(list("Server music: [babylon_music_title(client.babylon_music_track)] ", "\[?\]", "babylon_music=info"))

/client/Topic(href, list/href_list, hsrc, hsrc_command)
	if(href_list?["babylon_music"] == "info")
		babylon_music_info()
		return
	return ..()

/client/proc/babylon_music_info()
	var/list/lines = list()
	if(babylon_music_folder && world.time < babylon_music_playing_until)
		lines += "<b>Now playing:</b> [html_encode(babylon_music_title(babylon_music_track))]"
	lines += "This server plays music it picked itself. Those tracks are not part of Babylon13, and their licenses can differ from the game's: they cover playing them here, not your recordings."
	lines += "<b>Recording or streaming?</b> Mute it first with <b>Toggle Server Music</b> in the OOC tab, or set <b>Server music volume</b> to 0 in the game preferences. Otherwise your video can get copyright claims (for example YouTube Content ID)."
	to_chat(src, fieldset_block("Server music", span_infoplain(jointext(lines, "<br>")), "boxed_message"), type = MESSAGE_TYPE_INFO)

#undef BABYLON_MUSIC_GAP
