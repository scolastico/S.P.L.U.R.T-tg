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
 * "Server music volume" (its own preference, toggled from the OOC tab). A new place takes over
 * once the player has stayed there a few seconds, so walking through a door does not cut the
 * music. The status tab names the playing track with a [?] that explains, in chat, why players
 * who record should mute it: each server picks its own tracks, under licenses that need not
 * cover recordings. Without the folder, nothing changes.
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
	/// When the current track ends; the status tab names it until then.
	var/babylon_music_playing_until = 0
	/// The volume "Toggle Server Music" restores, remembered when it mutes.
	var/babylon_music_unmuted_volume
	/// A place the player moved to, and since when, before its music takes over.
	var/babylon_music_pending
	var/babylon_music_pending_since = 0

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
#undef BABYLON_MUSIC_SETTLE
#undef BABYLON_MUSIC_AREA_ROOT
