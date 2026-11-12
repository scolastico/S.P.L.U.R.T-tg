import io
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock

import logstream


class LogStream(unittest.TestCase):
    def capture(self):
        output = io.StringIO()
        patcher = mock.patch.object(logstream.sys, 'stdout', output)
        patcher.start()
        self.addCleanup(patcher.stop)
        return output

    def test_every_line_is_prefixed_and_control_characters_are_dropped(self):
        output = self.capture()
        logstream.emit('lobby', 'first\r\nsecond\x1b[31m\n')
        self.assertEqual(output.getvalue(), '[lobby] first\n[lobby] second[31m\n')

    def test_world_source_names_world_and_short_id(self):
        self.assertEqual(logstream.world_source({'id': '2930f94187bffc34', 'name': 'My\nBabylon'}),
                         'world MyBabylon 2930f941')

    def test_pump_forwards_a_child_pipe(self):
        output = self.capture()
        logstream.pump(io.BytesIO(b'World opened\nWelcome BYOND!\n'), 'lobby').join(2)
        self.assertEqual(output.getvalue(), '[lobby] World opened\n[lobby] Welcome BYOND!\n')

    def test_follower_skips_earlier_runs_and_follows_the_new_round_log(self):
        output = self.capture()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'daemon.log').write_bytes(b'previous run\n')
            old = root / 'data/logs/2026/11/11/round-01.00.00/dd.log'
            old.parent.mkdir(parents=True)
            old.write_bytes(b'old round\n')
            os.utime(old, (1, 1))
            follower = logstream.Follower('world w 1', root, lambda: True, started=time.time())
            with (root / 'daemon.log').open('ab') as handle:
                handle.write(b'World opened\n')
            new = root / 'data/logs/2026/11/12/round-09.14.22/dd.log'
            new.parent.mkdir(parents=True)
            new.write_bytes(b'Initializations complete\npartial')
            follower.drain()
            with new.open('ab') as handle:
                handle.write(b' line\n')
            follower.drain()
        self.assertEqual(output.getvalue(), '[world w 1] World opened\n[world w 1] Initializations complete\n'
                                            '[world w 1] partial line\n')

    def test_runtime_code_logs_through_logstream(self):
        # A bare print() reaches docker logs without a source prefix.
        root = Path(__file__).resolve().parents[2]
        files = [p for p in (root / 'services/supervisor').glob('*.py')
                 if not p.name.startswith(('test_', 'smoke_')) and p.name != 'logstream.py']
        files += [root / 'container/entrypoint.py', root / 'container/runtime_config.py']
        for path in files:
            for number, line in enumerate(path.read_text().splitlines(), 1):
                if 'print(' in line and "'[supervisor]" not in line:
                    self.fail('%s:%d uses print(); use logstream.log() instead' % (path.name, number))


if __name__ == '__main__':
    unittest.main()
