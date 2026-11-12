import importlib.util
from pathlib import Path
import tempfile
import time
import types
import unittest

from supervisor import Denied, Supervisor
from test_supervisor import FakeDriver

HAS_DISCORD = importlib.util.find_spec("discord") is not None


class DiscordLinks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.now = 1000
        self.config = dict(data_directory=self.temp.name, max_worlds_per_player=3,
                           max_running_worlds_per_player=1, max_running_worlds=2,
                           max_players_per_world=2, port_first=1400, port_last=1402,
                           ticket_lifetime_seconds=60, empty_grace_seconds=120,
                           startup_timeout_seconds=300, public_host="localhost", admins=["admin"],
                           discord=dict(link=True, require_create=False, require_join=False,
                                        invite="https://discord.gg/example"))
        self.s = Supervisor(self.config, FakeDriver(), lambda: self.now)
        self.changes = []
        self.s.discord_link_changed = lambda *change: self.changes.append(change)

    def tearDown(self):
        self.s.db.close()
        self.temp.cleanup()

    def code(self, actor="player"):
        return self.s.dispatch(actor, "discord_code", {})["code"]

    def test_code_links_once_and_shows_in_the_lobby_list(self):
        state = self.s.dispatch("player", "list", {})["discord"]
        self.assertEqual((state["link"], state["linked"], state["invite"]), (True, False, "https://discord.gg/example"))
        code = self.code()
        self.assertRegex(code, r"^[A-Z2-9]{4}-[A-Z2-9]{4}$")
        # Players may type it in lower case and without the dash.
        self.assertEqual(self.s.redeem_discord_code(code.replace("-", "").lower(), 123456789, "someone"), "player")
        state = self.s.dispatch("player", "list", {})["discord"]
        self.assertEqual((state["linked"], state["name"]), (True, "someone"))
        self.assertEqual(self.changes, [("player", "123456789", True)])
        with self.assertRaisesRegex(Denied, "invalid or has expired"):
            self.s.redeem_discord_code(code, 123456789, "someone")

    def test_codes_expire_and_a_new_code_replaces_the_old_one(self):
        old = self.code()
        new = self.code()
        with self.assertRaises(Denied):
            self.s.redeem_discord_code(old, 123456789, "a")
        self.now += 601
        with self.assertRaises(Denied):
            self.s.redeem_discord_code(new, 123456789, "a")

    def test_one_discord_account_per_byond_account(self):
        self.s.redeem_discord_code(self.code("first"), 123456789, "a")
        self.s.redeem_discord_code(self.code("second"), 123456789, "a")
        self.assertIsNone(self.s.discord_link("first"))
        self.assertEqual(self.s.discord_link_by_id(123456789)["ckey"], "second")

    def test_unlink_from_the_lobby_or_discord(self):
        self.s.redeem_discord_code(self.code(), 123456789, "a")
        self.assertTrue(self.s.dispatch("player", "discord_unlink", {})["unlinked"])
        self.assertFalse(self.s.dispatch("player", "discord_unlink", {})["unlinked"])
        self.s.redeem_discord_code(self.code(), 123456789, "a")
        self.assertEqual(self.s.unlink_discord(discord_id=123456789)["ckey"], "player")
        self.assertEqual([c[2] for c in self.changes], [True, False, True, False])

    def test_linking_disabled(self):
        self.config["discord"]["link"] = False
        with self.assertRaisesRegex(Denied, "not enabled"):
            self.code()
        self.assertFalse(self.s.dispatch("player", "list", {})["discord"]["link"])

    def test_requirements_gate_create_and_join_but_not_admins(self):
        world = self.s.dispatch("owner", "create", dict(name="World", visibility="public"))["id"]
        self.config["discord"].update(require_create=True, require_join=True)
        with self.assertRaisesRegex(Denied, "Link your Discord account to create"):
            self.s.dispatch("player", "create", dict(name="Mine", visibility="public"))
        with self.assertRaisesRegex(Denied, "Link your Discord account to join"):
            self.s.dispatch("player", "join", dict(world=world))
        self.assertTrue(self.s.dispatch("admin", "create", dict(name="Admin", visibility="public"))["ok"])
        self.s.redeem_discord_code(self.code(), 123456789, "a")
        mine = self.s.dispatch("player", "create", dict(name="Mine", visibility="public"))["id"]
        # A linked account that left the Discord server is refused; unknown membership is allowed.
        self.s.discord_membership = lambda discord_id: False
        with self.assertRaisesRegex(Denied, "not on our Discord"):
            self.s.dispatch("player", "join", dict(world=world))
        self.s.discord_membership = lambda discord_id: None
        self.assertTrue(self.s.dispatch("player", "join", dict(world=mine))["pending"])

    def test_only_join_required(self):
        self.config["discord"].update(require_join=True)
        self.assertTrue(self.s.dispatch("player", "create", dict(name="Mine", visibility="public"))["ok"])

    def test_status_snapshot_hides_private_world_names(self):
        public = self.s.dispatch("owner", "create", dict(name="Open", visibility="public"))["id"]
        private = self.s.dispatch("admin", "create", dict(name="Secret", visibility="private"))["id"]
        self.s.dispatch("owner", "join", dict(world=public))
        self.s.dispatch("admin", "join", dict(world=private))
        snapshot = self.s.status_snapshot()
        self.assertEqual(sorted(str(w["name"]) for w in snapshot["worlds"]), ["None", "Open"])
        self.assertEqual((snapshot["total_worlds"], snapshot["max_running_worlds"]), (2, 2))


@unittest.skipUnless(HAS_DISCORD, "discord.py is not installed")
class BotHelpers(unittest.TestCase):
    def setUp(self):
        import discord_bot
        self.bot = discord_bot

    def test_log_lines_are_split_into_code_blocks_below_the_limit(self):
        blocks = self.bot.chunk_lines(["x" * 1000, "y" * 1000, "```z"])
        self.assertEqual(len(blocks), 2)
        self.assertTrue(all(b.startswith("```\n") and b.endswith("```") and len(b) <= 2000 for b in blocks))
        self.assertNotIn("```z", blocks[1][3:-3])

    def test_status_embed_lists_running_worlds_without_private_names(self):
        snapshot = {"worlds": [{"name": "Open", "visibility": "public", "state": "running", "players": 2, "max_players": 4},
                               {"name": None, "visibility": "private", "state": "starting", "players": 0, "max_players": 4},
                               {"name": "Old", "visibility": "public", "state": "stopping", "players": 0, "max_players": 4}],
                    "total_worlds": 5, "max_running_worlds": 4, "players": 2}
        embed = self.bot.status_embed(snapshot, {"join_url": "https://example.org/join/", "address": "byond://h:1"})
        fields = {f.name: f.value for f in embed.fields}
        self.assertEqual(fields["Running worlds"], "2/4")
        self.assertIn("**Open** (public): 2/4 players", fields["Now running"])
        self.assertIn("*A private world* (private): starting", fields["Now running"])
        self.assertNotIn("Old", fields["Now running"])
        self.assertIn("Offline", self.bot.status_embed(None, {}, online=False).description)

    def test_transcript_contains_every_message_and_attachment(self):
        author = type("Author", (), {"id": 42, "__str__": lambda self: "member"})()
        import datetime
        message = types.SimpleNamespace(created_at=datetime.datetime(2026, 11, 12, 14, 0, tzinfo=datetime.timezone.utc),
                                        author=author, content="It crashes", embeds=[],
                                        attachments=[types.SimpleNamespace(filename="log.txt", url="https://cdn/log.txt")])
        text = self.bot.transcript_text({"number": 7, "owner": 42, "owner_name": "member", "opened": 0, "topic": "Crash"},
                                        [message])
        self.assertIn("Babylon13 ticket #0007", text)
        self.assertIn("[2026-11-12 14:00:00 UTC] member (42): It crashes", text)
        self.assertIn("[attachment] log.txt https://cdn/log.txt", text)
        self.assertEqual(self.bot.ticket_slug("Some Body!!"), "some-body")

    def ticket_panel_requests(self, history):
        import asyncio
        requests = []

        class Http:
            async def request(self, route, json=None):
                requests.append((route.method, route.path, route.channel_id, json))

        async def messages(limit):
            for message in history:
                yield message

        channel = types.SimpleNamespace(id=5, history=messages)
        client = types.SimpleNamespace(http=Http(), user=types.SimpleNamespace(id=1), channel=lambda name: channel)
        client.post_components = types.MethodType(self.bot.BabylonBot.post_components, client)
        asyncio.run(self.bot.BabylonBot.ensure_ticket_panel(client))
        return requests

    def test_ticket_panel_is_posted_once_and_edited_on_later_starts(self):
        (method, path, channel, body), = self.ticket_panel_requests([])
        self.assertEqual((method, path, channel), ("POST", "/channels/{channel_id}/messages", 5))
        self.assertEqual(body["components"][0]["components"][0]["custom_id"], self.bot.TICKET_OPEN)
        mine = types.SimpleNamespace(id=9, author=types.SimpleNamespace(id=1))
        other = types.SimpleNamespace(id=8, author=types.SimpleNamespace(id=2))
        (method, path, channel, body), = self.ticket_panel_requests([other, mine])
        self.assertEqual((method, path), ("PATCH", "/channels/{channel_id}/messages/{message_id}"))

    def test_background_loops_survive_a_failing_run(self):
        import asyncio
        runs = []

        async def step():
            runs.append(len(runs))
            if len(runs) == 1:
                raise RuntimeError("first run fails")
            if len(runs) == 3:
                client.closed = True

        client = types.SimpleNamespace(closed=False)
        client.is_closed = lambda: client.closed
        asyncio.run(self.bot.BabylonBot.repeat(client, "test", step, 0))
        self.assertEqual(runs, [0, 1, 2])

    def test_status_loop_starts_even_when_a_startup_step_fails(self):
        import asyncio
        started, errors = [], []

        async def nothing(*args, **kwargs):
            pass

        async def broken():
            raise TypeError("panel")

        async def on_error(event, *args, **kwargs):
            errors.append(event)

        async def run():
            loop = asyncio.get_running_loop()
            client = types.SimpleNamespace(
                guild=types.SimpleNamespace(name="Guild"), settings={"guild_id": 1}, user="bot",
                features={"status", "tickets", "voice"}, loop_ref=loop, send=nothing,
                cleanup_voice_rooms=nothing, ensure_ticket_panel=broken, on_error=on_error,
                status_loop=lambda: nothing(started.append(True)))
            await self.bot.BabylonBot.on_ready(client)
            await asyncio.sleep(0)

        asyncio.run(run())
        self.assertEqual(started, [True])
        self.assertEqual(errors, ["on_ready (ticket panel)"])

    def test_background_loops_use_repeat(self):
        source = (Path(__file__).parent / "discord_bot.py").read_text()
        self.assertEqual(source.count("while not self.is_closed()"), 1, "loop through BabylonBot.repeat")

    def test_raw_http_goes_through_request_only(self):
        # discord.py's http helpers take multipart parameters; calling them with keywords
        # fails at runtime only. Raw calls must use http.request with a Route.
        import re
        source = (Path(__file__).parent / "discord_bot.py").read_text()
        self.assertEqual(set(re.findall(r"(?<!discord)\.http\.(\w+)\(", source)), {"request"})


if __name__ == "__main__":
    unittest.main()
