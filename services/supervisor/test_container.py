import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

source = Path(__file__).resolve().parents[2] / 'container/runtime_config.py'
spec = importlib.util.spec_from_file_location('container_runtime_config', source)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class ContainerConfiguration(unittest.TestCase):
    def test_defaults_keep_api_internal_and_generate_distinct_secrets(self):
        config, lobby, limits, name = runtime.settings({})
        self.assertEqual(config['listen_host'], '127.0.0.1')
        self.assertEqual(config['bind_address'], '0.0.0.0')
        self.assertEqual(config['lobby_secret'], lobby['secret'])
        self.assertNotEqual(config['lobby_secret'], runtime.settings({})[0]['lobby_secret'])
        self.assertEqual(config['kept_save_points_per_world'], 4)
        self.assertEqual(config['delete_unused_worlds_after_days'], 60)
        self.assertEqual(config['afk_timeout_seconds'], 900)

    def test_environment_ports_quotas_and_admin_csv(self):
        config, lobby, limits, name = runtime.settings(dict(
            BABYLON_PUBLIC_HOST='station.example.org', BABYLON_LOBBY_PORT='2400',
            BABYLON_WORLD_PORT_FIRST='2500', BABYLON_WORLD_PORT_LAST='2501',
            BABYLON_MAX_RUNNING_WORLDS='2', BABYLON_MAX_PLAYERS_PER_WORLD='8',
            BABYLON_ADMINS='Alice Smith, BOB, alice.smith, ,',
            BABYLON_AFK_TIMEOUT_SECONDS='300',
            BABYLON_DELETE_UNUSED_WORLDS_AFTER_DAYS='0', BABYLON_KEPT_SAVE_POINTS_PER_WORLD='9'))
        self.assertEqual(config['admins'], ['alicesmith', 'bob'])
        self.assertEqual(config['lobby_address'], 'byond://station.example.org:2400')
        self.assertEqual((config['port_first'], config['port_last']), (2500, 2501))
        self.assertEqual(config['max_players_per_world'], 8)
        self.assertEqual(config['delete_unused_worlds_after_days'], 0)
        self.assertEqual(config['kept_save_points_per_world'], 9)
        self.assertEqual(config['afk_timeout_seconds'], 300)
        self.assertEqual(runtime.settings(dict(BABYLON_AFK_TIMEOUT_SECONDS='0'))[0]['afk_timeout_seconds'], 0)

    def test_hub_listing_is_opt_in_and_configurable(self):
        lobby = runtime.settings({})[1]
        self.assertFalse(lobby['hub_listed'])
        self.assertEqual((lobby['hub'], lobby['name']), ('Exadv1.spacestation13', 'Babylon13'))
        lobby = runtime.settings(dict(BABYLON_HUB_LISTED='True', BABYLON_HUB='Someone.babylon',
                                      BABYLON_HUB_PASSWORD='s3cret!'))[1]
        self.assertTrue(lobby['hub_listed'])
        self.assertEqual((lobby['hub'], lobby['hub_password']), ('Someone.babylon', 's3cret!'))
        for values in (dict(BABYLON_HUB_LISTED='maybe'), dict(BABYLON_HUB='no-dot'),
                       dict(BABYLON_HUB_PASSWORD='has space'), dict(BABYLON_HUB_STATUS='x' * 2049)):
            with self.subTest(values=values), self.assertRaises(ValueError):
                runtime.settings(values)

    def test_hub_status_template_comes_from_the_environment(self):
        lobby = runtime.settings({})[1]
        self.assertIn('{players}', lobby['hub_status'])
        self.assertEqual((lobby['address'], lobby['max_running_worlds']),
                         ('byond://127.0.0.1:1361', runtime.settings({})[2]['max_running_worlds']))
        template = '<b>{name}</b> <a href="https://example.org">Discord</a> {players} online'
        self.assertEqual(runtime.settings(dict(BABYLON_HUB_STATUS=template))[1]['hub_status'], template)
        self.assertEqual(runtime.settings(dict(BABYLON_HUB_STATUS=' '))[1]['hub_status'], lobby['hub_status'])

    def test_discord_is_off_without_a_token_and_never_stored_with_it(self):
        config, lobby = runtime.settings({})[:2]
        self.assertEqual(config['discord'], dict(link=False, require_create=False, require_join=False, invite=''))
        env = dict(BABYLON_DISCORD_TOKEN='secret-token', BABYLON_DISCORD_GUILD_ID='1570426548362678402',
                   BABYLON_DISCORD_FEATURES='link,roles,tickets,status', BABYLON_DISCORD_SELF_ROLES='111111, 222222',
                   BABYLON_DISCORD_COLOR_ROLES='333333', BABYLON_DISCORD_STAFF_ROLES='444444',
                   BABYLON_DISCORD_TICKET_CATEGORY='555555', BABYLON_DISCORD_TICKET_PANEL_CHANNEL='666666',
                   BABYLON_DISCORD_TICKET_LOG_CHANNEL='777777', BABYLON_DISCORD_STATUS_CHANNEL='888888',
                   BABYLON_DISCORD_INVITE='https://discord.gg/example', BABYLON_REQUIRE_DISCORD_TO_JOIN='true')
        bot = runtime.discord_settings(env, 'byond://host:1361')
        self.assertEqual((bot['self_roles'], bot['color_roles'], bot['staff_roles']), ([111111, 222222], [333333], [444444]))
        self.assertEqual(bot['channels'], dict(status=888888, ticket_panel=666666, ticket_log=777777))
        config = runtime.settings(env)[0]
        self.assertEqual(config['discord'], dict(link=True, require_create=False, require_join=True,
                                                 invite='https://discord.gg/example'))
        self.assertNotIn('secret-token', json.dumps(config))
        self.assertEqual(runtime.discord_settings(dict(BABYLON_DISCORD_TOKEN='t', BABYLON_DISCORD_GUILD_ID='123456'))['features'],
                         ['link', 'roles'])

    def test_invalid_discord_settings_are_rejected(self):
        base = dict(BABYLON_DISCORD_TOKEN='t', BABYLON_DISCORD_GUILD_ID='123456')
        for values in (dict(BABYLON_DISCORD_TOKEN='t'),
                       dict(base, BABYLON_DISCORD_FEATURES='link,dance'),
                       dict(base, BABYLON_DISCORD_FEATURES='voice'),
                       dict(base, BABYLON_DISCORD_FEATURES='tickets'),
                       dict(base, BABYLON_DISCORD_FEATURES='roles', BABYLON_REQUIRE_DISCORD_TO_CREATE='true'),
                       dict(BABYLON_REQUIRE_DISCORD_TO_JOIN='true'),
                       dict(base, BABYLON_DISCORD_SELF_ROLES='12,abc'),
                       dict(base, BABYLON_DISCORD_STATUS_CHANNEL='#status'),
                       dict(base, BABYLON_DISCORD_INVITE='discord.gg/x'),
                       dict(base, BABYLON_REQUIRE_DISCORD_TO_JOIN='maybe')):
            with self.subTest(values=values), self.assertRaises(ValueError):
                runtime.discord_settings(values)

    def test_invalid_ports_and_unsafe_environment_are_rejected(self):
        for values in (
            dict(BABYLON_API_PORT='1361'), dict(BABYLON_API_PORT='1400'),
            dict(BABYLON_LOBBY_PORT='1401'), dict(BABYLON_WORLD_PORT_LAST='1399'),
            dict(BABYLON_WORLD_PORT_FIRST='65536'), dict(BABYLON_MAX_RUNNING_WORLDS='100'),
            dict(BABYLON_MAX_PLAYERS_PER_WORLD='0'), dict(BABYLON_EMPTY_GRACE_SECONDS='1.5'),
            dict(BABYLON_PUBLIC_HOST='https://station.example.org'),
            dict(BABYLON_SERVER_NAME='Name\nSQL_ENABLED'), dict(BABYLON_ADMINS='Guest123'),
            dict(BABYLON_AFK_TIMEOUT_SECONDS='-1'), dict(BABYLON_AFK_TIMEOUT_SECONDS='1.5'),
        ):
            with self.subTest(values=values), self.assertRaises(ValueError):
                runtime.settings(values)

    def test_write_private_runtime_configuration_without_touching_template(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            template = folder / 'template'
            config_dir = template / 'container/default-config'
            config_dir.mkdir(parents=True)
            (config_dir / 'config.txt').write_text('$include comms.txt\n')
            (config_dir / 'comms.txt').write_text('# generated by supervisor\n')
            output = folder / 'runtime'
            config, lobby, limits = runtime.write_settings(
                dict(BABYLON_DATA_DIRECTORY=str(folder / 'data'), BABYLON_SERVER_NAME='Test station'),
                output, template)
            self.assertEqual(json.loads((output / 'supervisor.json').read_text())['admins'], [])
            self.assertEqual(config['lobby_secret'], lobby['secret'])
            self.assertIn('SERVERNAME Test station', (output / 'game-config/config.txt').read_text())
            self.assertNotIn('SERVERNAME', (config_dir / 'config.txt').read_text())


class LobbyHubListing(unittest.TestCase):
    """The hub keeps the first announcement: with a wrong password the lobby is listed only
    while someone is connected. It must start invisible and become visible only after the
    configured password is set."""

    def test_lobby_announces_itself_only_with_the_configured_password(self):
        source = (Path(__file__).resolve().parents[2] / "modular_babylon/lobby/lobby.dm").read_text()
        world_block = source.split("/world/New()")[0]
        self.assertRegex(world_block, r"\n\tvisibility = 0\n")
        self.assertNotIn("SORRYNOPASSWORD", world_block)
        new_proc = source.split("/world/New()")[1].split("\n/")[0]
        self.assertLess(new_proc.index('hub_password = lobby_config["hub_password"]'), new_proc.index("visibility = 1"))


class DefaultGameConfig(unittest.TestCase):
    """Babylon's default config does not include upstream's files, so settings players
    rely on must be set in it explicitly."""

    def flags(self):
        directory = Path(__file__).resolve().parents[2] / "container/default-config"
        flags, pending = set(), ["config.txt"]
        while pending:
            name = pending.pop()
            self.assertTrue((directory / name).is_file(), f"$include {name} is missing")
            for line in (directory / name).read_text().splitlines():
                line = line.strip()
                if line.startswith("$include "):
                    pending.append(line.split(None, 1)[1])
                elif line and not line.startswith("#"):
                    flags.add(line.split()[0])
        return flags

    def test_ooc_stays_on_during_the_round_and_moderation_is_logged(self):
        flags = self.flags()
        self.assertIn("OOC_DURING_ROUND", flags)  # otherwise "OOC is globally muted" from round start
        self.assertLessEqual({"LOG_OOC", "LOG_SAY", "LOG_ADMIN", "LOG_ADMINCHAT"}, flags)


class LobbyHtml(unittest.TestCase):
    """The lobby builds HTML from supervisor data (world names, descriptions, errors ...).
    Every such value must go through html_encode, url_encode or lobby_number."""

    def test_lobby_html_never_interpolates_raw_supervisor_data(self):
        import re
        source = (Path(__file__).resolve().parents[2] / "modular_babylon/lobby/lobby.dm").read_text()
        data = r"(card|result|limits|discord|params|summary|lobby_config|code_result|unlink_result|history|status|current|payload)"
        raw = re.compile(r"(?<![\w\]])\[" + data + r"\[")
        offenders = [line.strip()[:120] for line in source.splitlines()
                     if ("<" in line.replace("<<", "") or re.search(r"\b(rendered|content)\s*\+?=", line))
                     and not line.strip().startswith("world.log") and raw.search(line)]
        self.assertEqual(offenders, [])
