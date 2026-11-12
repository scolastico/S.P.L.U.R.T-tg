import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs

from supervisor import Driver, load_config


class AfkConfiguration(unittest.TestCase):
    def test_native_configuration_default_disabled_and_invalid_values(self):
        example = Path(__file__).with_name('config.example.json')
        config = json.loads(example.read_text())
        config['lobby_secret'] = 'test-only-secret-' * 4
        config.pop('afk_timeout_seconds')
        with tempfile.TemporaryDirectory() as folder:
            file = Path(folder) / 'config.json'
            file.write_text(json.dumps(config))
            self.assertEqual(load_config(file)['afk_timeout_seconds'], 900)
            for value in (0, 120):
                config['afk_timeout_seconds'] = value
                file.write_text(json.dumps(config))
                self.assertEqual(load_config(file)['afk_timeout_seconds'], value)
            for value in (-1, 1.5, True, '60'):
                config['afk_timeout_seconds'] = value
                file.write_text(json.dumps(config))
                with self.subTest(value=value), self.assertRaises(ValueError):
                    load_config(file)

    def test_child_launch_receives_timeout_in_seconds(self):
        with tempfile.TemporaryDirectory() as folder:
            for value in (None, 0, 300):
                config = dict(dreamdaemon='unused', listen_port=1360, lobby_address='byond://localhost:1361')
                if value is not None:
                    config['afk_timeout_seconds'] = value
                driver = Driver(config)
                with patch.object(driver, 'prepare', return_value=Path(folder)), \
                        patch('supervisor.subprocess.Popen', return_value=SimpleNamespace(pid=123)) as launch:
                    driver.start({'id': 'world', 'owner': 'owner', 'name': 'World'}, {'id': 'run', 'port': 1400, 'secret': 'test-only'})
                    arguments = launch.call_args.args[0]
                    params = parse_qs(arguments[arguments.index('-params') + 1])
                    self.assertEqual(params['babylon-afk-timeout'], [str(900 if value is None else value)])
