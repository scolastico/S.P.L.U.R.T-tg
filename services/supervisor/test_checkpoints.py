import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from checkpoints import Checkpoints, CheckpointError, atomic_json
from supervisor import Supervisor, Driver, Denied, load_config
from test_supervisor import FakeDriver


def seed(store, world, count, commit=True):
    generation = f"save-20261109-120000-{count}"
    root = store.root(world)
    path = store.path(root, generation)
    path.mkdir(parents=True, exist_ok=True)
    (path / "map.dmm").write_text(f"map at checkpoint {count}")
    atomic_json(path / "state.json", dict(generation=generation, save_count=count, records=[{"id": count}]))
    if commit:
        atomic_json(root / "latest.json", {"generation": generation})
    return generation


class Storage(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = Checkpoints(self.temp.name)
        self.world = "a" * 32

    def tearDown(self):
        self.temp.cleanup()

    def generations(self):
        return {p.name for p in self.store.root(self.world).glob("save-*")}

    def test_default_retention_orders_same_second_counters_numerically(self):
        points = [seed(self.store, self.world, n) for n in range(1, 13)]
        self.store.retain(self.world)
        self.assertEqual(self.generations(), set(points[-4:]))
        self.assertEqual([p["generation"] for p in self.store.list(self.world)["checkpoints"]], points[-4:][::-1])

    def test_custom_retention_is_scoped_to_one_world(self):
        points = [seed(self.store, self.world, n) for n in range(1, 7)]
        other = "b" * 32
        for n in range(1, 7):
            seed(self.store, other, n)
        Checkpoints(self.temp.name, keep=2).retain(self.world)
        self.assertEqual(self.generations(), set(points[-2:]))
        self.assertEqual(len(self.store.directories(self.store.root(other))), 6)

    def test_next_start_stages_selected_map_and_state(self):
        points = [seed(self.store, self.world, n) for n in range(1, 5)]
        self.store.rollback(self.world, points[1], points[-1])
        template = Path(self.temp.name) / "template"
        template.mkdir()
        (template / "babylon.dmb").write_text("unused fixture binary")
        config_dir = Path(self.temp.name) / "config"
        config_dir.mkdir()
        driver = Driver(dict(data_directory=self.temp.name, template_directory=str(template),
                             config_directory=str(config_dir)))
        prepared = driver.prepare({"id": self.world}, {"secret": "test-only-control"})
        self.assertEqual((prepared / "_maps/babylon/active.dmm").read_text(), "map at checkpoint 2")
        restored = json.loads((prepared / "data/babylon/resume-state.json").read_text())
        self.assertEqual(restored["save_count"], 2)
        self.assertEqual(restored["generation"], points[1])

    def test_pending_generation_and_changed_head_are_not_pruned(self):
        points = [seed(self.store, self.world, n) for n in range(1, 7)]
        pending = seed(self.store, self.world, 7, commit=False)
        (self.store.path(self.store.root(self.world), pending) / "map.dmm").unlink()
        self.store.retain(self.world, expected=points[-2])
        self.assertEqual(len(self.generations()), 7)
        self.store.retain(self.world, expected=points[-1])
        self.assertEqual(self.generations(), set(points[-4:]) | {pending})
        self.assertEqual(len(self.store.list(self.world)["checkpoints"]), 4)

    def test_rollback_deletes_only_newer_points_and_stale_resume(self):
        points = [seed(self.store, self.world, n) for n in range(1, 7)]
        root = self.store.root(self.world)
        resume = root.parent / "resume-state.json"
        resume.write_text("old future state")
        self.store.retain(self.world)
        result = self.store.rollback(self.world, points[2], points[-1])
        self.assertEqual(result["deleted"], 3)
        self.assertEqual(self.generations(), {points[2]})
        self.assertEqual(self.store.head(root), points[2])
        self.assertFalse(resume.exists())
        self.assertEqual((root / points[2] / "map.dmm").read_text(), "map at checkpoint 3")

    def test_interrupted_rollback_finishes_before_history_reopens(self):
        points = [seed(self.store, self.world, n) for n in range(1, 7)]
        with patch.object(self.store, "remove", side_effect=OSError("interrupted deletion")):
            with self.assertRaises(OSError):
                self.store.rollback(self.world, points[1], points[-1])
        root = self.store.root(self.world)
        self.assertTrue((root / "rollback-pending.json").exists())
        self.assertEqual(self.store.head(root), points[1])
        restarted = Checkpoints(self.temp.name)
        restarted.retain(self.world)
        self.assertEqual(self.generations(), set(points[:2]))
        self.assertFalse((root / "rollback-pending.json").exists())

    def test_stale_or_uncommitted_target_leaves_history_unchanged(self):
        points = [seed(self.store, self.world, n) for n in range(1, 5)]
        future = seed(self.store, self.world, 5, commit=False)
        for target, expected in ((points[0], points[-2]), (future, points[-1])):
            with self.assertRaises(CheckpointError):
                self.store.rollback(self.world, target, expected)
        self.assertEqual(self.generations(), set(points) | {future})

    def test_bad_head_does_not_delete_older_saves(self):
        points = [seed(self.store, self.world, n) for n in range(1, 7)]
        (self.store.root(self.world) / points[-1] / "state.json").write_text("incomplete")
        with self.assertRaises(CheckpointError):
            self.store.retain(self.world)
        self.assertEqual(self.generations(), set(points))

    def test_invalid_paths_and_limits(self):
        for name in ("../../elsewhere", "save-20261109-120000-1/../other", None):
            with self.assertRaises(CheckpointError):
                self.store.path(self.store.root(self.world), name)
        with self.assertRaises(CheckpointError):
            self.store.root("../otherworld")
        for count in (0, -1, True, 2.5):
            with self.assertRaises(ValueError):
                Checkpoints(self.temp.name, count)

    def test_linked_directory_cannot_escape_world(self):
        outside = Path(self.temp.name) / "outside"
        outside.mkdir()
        root = self.store.root(self.world)
        root.mkdir(parents=True)
        linked = root / "save-20261109-120000-1"
        try:
            linked.symlink_to(outside, target_is_directory=True)
        except OSError:
            self.skipTest("Creating symlinks is not permitted on this host")
        with self.assertRaises(CheckpointError):
            self.store.remove(root, linked.name)
        self.assertTrue(outside.exists())


class CheckpointPolicies(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.driver = FakeDriver()
        self.config = dict(data_directory=self.temp.name, max_worlds_per_player=3,
                           max_running_worlds_per_player=1, max_running_worlds=2,
                           max_players_per_world=2, port_first=1400, port_last=1402,
                           ticket_lifetime_seconds=60, empty_grace_seconds=120,
                           startup_timeout_seconds=300, public_host="localhost", admins=["admin"])
        self.s = Supervisor(self.config, self.driver)
        self.world = self.s.dispatch("owner", "create", {"name": "History"})["id"]
        self.points = [seed(self.s.checkpoints, self.world, n) for n in range(1, 7)]

    def tearDown(self):
        self.s.db.close()
        self.temp.cleanup()

    def request(self, action, actor="owner", **kwargs):
        return self.s.dispatch(actor, action, dict(world=self.world, **kwargs))

    def test_owner_admin_only_and_offline_only(self):
        self.request("member", member="friend")
        for actor in ("stranger", "friend"):
            with self.assertRaises(Denied):
                self.request("checkpoints", actor)
            with self.assertRaises(Denied):
                self.request("rollback", actor, generation=self.points[2], expected_latest=self.points[-1], confirm_delete_newer=1)
        self.assertEqual(len(self.request("checkpoints", "admin")["checkpoints"]), 4)
        self.request("join")
        for action in ("checkpoints", "rollback"):
            with self.assertRaises(Denied):
                self.request(action, "admin", generation=self.points[2], expected_latest=self.points[-1], confirm_delete_newer=1)

    def test_confirmation_and_stale_selection(self):
        for extra in ({}, {"confirm_delete_newer": False}, {"confirm_delete_newer": 1, "expected_latest": self.points[-2]}):
            payload = dict(generation=self.points[2], expected_latest=self.points[-1])
            payload.update(extra)
            with self.assertRaises(Denied):
                self.request("rollback", **payload)
        result = self.request("rollback", generation=self.points[2], expected_latest=self.points[-1], confirm_delete_newer=1)
        self.assertEqual(result["deleted"], 3)
        self.assertEqual(self.s.last_save(self.world), self.points[2])

    def test_running_save_retention_waits_until_commit_is_not_busy(self):
        self.request("join")
        points = [seed(self.s.checkpoints, self.world, n) for n in range(7, 10)]
        busy = [True]
        def status(run):
            return dict(world=self.world, run=run["id"], players=[], ready=True, busy=busy[0], last_save=points[-1])
        self.driver.status = status
        self.s.tick()
        self.assertEqual(len(self.s.checkpoints.directories(self.s.checkpoints.root(self.world))), 7)
        busy[0] = False
        self.s.tick()
        self.assertEqual(len(self.s.checkpoints.directories(self.s.checkpoints.root(self.world))), 4)

    def test_config_default_and_validation(self):
        config = json.loads((Path(__file__).parent / "config.example.json").read_text())
        config["lobby_secret"] = "test-secret-" * 4
        config.pop("kept_save_points_per_world")
        file = Path(self.temp.name) / "config.json"
        atomic_json(file, config)
        self.assertEqual(load_config(file)["kept_save_points_per_world"], 4)
        config["kept_save_points_per_world"] = 0
        atomic_json(file, config)
        with self.assertRaises(ValueError):
            load_config(file)


if __name__ == "__main__":
    unittest.main()
