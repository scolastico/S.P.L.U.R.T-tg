"""Save/stop cluster worlds through the supervisor; never kill a child process."""
import argparse
from contextlib import closing
import json
from pathlib import Path
import sqlite3
import time
import urllib.error
import urllib.request

from logstream import log


def running_worlds(database):
    if not database.exists():
        return []
    with closing(sqlite3.connect(database.resolve().as_uri() + '?mode=ro', uri=True)) as db:
        db.row_factory = sqlite3.Row
        return [dict(row) for row in db.execute(
            'SELECT r.world,r.state,r.error,w.owner FROM runs r JOIN worlds w ON w.id=r.world')]


def stop_worlds(config, timeout=180, request=None, sleep=time.sleep, clock=time.monotonic):
    database = Path(config['data_directory']) / 'supervisor.sqlite3'
    worlds = running_worlds(database)
    if not worlds:
        log('No world servers are running.')
        return
    if request is None:
        def request(actor, world):
            body = json.dumps(dict(secret=config['lobby_secret'], actor=actor,
                                   action='stop', payload=dict(world=world))).encode()
            message = urllib.request.Request('http://127.0.0.1:%s/api' % config['listen_port'],
                                             data=body, headers={'Content-Type': 'application/json'})
            try:
                with urllib.request.urlopen(message, timeout=30) as response:
                    result = json.load(response)
            except urllib.error.HTTPError as error:
                result = json.load(error)
            if not result.get('ok'):
                raise RuntimeError(result.get('error', 'Supervisor rejected shutdown'))
    log('Saving and stopping %d world(s)...' % len(worlds))
    # A child cannot checkpoint until restoration/initialization has finished.
    # Closing the lobby already prevents further launches while we wait.
    deadline = clock() + max(timeout, config.get('startup_timeout_seconds', 300))
    while any(world['state'] == 'starting' for world in worlds):
        if clock() >= deadline:
            raise TimeoutError('A world is still starting; supervisor and children left running')
        sleep(.5)
        worlds = running_worlds(database)
    for world in worlds:
        request(world['owner'], world['world'])
    deadline = clock() + timeout
    while True:
        remaining = running_worlds(database)
        if not remaining:
            log('All worlds saved and stopped.')
            return
        failures = [world for world in remaining if world['state'] == 'error']
        if failures:
            raise RuntimeError('World save/stop failed; processes retained: ' +
                               '; '.join(world['error'] or world['world'] for world in failures))
        if clock() >= deadline:
            raise TimeoutError('World shutdown timed out; supervisor and children left running')
        sleep(.5)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    try:
        stop_worlds(json.loads(Path(args.config).read_text(encoding='utf-8-sig')))
    except Exception as error:
        raise SystemExit(str(error))
