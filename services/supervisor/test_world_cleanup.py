import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

from supervisor import Denied, Supervisor, load_config
from test_supervisor import FakeDriver
from world_storage import delete_world_data


class Expiry(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.now = 1000
        self.config = dict(data_directory=self.temp.name, max_worlds_per_player=3,
                           max_running_worlds_per_player=1, max_running_worlds=2,
                           max_players_per_world=2, port_first=1400, port_last=1402,
                           ticket_lifetime_seconds=60, empty_grace_seconds=120,
                           startup_timeout_seconds=300, public_host="localhost", admins=[])
        self.driver = FakeDriver()
        self.s = Supervisor(self.config, self.driver, lambda: self.now)
        self.world = self.s.dispatch("owner", "create", {"name": "Old world"})["id"]
        self.path = Path(self.temp.name) / "worlds" / self.world
        self.path.mkdir(parents=True)
        (self.path / "progress.txt").write_text("only this world")

    def tearDown(self):
        self.s.db.close()
        self.temp.cleanup()

    def test_owner_delete_requires_confirmation_and_removes_all_world_data(self):
        self.s.dispatch("owner", "member", {"world": self.world, "member": "friend"})
        saved = self.path / "data/babylon/saves/checkpoint"
        saved.mkdir(parents=True)
        (saved / "state.json").write_text("saved progress")
        other = self.s.dispatch("owner", "create", {"name": "Keep this"})["id"]
        other_path = Path(self.temp.name) / "worlds" / other
        other_path.mkdir()
        (other_path / "keep.txt").write_text("untouched")
        with self.assertRaises(Denied):
            self.s.dispatch("owner", "delete", {"world": self.world})
        self.assertTrue(self.path.exists())
        result = self.s.dispatch("owner", "delete", {"world": self.world, "confirm_delete": 1})
        self.assertTrue(result["ok"])
        self.assertFalse(result["cleanup_pending"])
        self.assertFalse(self.path.exists())
        self.assertEqual((other_path / "keep.txt").read_text(), "untouched")
        self.assertIsNone(self.s.row("SELECT * FROM worlds WHERE id=?", (self.world,)))
        self.assertEqual(self.s.row("SELECT count(*) n FROM members WHERE world=?", (self.world,))["n"], 0)
        self.assertEqual(self.s.row("SELECT count(*) n FROM audit WHERE action='delete_world'")["n"], 1)

    def test_members_and_guests_cannot_delete_but_admin_can(self):
        self.s.dispatch("owner", "member", {"world": self.world, "member": "friend"})
        for actor in ("friend", "outsider"):
            with self.assertRaises(Denied):
                self.s.dispatch(actor, "delete", {"world": self.world, "confirm_delete": 1})
        self.s.admins.add("admin")
        self.assertTrue(self.s.dispatch("admin", "delete", {"world": self.world, "confirm_delete": 1})["ok"])

    def test_delete_rejects_every_live_run_state(self):
        self.s.dispatch("owner", "join", {"world": self.world})
        for state in ("starting", "running", "stopping", "error"):
            with self.s.db:
                self.s.db.execute("UPDATE runs SET state=? WHERE world=?", (state, self.world))
            with self.assertRaisesRegex(Denied, "Stop the world"):
                self.s.dispatch("owner", "delete", {"world": self.world, "confirm_delete": 1})
        self.assertTrue(self.path.exists())

    def test_manual_deletion_retries_filesystem_failure_and_releases_quota(self):
        self.config["max_worlds_per_player"] = 1
        with patch("supervisor.delete_world_data", side_effect=OSError("locked file")):
            result = self.s.dispatch("owner", "delete", {"world": self.world, "confirm_delete": 1})
        self.assertTrue(result["cleanup_pending"])
        self.assertTrue(self.path.exists())
        self.assertIsNotNone(self.s.row("SELECT * FROM world_deletions WHERE world=?", (self.world,)))
        self.assertEqual(self.s.dispatch("owner", "list", {})["worlds"], [])
        self.s.dispatch("owner", "create", {"name": "Replacement"})
        self.s.cleanup_unused_worlds()
        self.assertFalse(self.path.exists())
        self.assertIsNone(self.s.row("SELECT * FROM world_deletions WHERE world=?", (self.world,)))

    def test_default_sixty_days_removes_stopped_world_and_members(self):
        self.s.dispatch("owner", "member", {"world": self.world, "member": "friend"})
        self.now += 59 * 86400
        self.s.cleanup_unused_worlds()
        self.assertTrue(self.path.exists())
        self.now += 86400
        self.s.cleanup_unused_worlds()
        self.assertFalse(self.path.exists())
        self.assertIsNone(self.s.row("SELECT * FROM worlds WHERE id=?", (self.world,)))
        self.assertEqual(self.s.row("SELECT count(*) n FROM members")["n"], 0)
        self.assertEqual(self.s.row("SELECT count(*) n FROM world_deletions")["n"], 0)

    def test_running_world_is_protected_and_play_resets_activity(self):
        self.s.dispatch("owner", "join", {"world": self.world})
        self.now += 70 * 86400
        run = self.s.row("SELECT * FROM runs")
        self.driver.runs[run["id"]]["players"] = ["owner"]
        self.s.tick()
        self.assertTrue(self.path.exists())
        self.assertEqual(self.s.world(self.world)["last_used"], self.now)

    def test_owner_edits_reset_timer_browsing_does_not(self):
        self.now += 59 * 86400
        self.s.dispatch("owner", "list", {})
        self.assertEqual(self.s.world(self.world)["last_used"], 1000)
        self.s.dispatch("owner", "edit", {"world": self.world, "name": "Still using it"})
        self.now += 2 * 86400
        self.s.cleanup_unused_worlds()
        self.assertTrue(self.path.exists())

    def test_disabled_expiry(self):
        self.config["delete_unused_worlds_after_days"] = 0
        self.now += 500 * 86400
        self.s.cleanup_unused_worlds()
        self.assertTrue(self.path.exists())

    def test_custom_period_and_config_validation(self):
        self.config["delete_unused_worlds_after_days"] = 5
        self.now += 6 * 86400
        self.s.cleanup_unused_worlds()
        self.assertFalse(self.path.exists())
        config = json.loads((Path(__file__).parent / "config.example.json").read_text())
        config["lobby_secret"] = "test-only-credential-" * 3
        file = Path(self.temp.name) / "config.json"
        config.pop("delete_unused_worlds_after_days")
        file.write_text(json.dumps(config))
        self.assertEqual(load_config(file)["delete_unused_worlds_after_days"], 60)
        for value in (-1, True, 2.5):
            config["delete_unused_worlds_after_days"] = value
            file.write_text(json.dumps(config))
            with self.assertRaises(ValueError):
                load_config(file)

    def test_interrupted_cleanup_retries_without_restoring_access(self):
        self.now += 60 * 86400
        with patch("supervisor.delete_world_data", side_effect=OSError("busy")):
            self.s.cleanup_unused_worlds()
        self.assertIsNone(self.s.row("SELECT * FROM worlds WHERE id=?", (self.world,)))
        self.assertTrue(self.path.exists())
        self.assertEqual(self.s.row("SELECT count(*) n FROM world_deletions")["n"], 1)
        self.now += 3600
        self.s.cleanup_unused_worlds()
        self.assertFalse(self.path.exists())

    def test_migration_preserves_latest_known_activity(self):
        self.s.db.close()
        connection = sqlite3.connect(Path(self.temp.name) / "supervisor.sqlite3")
        connection.execute("ALTER TABLE worlds DROP COLUMN last_used")
        connection.execute("INSERT INTO audit VALUES(?,?,?,?)", (9999, "owner", "admit", self.world))
        connection.commit()
        connection.close()
        self.s = Supervisor(self.config, self.driver, lambda: self.now)
        self.assertEqual(self.s.world(self.world)["last_used"], 9999)

    def test_filesystem_cleanup_is_confined_to_named_world(self):
        other = Path(self.temp.name) / "worlds" / ("b" * 32)
        other.mkdir()
        (other / "keep.txt").write_text("keep")
        delete_world_data(self.temp.name, self.world)
        self.assertTrue((other / "keep.txt").exists())
        for world in ("..", "../outside", "worlds"):
            with self.assertRaises(ValueError):
                delete_world_data(self.temp.name, world)

    def test_world_link_cannot_delete_another_directory(self):
        outside = Path(self.temp.name) / "outside"
        outside.mkdir()
        linked = Path(self.temp.name) / "worlds" / ("c" * 32)
        try:
            linked.symlink_to(outside, target_is_directory=True)
        except OSError:
            self.skipTest("Symlinks unavailable")
        with self.assertRaises(ValueError):
            delete_world_data(self.temp.name, "c" * 32)
        self.assertTrue(outside.exists())


if __name__ == "__main__":
    unittest.main()
