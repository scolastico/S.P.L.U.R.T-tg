import json
from pathlib import Path
import tempfile
import threading
import time
import unittest

from supervisor import Denied, Supervisor


class FakeDriver:
    def __init__(self):
        self.runs = {}
        self.starts = 0
        self.fail_save = False

    def start(self, world, run):
        self.starts += 1
        self.runs[run["id"]] = dict(run, players=[], ready=True)
        return 123

    def alive(self, run):
        return run["id"] in self.runs

    def status(self, run):
        r = self.runs[run["id"]]
        return dict(world=r["world"], run=r["id"], players=r["players"], ready=r["ready"])

    def stop(self, run):
        if self.fail_save:
            return {"error": "disk full"}
        del self.runs[run["id"]]
        return {"ok": True}

    def ahelp_reply(self, run, payload):
        self.replies = getattr(self, "replies", []) + [(run["id"], payload)]
        if payload["ckey"] == "gone":
            return {"ok": 0, "result": "The player is no longer in this world"}
        return {"ok": 1, "result": "Message Successful"}


class Policies(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.driver = FakeDriver()
        self.now = 1000
        self.config = dict(data_directory=self.temp.name, max_worlds_per_player=3,
                           max_running_worlds_per_player=1, max_running_worlds=2,
                           max_players_per_world=2, port_first=1400, port_last=1402,
                           ticket_lifetime_seconds=60, empty_grace_seconds=120,
                           startup_timeout_seconds=300, public_host="localhost", admins=["admin"])
        self.s = Supervisor(self.config, self.driver, lambda: self.now)

    def tearDown(self):
        for _ in range(100):
            if not self.s.stop_workers:
                break
            time.sleep(.01)
        self.s.db.close()
        self.temp.cleanup()

    def create(self, actor="owner", **kwargs):
        return self.s.dispatch(actor, "create", dict(name="World", visibility="public", **kwargs))["id"]

    def start(self, world, actor="owner", **kwargs):
        self.assertTrue(self.s.dispatch(actor, "join", dict(world=world, **kwargs))["pending"])
        self.s.tick()
        return self.s.row("SELECT * FROM runs WHERE world=?", (world,))

    def ticket(self, world, actor="owner", **kwargs):
        result = self.s.dispatch(actor, "join", dict(world=world, **kwargs))
        return result["address"].split("babylon_ticket=")[1]

    def test_private_members_and_admin(self):
        w = self.s.dispatch("owner", "create", {"name": "Private", "visibility": "private"})["id"]
        self.assertEqual(self.s.dispatch("stranger", "list", {})["worlds"], [])
        with self.assertRaises(Denied):
            self.s.dispatch("stranger", "join", {"world": w})
        self.s.dispatch("owner", "member", {"world": w, "member": "friend"})
        run = self.start(w, "friend")
        token = self.ticket(w, "admin")
        self.assertEqual(self.s.redeem(run["id"], run["secret"], token, "admin")["role"], "admin")

    def test_showcase_guest_visits_while_members_and_admins_play(self):
        world = self.s.dispatch("owner", "create", dict(name="Showcase", visibility="showcase", max_players=2))["id"]
        self.assertEqual(self.s.dispatch("visitor", "list", {})["worlds"][0]["visibility"], "showcase")
        self.s.dispatch("owner", "member", dict(world=world, member="friend"))
        run = self.start(world)
        for actor, expected in (("visitor", "showcase"), ("friend", "player"), ("owner", "player"), ("admin", "player")):
            with self.subTest(actor=actor):
                token = self.ticket(world, actor)
                result = self.s.redeem(run["id"], run["secret"], token, actor)
                self.assertEqual(result["mode"], expected)
                self.s.db.execute("DELETE FROM sessions")

    def test_showcase_mode_is_decided_at_redemption_not_from_join_payload(self):
        world = self.s.dispatch("owner", "create", dict(name="Showcase", visibility="showcase"))["id"]
        run = self.start(world)
        token = self.ticket(world, "visitor", mode="player", role="owner")
        self.assertEqual(self.s.redeem(run["id"], run["secret"], token, "visitor")["mode"], "showcase")
        token = self.ticket(world, "upgraded")
        self.s.dispatch("owner", "member", dict(world=world, member="upgraded"))
        # Membership changes revoke that actor's pending ticket.
        with self.assertRaises(Denied):
            self.s.redeem(run["id"], run["secret"], token, "upgraded")
        token = self.ticket(world, "upgraded")
        self.assertEqual(self.s.redeem(run["id"], run["secret"], token, "upgraded")["mode"], "player")

    def test_showcase_tickets_fail_when_world_becomes_private(self):
        world = self.s.dispatch("owner", "create", dict(name="Showcase", visibility="showcase"))["id"]
        run = self.start(world)
        token = self.ticket(world, "visitor")
        # Simulate an access change racing with ticket redemption.
        self.s.db.execute("UPDATE worlds SET visibility='private' WHERE id=?", (world,))
        with self.assertRaisesRegex(Denied, "Access has changed"):
            self.s.redeem(run["id"], run["secret"], token, "visitor")

    def test_public_guests_still_get_normal_play_mode(self):
        world = self.create()
        run = self.start(world)
        token = self.ticket(world, "visitor")
        self.assertEqual(self.s.redeem(run["id"], run["secret"], token, "visitor")["mode"], "player")

    def test_password_and_no_password_leak(self):
        w = self.s.dispatch("owner", "create", {"name": "Locked", "visibility": "password", "password": "secret"})["id"]
        self.assertNotIn("secret", json.dumps(self.s.dispatch("visitor", "list", {})))
        with self.assertRaises(Denied):
            self.s.dispatch("other", "join", {"world": w, "password": "wrong"})
        run = self.start(w)
        token = self.ticket(w, "other", password="secret")
        self.assertTrue(self.s.redeem(run["id"], run["secret"], token, "other")["ok"])

    def test_ticket_binding_expiry_and_replay(self):
        w = self.create()
        run = self.start(w)
        token = self.ticket(w)
        for run_id, key, actor in ((run["id"], run["secret"], "thief"), (run["id"], "wrong", "owner"), ("oldrun", run["secret"], "owner")):
            with self.assertRaises(Denied):
                self.s.redeem(run_id, key, token, actor)
        self.assertTrue(self.s.redeem(run["id"], run["secret"], token, "owner")["ok"])
        with self.assertRaises(Denied):
            self.s.redeem(run["id"], run["secret"], token, "owner")
        token = self.ticket(w)
        self.now += 61
        with self.assertRaises(Denied):
            self.s.redeem(run["id"], run["secret"], token, "owner")

    def test_quotas_reservations_and_duplicate_starts(self):
        w = self.create()
        run = self.start(w)
        self.ticket(w, "first")
        self.ticket(w, "second")
        with self.assertRaises(Denied):
            self.ticket(w, "third")
        self.assertEqual(self.driver.starts, 1)
        w2 = self.create()
        with self.assertRaises(Denied):
            self.start(w2)
        self.create()
        with self.assertRaises(Denied):
            self.create()
        self.assertEqual(self.s.row("SELECT count(*) n FROM runs")["n"], 1)

    def test_concurrent_join_single_process(self):
        w = self.create()
        for i in range(8):
            self.s.dispatch("owner", "member", {"world": w, "member": "p" + str(i)})
        errors = []
        def join(actor):
            try:
                self.s.dispatch(actor, "join", {"world": w})
            except Exception as error:
                errors.append(error)
        threads = [threading.Thread(target=join, args=("p" + str(i),)) for i in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(errors, [])
        self.assertEqual(self.driver.starts, 1)

    def test_guests_cannot_start_public_password_or_showcase_worlds(self):
        for visibility in ("public", "password", "showcase"):
            with self.subTest(visibility=visibility):
                w = self.s.dispatch("owner", "create", {"name": "Offline", "visibility": visibility, "password": "secret"})["id"]
                with self.assertRaisesRegex(Denied, "offline"):
                    self.s.dispatch("visitor", "join", {"world": w, "password": "secret"})
        self.assertEqual(self.driver.starts, 0)
        self.assertEqual(self.s.row("SELECT count(*) n FROM runs")["n"], 0)

    def test_admin_can_start_private_world(self):
        w = self.s.dispatch("owner", "create", {"name": "Private", "visibility": "private"})["id"]
        self.start(w, "admin")
        self.assertEqual(self.driver.starts, 1)

    def test_offline_edit_and_ownership(self):
        w = self.create()
        with self.assertRaises(Denied):
            self.s.dispatch("other", "edit", {"world": w, "name": "stolen"})
        self.s.dispatch("owner", "edit", {"world": w, "visibility": "private", "name": "changed"})
        self.start(w)
        with self.assertRaises(Denied):
            self.s.dispatch("owner", "edit", {"world": w, "name": "live"})

    def test_removed_members_ticket_invalidated(self):
        w = self.s.dispatch("owner", "create", {"name": "Private", "visibility": "private"})["id"]
        self.s.dispatch("owner", "member", {"world": w, "member": "friend"})
        run = self.start(w)
        token = self.ticket(w, "friend")
        self.s.dispatch("owner", "member", {"world": w, "member": "friend", "role": "remove"})
        with self.assertRaises(Denied):
            self.s.redeem(run["id"], run["secret"], token, "friend")

    def test_empty_stop_and_save_failure(self):
        w = self.create()
        run = self.start(w)
        token = self.ticket(w)
        self.now += 50
        self.s.tick()
        self.assertIsNone(self.s.row("SELECT * FROM runs")["empty_since"])
        self.now += 20
        self.s.tick()
        self.driver.fail_save = True
        self.now += 121
        self.s.tick()
        for _ in range(100):
            if not self.s.stop_workers:
                break
            time.sleep(.01)
        self.assertEqual(self.s.row("SELECT * FROM runs")["state"], "error")
        self.assertTrue(self.driver.alive(run))
        with self.assertRaises(Denied):
            self.s.redeem(run["id"], run["secret"], token, "owner")
        self.driver.fail_save = False
        self.s.dispatch("owner", "stop", {"world": w})
        for _ in range(100):
            if not self.s.stop_workers:
                break
            time.sleep(.01)
        self.s.tick()
        self.assertIsNone(self.s.row("SELECT * FROM runs"))

    def test_summary_counts_players_across_running_worlds_without_actor(self):
        self.assertEqual(self.s.dispatch("", "summary", {}), {"ok": True, "running_worlds": 0, "admin_worlds": 0, "players": 0})
        one, two = self.start(self.create("one"), "one"), self.start(self.create("two"), "two")
        self.driver.runs[one["id"]]["players"] = ["alice", "bob"]
        self.driver.runs[two["id"]]["players"] = ["carol"]
        self.s.tick()
        summary = self.s.dispatch("", "summary", {})
        self.assertEqual((summary["running_worlds"], summary["players"]), (2, 3))
        self.assertNotIn("worlds", summary)

    def test_restart_keeps_worlds_and_reconciles_child(self):
        w = self.create()
        self.start(w)
        self.s.db.close()
        self.s = Supervisor(self.config, self.driver, lambda: self.now)
        self.s.tick()
        self.assertEqual(self.s.dispatch("owner", "list", {})["worlds"][0]["state"], "running")

    def test_global_limit_across_owners(self):
        for actor in ("one", "two"):
            self.start(self.create(actor), actor)
        w = self.create("three")
        with self.assertRaises(Denied):
            self.start(w, "three")
        self.assertEqual(self.driver.starts, 2)

    def test_redeemed_seats_count_before_next_heartbeat(self):
        w = self.create()
        run = self.start(w)
        for actor in ("one", "two"):
            token = self.ticket(w, actor)
            self.s.redeem(run["id"], run["secret"], token, actor)
        with self.assertRaises(Denied):
            self.ticket(w, "three")
        token = self.ticket(w, "admin")
        self.assertTrue(self.s.redeem(run["id"], run["secret"], token, "admin")["ok"])

    def test_settings_validation(self):
        for payload in ({"visibility": "invalid"}, {"visibility": "password"},
                        {"max_players": 999}, {"max_players": 0}, {"name": ""}):
            with self.assertRaises(Denied):
                self.s.dispatch("owner", "create", payload)
        self.assertEqual(self.s.dispatch("owner", "list", {})["worlds"], [])


if __name__ == "__main__":
    unittest.main()
