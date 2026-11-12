"""Translate the public container environment into private cluster configs."""
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'services/supervisor'))
from supervisor import ckey, load_config


DEFAULTS = {
    'lobby_port': 1361, 'api_port': 1360, 'world_port_first': 1400, 'world_port_last': 1420,
    'max_running_worlds': 4, 'max_players_per_world': 4, 'max_worlds_per_player': 3,
    'max_running_worlds_per_player': 1, 'kept_save_points_per_world': 4,
    'delete_unused_worlds_after_days': 60, 'empty_grace_seconds': 120,
    'startup_timeout_seconds': 300, 'ticket_lifetime_seconds': 60,
    'shutdown_timeout_seconds': 180,
    'afk_timeout_seconds': 900,
}

# Upstream's shared Space Station 13 hub entry; its password is public in code/world.dm.
UPSTREAM_HUB = 'Exadv1.spacestation13'
UPSTREAM_HUB_PASSWORD = 'kMZy3U5jJHSiBQjr'
# BYOND hub status line (HTML). Placeholders, filled by the lobby every 30 s:
# {name} {players} {lobby_players} {world_players} {running_worlds}
# {running_worlds_label} {max_running_worlds} {address}
DEFAULT_HUB_STATUS = ('<b>{name}</b> &#8212; persistent station building<br>'
                      'Players: <b>{players}</b> ({world_players} in {running_worlds_label}, '
                      '{lobby_players} in the lobby)')


def settings(env=None, runtime=Path('/run/babylon'), template=ROOT):
    env = os.environ if env is None else env
    values = {}
    for name, default in DEFAULTS.items():
        raw = str(env.get('BABYLON_' + name.upper(), default))
        if not re.fullmatch(r'\d+', raw):
            raise ValueError('BABYLON_' + name.upper() + ' must be an integer')
        number = int(raw)
        minimum = 0 if name in ('delete_unused_worlds_after_days', 'afk_timeout_seconds') else 1
        if number < minimum or ('port' in name and number > 65535):
            raise ValueError('Invalid BABYLON_' + name.upper())
        values[name] = number
    first, last = values['world_port_first'], values['world_port_last']
    if last < first:
        raise ValueError('WORLD_PORT_LAST must be >= WORLD_PORT_FIRST')
    if values['api_port'] == values['lobby_port'] or any(first <= values[key] <= last for key in ('api_port', 'lobby_port')):
        raise ValueError('Lobby, internal API and world port range must not overlap')
    if values['max_running_worlds'] > last - first + 1:
        raise ValueError('The world port range is smaller than MAX_RUNNING_WORLDS')
    host = env.get('BABYLON_PUBLIC_HOST', '127.0.0.1')
    if not re.fullmatch(r'[A-Za-z0-9.-]+', host):
        raise ValueError('BABYLON_PUBLIC_HOST must be a hostname or IPv4 address, without a port')
    admins = []
    for item in env.get('BABYLON_ADMINS', '').split(','):
        if not item.strip():
            continue
        account = ckey(item)
        if not account or account.startswith('guest'):
            raise ValueError('Invalid account in BABYLON_ADMINS')
        if account not in admins:
            admins.append(account)
    name = env.get('BABYLON_SERVER_NAME', 'Babylon13')
    if not name.strip() or '\n' in name or '\r' in name:
        raise ValueError('BABYLON_SERVER_NAME must be a nonempty single line')
    listed = env.get('BABYLON_HUB_LISTED', 'false').strip().lower()
    if listed not in ('true', 'false', '1', '0', 'yes', 'no'):
        raise ValueError('BABYLON_HUB_LISTED must be true or false')
    hub = env.get('BABYLON_HUB', UPSTREAM_HUB)
    if not re.fullmatch(r'[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', hub):
        raise ValueError('BABYLON_HUB must be a BYOND hub path such as Author.Game')
    # Empty means the default, so Compose can pass ${BABYLON_HUB_STATUS:-}.
    hub_status = env.get('BABYLON_HUB_STATUS', '').strip() or DEFAULT_HUB_STATUS
    if len(hub_status) > 2048:
        raise ValueError('BABYLON_HUB_STATUS must be at most 2048 characters')
    hub_password = env.get('BABYLON_HUB_PASSWORD', UPSTREAM_HUB_PASSWORD)
    if not re.fullmatch(r'[\x21-\x7e]{1,128}', hub_password):
        raise ValueError('BABYLON_HUB_PASSWORD must be printable ASCII without spaces')
    secret = secrets.token_urlsafe(48)
    address = 'byond://%s:%s' % (host, values['lobby_port'])
    config = {key: values[key] for key in (
        'max_running_worlds', 'max_players_per_world', 'max_worlds_per_player',
        'max_running_worlds_per_player', 'kept_save_points_per_world',
        'delete_unused_worlds_after_days', 'empty_grace_seconds',
        'startup_timeout_seconds', 'ticket_lifetime_seconds', 'afk_timeout_seconds')}
    discord = discord_settings(env, address, env.get('BABYLON_DATA_DIRECTORY', '/data'))
    config['discord'] = public_discord(discord)
    config.update(listen_host='127.0.0.1', listen_port=values['api_port'], public_host=host,
                  bind_address='0.0.0.0', lobby_address=address, lobby_secret=secret, admins=admins,
                  data_directory=env.get('BABYLON_DATA_DIRECTORY', '/data'),
                  template_directory=str(template), config_directory=str(runtime / 'game-config'),
                  dreamdaemon='/opt/byond/bin/DreamDaemon', port_first=first, port_last=last)
    # Only the lobby is ever listed; child worlds run with DreamDaemon -invisible.
    lobby = dict(api='http://127.0.0.1:%s' % values['api_port'], secret=secret, port=values['lobby_port'],
                 name=name, hub_listed=listed in ('true', '1', 'yes'), hub=hub, hub_password=hub_password,
                 hub_status=hub_status, address=address, max_running_worlds=values['max_running_worlds'])
    return config, lobby, values, name


DISCORD_FEATURES = ('link', 'roles', 'voice', 'logs', 'status', 'gamelog', 'tickets')
DISCORD_CHANNELS = ('status', 'voice_lobby', 'mod_log', 'member_log', 'message_log', 'voice_log', 'game_log', 'bot_log',
                    'ticket_panel', 'ticket_log')


def flag(env, name, default='false'):
    value = env.get(name, default).strip().lower() or default
    if value not in ('true', 'false', '1', '0', 'yes', 'no'):
        raise ValueError(name + ' must be true or false')
    return value in ('true', '1', 'yes')


def snowflake(env, name, required=False):
    value = env.get(name, '').strip()
    if not value:
        if required:
            raise ValueError(name + ' is required for the Discord bot')
        return None
    if not re.fullmatch(r'\d{5,25}', value):
        raise ValueError(name + ' must be a Discord ID (digits only)')
    return int(value)


def id_list(env, name):
    value = env.get(name, '').replace(' ', '')
    if not re.fullmatch(r'(\d{5,25}(,\d{5,25})*)?,?', value):
        raise ValueError(name + ' must be comma-separated Discord IDs')
    return [int(item) for item in value.split(',') if item]


def discord_settings(env, address='', data_directory='/data'):
    """The bot's settings, including its token. Never written to disk."""
    token = env.get('BABYLON_DISCORD_TOKEN', '').strip()
    # The default needs no channel IDs; the others are enabled explicitly.
    raw = env.get('BABYLON_DISCORD_FEATURES', 'link,roles')
    features = [item.strip().lower() for item in raw.split(',') if item.strip()]
    unknown = [item for item in features if item not in DISCORD_FEATURES]
    if unknown:
        raise ValueError('Unknown BABYLON_DISCORD_FEATURES: ' + ', '.join(unknown))
    invite = env.get('BABYLON_DISCORD_INVITE', '').strip()
    if invite and not re.fullmatch(r'https://[\x21-\x7e]+', invite):
        raise ValueError('BABYLON_DISCORD_INVITE must be an https:// link')
    join_url = env.get('BABYLON_JOIN_URL', '').strip()
    if join_url and not re.fullmatch(r'https://[\x21-\x7e]+', join_url):
        raise ValueError('BABYLON_JOIN_URL must be an https:// link')
    settings = {
        'token': token,
        'enabled': bool(token),
        'guild_id': snowflake(env, 'BABYLON_DISCORD_GUILD_ID', required=bool(token)),
        'features': features if token else [],
        'channels': {key: channel for key in DISCORD_CHANNELS
                     if (channel := snowflake(env, 'BABYLON_DISCORD_%s_CHANNEL' % key.upper()))},
        'self_roles': id_list(env, 'BABYLON_DISCORD_SELF_ROLES'),
        'color_roles': id_list(env, 'BABYLON_DISCORD_COLOR_ROLES'),
        'staff_roles': id_list(env, 'BABYLON_DISCORD_STAFF_ROLES'),
        'ticket_category': snowflake(env, 'BABYLON_DISCORD_TICKET_CATEGORY'),
        'linked_role': snowflake(env, 'BABYLON_DISCORD_LINKED_ROLE'),
        'voice_room_name': env.get('BABYLON_DISCORD_VOICE_ROOM_NAME', "\U0001f50a\u2503{name}'s room")[:90] or "{name}'s room",
        'invite': invite,
        'join_url': join_url,
        'address': address,
        'data_directory': data_directory,
        'require_create': flag(env, 'BABYLON_REQUIRE_DISCORD_TO_CREATE'),
        'require_join': flag(env, 'BABYLON_REQUIRE_DISCORD_TO_JOIN'),
    }
    if 'tickets' in settings['features'] and not (settings['ticket_category'] and settings['staff_roles']
                                                  and {'ticket_panel', 'ticket_log'} <= set(settings['channels'])):
        raise ValueError('The tickets feature needs BABYLON_DISCORD_TICKET_PANEL_CHANNEL, _TICKET_LOG_CHANNEL, '
                         '_TICKET_CATEGORY and _STAFF_ROLES')
    settings['link'] = 'link' in settings['features']
    if (settings['require_create'] or settings['require_join']) and not settings['link']:
        raise ValueError('Requiring Discord needs the bot (BABYLON_DISCORD_TOKEN) with the link feature')
    if 'voice' in settings['features'] and 'voice_lobby' not in settings['channels']:
        raise ValueError('The voice feature needs BABYLON_DISCORD_VOICE_LOBBY_CHANNEL')
    if 'status' in settings['features'] and 'status' not in settings['channels']:
        raise ValueError('The status feature needs BABYLON_DISCORD_STATUS_CHANNEL')
    if 'gamelog' in settings['features'] and 'game_log' not in settings['channels']:
        raise ValueError('The gamelog feature needs BABYLON_DISCORD_GAME_LOG_CHANNEL')
    return settings


def public_discord(settings):
    """The part of the Discord settings the supervisor and lobby may store."""
    return {key: settings[key] for key in ('link', 'require_create', 'require_join', 'invite')}


def write_settings(env=None, runtime=Path('/run/babylon'), template=ROOT):
    env = os.environ if env is None else env
    config, lobby, values, name = settings(env, runtime, template)
    runtime.mkdir(parents=True, exist_ok=True)
    os.chmod(runtime, 0o700)
    source = Path(env.get('BABYLON_CONFIG_DIRECTORY', str(template / 'container/default-config')))
    if not (source / 'config.txt').is_file():
        raise ValueError('BABYLON_CONFIG_DIRECTORY must contain config.txt')
    shutil.copytree(source, runtime / 'game-config', dirs_exist_ok=True)
    with (runtime / 'game-config/config.txt').open('a') as output:
        output.write('\nSERVERNAME ' + name + '\n')
        if config['discord']['invite']:
            # The game's Discord button (escape menu > Resources).
            output.write('DISCORDURL ' + config['discord']['invite'] + '\n')
        rules = env.get('BABYLON_RULES_URL', '').strip()
        if rules:
            if not re.fullmatch(r'https://[\x21-\x7e]+', rules):
                raise ValueError('BABYLON_RULES_URL must be an https:// link')
            output.write('RULESURL ' + rules + '\n')
    for filename, contents in (('supervisor.json', config), ('lobby.json', lobby)):
        file = runtime / filename
        file.write_text(json.dumps(contents))
        os.chmod(file, 0o600)
    # Apply the same validation and path normalization as a native installation.
    validated = load_config(runtime / 'supervisor.json')
    return validated, lobby, values
