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
    config.update(listen_host='127.0.0.1', listen_port=values['api_port'], public_host=host,
                  bind_address='0.0.0.0', lobby_address=address, lobby_secret=secret, admins=admins,
                  data_directory=env.get('BABYLON_DATA_DIRECTORY', '/data'),
                  template_directory=str(template), config_directory=str(runtime / 'game-config'),
                  dreamdaemon='/opt/byond/bin/DreamDaemon', port_first=first, port_last=last)
    # Only the lobby is ever listed; child worlds run with DreamDaemon -invisible.
    lobby = dict(api='http://127.0.0.1:%s' % values['api_port'], secret=secret, port=values['lobby_port'],
                 name=name, hub_listed=listed in ('true', '1', 'yes'), hub=hub, hub_password=hub_password)
    return config, lobby, values, name


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
    for filename, contents in (('supervisor.json', config), ('lobby.json', lobby)):
        file = runtime / filename
        file.write_text(json.dumps(contents))
        os.chmod(file, 0o600)
    # Apply the same validation and path normalization as a native installation.
    validated = load_config(runtime / 'supervisor.json')
    return validated, lobby, values
