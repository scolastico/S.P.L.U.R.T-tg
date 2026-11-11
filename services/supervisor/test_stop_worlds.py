from pathlib import Path
import sqlite3
import tempfile
import unittest

from stop_worlds import running_worlds, stop_worlds


class Shutdown(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.config = dict(data_directory=self.temp.name)
        self.database = Path(self.temp.name) / 'supervisor.sqlite3'
        self.db = sqlite3.connect(self.database)
        self.db.executescript('CREATE TABLE worlds(id,owner); CREATE TABLE runs(world,state,error);')

    def tearDown(self):
        self.db.close()
        self.temp.cleanup()

    def world(self, name, owner):
        with self.db:
            self.db.execute('INSERT INTO worlds VALUES(?,?)', (name, owner))
            self.db.execute("INSERT INTO runs VALUES(?,'running',NULL)", (name,))

    def test_stopped_cluster_is_noop(self):
        stop_worlds(self.config, request=lambda *_: self.fail('No stop request expected'))
        self.assertEqual(running_worlds(self.database), [])

    def test_every_world_is_requested_and_exit_is_waited_for(self):
        self.world('a', 'alice')
        self.world('b', 'bob')
        requests = []
        def stop(actor, world):
            requests.append((actor, world))
            with self.db:
                self.db.execute("UPDATE runs SET state='stopping' WHERE world=?", (world,))
        def exited(_):
            self.assertEqual(len(running_worlds(self.database)), 2)
            with self.db:
                self.db.execute('DELETE FROM runs')
        stop_worlds(self.config, request=stop, sleep=exited)
        self.assertEqual(requests, [('alice', 'a'), ('bob', 'b')])

    def test_save_failure_is_reported_and_run_is_retained(self):
        self.world('a', 'alice')
        def failed(*_):
            with self.db:
                self.db.execute("UPDATE runs SET state='error',error='disk full'")
        with self.assertRaisesRegex(RuntimeError, 'disk full'):
            stop_worlds(self.config, request=failed)
        self.assertEqual(len(running_worlds(self.database)), 1)

    def test_shutdown_waits_for_starting_world_before_requesting_save(self):
        self.world('a', 'alice')
        with self.db:
            self.db.execute("UPDATE runs SET state='starting'")
        ready = []
        def initialized(_):
            ready.append(True)
            with self.db:
                self.db.execute("UPDATE runs SET state='running'")
        def stopped(*_):
            self.assertTrue(ready)
            with self.db:
                self.db.execute('DELETE FROM runs')
        stop_worlds(self.config, request=stopped, sleep=initialized)

    def test_timeout_does_not_remove_or_kill_world(self):
        self.world('a', 'alice')
        with self.assertRaises(TimeoutError):
            stop_worlds(self.config, timeout=0, request=lambda *_: None)
        self.assertEqual(len(running_worlds(self.database)), 1)
