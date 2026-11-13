"""Container PID 1: run the lobby/supervisor and checkpoint children on SIGTERM."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.request
from urllib.parse import urlencode

from runtime_config import ROOT, discord_settings, write_settings
from supervisor import Supervisor, serve
from stop_worlds import stop_worlds
from logstream import log, pump

RUNTIME = Path('/run/babylon')


def healthcheck():
    config = json.loads((RUNTIME / 'supervisor.json').read_text())
    lobby = json.loads((RUNTIME / 'lobby.json').read_text())
    body = json.dumps(dict(secret=config['lobby_secret'], actor='containerhealth',
                           action='list', payload={})).encode()
    request = urllib.request.Request('http://127.0.0.1:%s/api' % config['listen_port'],
                                     data=body, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=3) as response:
        assert json.load(response).get('ok')
    with socket.create_connection(('127.0.0.1', lobby['port']), timeout=2):
        pass


LOBBY_HANDOFF_SECONDS = 8


def restart_countdown(service, seconds, sleep=time.sleep):
    """Closes new joins and counts down in every world (and the lobby) before shutting down."""
    service.shutting_down = True
    if seconds <= 0:
        return
    remaining = seconds
    for mark in sorted({seconds, 10, 5}, reverse=True):
        if mark > seconds:
            continue
        sleep(remaining - mark)
        remaining = mark
        message = ('The server restarts in %d seconds. Your world is saved first, then you return to the '
                   'lobby, where Reconnect brings you back once the server is up again.' % mark)
        service.server_notice = message
        log('Restart countdown: %d seconds' % mark)
        service.announce(message)
    sleep(remaining)
    service.server_notice = 'The server is restarting now. Press Reconnect once it is back.'


def main():
    config, lobby, limits = write_settings()
    data = Path(config['data_directory'])
    data.mkdir(parents=True, exist_ok=True)
    lock = (data / '.cluster.lock').open('a')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise RuntimeError('Another container is already using this data volume') from None
    service = Supervisor(config)
    api = threading.Thread(target=serve, args=(config, service), daemon=True)
    api.start()
    bot = None
    bot_settings = discord_settings(os.environ, config['lobby_address'], config['data_directory'])
    if bot_settings['enabled']:
        from discord_bot import BotHandle  # Only needs discord.py when the bot is on.
        bot = BotHandle(bot_settings, service).start()
    directory = RUNTIME / 'lobby'
    directory.mkdir(exist_ok=True)
    for ext in ('dmb', 'rsc'):
        shutil.copy2(ROOT / ('babylon-lobby.' + ext), directory / ('babylon-lobby.' + ext))
    shutil.copytree(ROOT / 'modular_babylon/lobby', directory / 'modular_babylon/lobby', dirs_exist_ok=True)
    params = urlencode({'lobby-config': str(RUNTIME / 'lobby.json')})
    menu = subprocess.Popen([config['dreamdaemon'], 'babylon-lobby.dmb', str(lobby['port']),
                             '-ip', '0.0.0.0', '-trusted', '-close', '-params', params], cwd=directory,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    pump(menu.stdout, 'lobby')
    stopping = threading.Event()
    for kind in (signal.SIGTERM, signal.SIGINT):
        signal.signal(kind, lambda *_: stopping.set())
    log('Lobby address: ' + config['lobby_address'])
    exit_code = 0
    handed_over = False
    while True:
        if menu.poll() is not None or not api.is_alive():
            log('A cluster component exited (lobby exit code %s); saving worlds before restart.' % menu.poll())
            stopping.set()
            exit_code = 1
        if stopping.wait(.5):
            if bot:
                bot.stop()  # Marks the status message offline.
                bot = None
            lobby_running = menu.poll() is None
            if not handed_over:
                # The lobby stays up until the worlds have sent their players to it: its restart
                # screen offers Reconnect for when the server is back.
                handed_over = True
                restart_countdown(service, limits['restart_warning_seconds'] if lobby_running and not exit_code else 0)
            players = service.players_in_worlds()
            def stop(actor, world):
                return service.dispatch(actor, 'stop', {'world': world})
            def tick(delay):
                service.tick()
                time.sleep(delay)
            try:
                stop_worlds(config, timeout=limits['shutdown_timeout_seconds'], request=stop, sleep=tick)
            except Exception as error:
                # Keep unsaved world processes alive. Docker may still SIGKILL
                # after stop_grace_period; allow enough time to resolve failures.
                log('Shutdown could not complete; worlds retained: %s. Retrying...' % error)
                time.sleep(5)
                continue
            if menu.poll() is None:
                if players:
                    # Give the players sent back from their worlds time to arrive in the lobby.
                    log('Waiting %ss for %d player(s) to reach the lobby.' % (LOBBY_HANDOFF_SECONDS, players))
                    time.sleep(LOBBY_HANDOFF_SECONDS)
                menu.terminate()
                menu.wait(timeout=10)
            return exit_code


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--healthcheck', action='store_true')
    args = parser.parse_args()
    try:
        if args.healthcheck:
            healthcheck()
        else:
            raise SystemExit(main())
    except Exception as error:
        print('[supervisor] %s' % error, file=sys.stderr, flush=True)
        raise SystemExit(1)
