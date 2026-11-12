// Links in the escape menu (Menu > Resources). Upstream's defaults point at
// /tg/station's wiki, forums, rules and server config; Babylon only shows the
// links its container configures (see container/runtime_config.py).

/datum/config_entry/string/wikiurl
	default = ""

/datum/config_entry/string/forumurl
	default = ""

/datum/config_entry/string/rulesurl
	default = ""

/datum/config_entry/string/configurl
	default = ""

/datum/config_entry/string/githuburl
	default = "https://github.com/scolastico/babylon13"

/// Discord invite for the escape menu's Discord button (BABYLON_DISCORD_INVITE).
/datum/config_entry/string/discordurl

/datum/escape_menu/proc/babylon_resources()
	. = list()
	if(CONFIG_GET(string/discordurl))
		. += list(list("id" = "discord", "label" = "Discord", "tooltip" = "Join the Babylon13 Discord"))

/client/proc/babylon_open_discord()
	var/discordurl = CONFIG_GET(string/discordurl)
	if(!discordurl)
		to_chat(src, span_danger("The Discord link is not set in the server configuration."))
		return
	DIRECT_OUTPUT(src, link(discordurl))

/datum/asset/spritesheet/escape_menu_icons/create_spritesheets()
	. = ..()
	// The escape menu has no Discord icon; reuse the speech bubbles of Forums.
	Insert("discord", 'icons/hud/escape_menu_icons.dmi', icon_state = "forums")
