/*
 * Optional server-side music. The operator puts tracks into a folder on the server (a Docker
 * volume, BABYLON_MUSIC_DIRECTORY, default /music), never into the repository, so licensed
 * music stays server specific. Subfolders choose where a track plays:
 *
 *   space/                 outside the station
 *   station/               anywhere inside without a more specific folder
 *   engineering/           an area of the station's tree (/area/ruin/space/bb13/...),
 *   engineering/engine/    the most specific folder with tracks wins
 *
 * Tracks (.ogg, .mp3, .wav) play one after another, with a pause between them, at the player's
 * "Jukebox volume". A new place takes over once the player has stayed there a few seconds, so
 * walking through a door does not cut the music. Without the folder, nothing changes.
 */

#define BABYLON_MUSIC_GAP (30 SECONDS)
#define BABYLON_MUSIC_SETTLE (5 SECONDS)
#define BABYLON_MUSIC_AREA_ROOT "/area/ruin/space/bb13/"

GLOBAL_DATUM_INIT(babylon_music, /datum/babylon_music, new)

/datum/babylon_music
	/// The music folder with a trailing slash, or null without music.
	var/root
	/// Folder ("space", "station", "engineering/engine" ...) -> list of track paths.
	var/list/tracks = list()
	var/scanned = FALSE

/datum/babylon_music/proc/scan()
	scanned = TRUE
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
	log_world("Babylon music: [count] track(s) in [length(tracks)] folder(s) under [root].")

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
	var/area/room = get_area(place)
	if(isspaceturf(place) || istype(room, /area/space))
		return tracks["space"] ? "space" : null
	var/path = "[room.type]"
	if(findtext(path, BABYLON_MUSIC_AREA_ROOT) == 1)
		// engineering/engine, then engineering, then station.
		var/list/parts = splittext(copytext(path, length(BABYLON_MUSIC_AREA_ROOT) + 1), "/")
		while(length(parts))
			var/folder = jointext(parts, "/")
			if(tracks[folder])
				return folder
			parts.len--
	return tracks["station"] ? "station" : null

/client
	/// The music folder now playing for this client, its last track and when the next may start.
	var/babylon_music_folder
	var/babylon_music_track
	var/babylon_music_next = 0
	/// A place the player moved to, and since when, before its music takes over.
	var/babylon_music_pending
	var/babylon_music_pending_since = 0

/client/proc/babylon_music_volume()
	return prefs ? prefs.read_preference(/datum/preference/numeric/volume/sound_jukebox) : 0

/client/proc/babylon_stop_music()
	babylon_music_folder = null
	babylon_music_next = 0
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
	var/folder = music.folder_for(mob)
	if(folder != babylon_music_folder)
		if(folder != babylon_music_pending)
			babylon_music_pending = folder
			babylon_music_pending_since = world.time
			return
		if(world.time < babylon_music_pending_since + BABYLON_MUSIC_SETTLE)
			return
		if(!folder)
			babylon_stop_music()
			return
		babylon_music_folder = folder
		babylon_music_next = 0 // The new place's music starts now.
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
	babylon_music_next = world.time + (duration > 0 ? duration : 3 MINUTES) + BABYLON_MUSIC_GAP

/// Moving the "Jukebox volume" slider changes the music now, or stops it at 0.
/datum/preference/numeric/volume/sound_jukebox/apply_to_client_updated(client/client, value)
	. = ..()
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

#undef BABYLON_MUSIC_GAP
#undef BABYLON_MUSIC_SETTLE
#undef BABYLON_MUSIC_AREA_ROOT
