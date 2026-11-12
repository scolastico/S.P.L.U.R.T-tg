"""One log stream for the whole cluster: every line on stdout carries a prefix
naming its source ([supervisor], [lobby], [world <name> <id>]), so `docker logs`
shows the supervisor, the lobby and each child world in one place."""
import re
import sys
import threading
import time
from pathlib import Path

_lock = threading.Lock()
_unsafe = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")
_control = re.compile(r"[\x00-\x1f\x7f]")


def emit(source, text):
    """Write text (possibly several lines) to stdout, each line prefixed."""
    lines = str(text).replace("\r\n", "\n").replace("\r", "\n").rstrip("\n").split("\n")
    with _lock:
        for line in lines:
            sys.stdout.write("[%s] %s\n" % (source, _unsafe.sub("", line)))
        sys.stdout.flush()


def log(text):
    emit("supervisor", text)


def world_source(world):
    name = _control.sub("", str(world.get("name") or "world")).strip()[:40] or "world"
    return "world %s %s" % (name, str(world["id"])[:8])


def pump(stream, source):
    """Forward a child's stdout pipe line by line; returns the reader thread."""
    def run():
        with stream:
            for raw in iter(stream.readline, b""):
                emit(source, raw.decode("utf-8", "replace"))
    thread = threading.Thread(target=run, daemon=True)
    thread.start()
    return thread


class Follower:
    """Tails log files that DreamDaemon writes itself.

    /tg/ code moves world.log from the daemon's stdout into the round's
    data/logs/.../dd.log a few seconds after start, so a child world's output
    lives in two files: daemon.log (startup) and the newest round's dd.log.
    """

    def __init__(self, source, root, alive, started=None, interval=1.0):
        self.source = source
        self.root = Path(root)
        self.alive = alive
        self.started = time.time() if started is None else started
        self.interval = interval
        self.offsets = {}
        daemon = self.root / "daemon.log"
        # daemon.log is appended to across runs; only forward this run's part.
        self.offsets[daemon] = daemon.stat().st_size if daemon.exists() else 0
        self.partial = {}

    def paths(self):
        found = [self.root / "daemon.log"]
        for path in self.root.glob("data/logs/*/*/*/round-*/dd.log"):
            try:
                if path.stat().st_mtime >= self.started - 5:
                    found.append(path)
            except OSError:
                pass
        return found

    def drain(self):
        for path in self.paths():
            try:
                with path.open("rb") as handle:
                    handle.seek(self.offsets.get(path, 0))
                    chunk = handle.read()
                    self.offsets[path] = handle.tell()
            except OSError:
                continue
            if not chunk:
                continue
            data = self.partial.pop(path, b"") + chunk
            complete, _, rest = data.rpartition(b"\n")
            if rest:
                self.partial[path] = rest
            if complete:
                emit(self.source, complete.decode("utf-8", "replace"))

    def run(self):
        while True:
            running = self.alive()
            self.drain()
            if not running:
                for path, rest in list(self.partial.items()):
                    emit(self.source, rest.decode("utf-8", "replace"))
                return
            time.sleep(self.interval)

    def start(self):
        thread = threading.Thread(target=self.run, daemon=True)
        thread.start()
        return thread
