"""Bounded checkpoint history and recoverable, stopped-world rollback."""
import json
import os
from pathlib import Path
import re
import shutil
import tempfile


GENERATION = re.compile(r"save-(\d{8}-\d{6})-(\d+)")


class CheckpointError(ValueError):
    pass


def order(generation):
    match = GENERATION.fullmatch(str(generation))
    if not match:
        raise CheckpointError("Invalid checkpoint generation")
    # Counters remain monotonic even across clock changes and within one second.
    return int(match[2]), match[1]


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".checkpoint-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(value, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


class Checkpoints:
    def __init__(self, data_directory, keep=4):
        if type(keep) is not int or keep < 1:
            raise ValueError("kept_save_points_per_world must be a positive integer")
        self.base = Path(data_directory).resolve() / "worlds"
        self.keep = keep
        self.maintained = {}

    def root(self, world):
        if not re.fullmatch(r"[a-f0-9]{32}", str(world)):
            raise CheckpointError("Invalid world identifier")
        directory = self.base / world
        root = directory / "data/babylon/saves"
        if directory.resolve().parent != self.base.resolve() or not root.resolve().is_relative_to(directory.resolve()):
            raise CheckpointError("Checkpoint directory escapes its world")
        return root

    def path(self, root, generation):
        order(generation)
        path = root / generation
        if path.is_symlink() or getattr(path, "is_junction", lambda: False)() or path.resolve().parent != root.resolve():
            raise CheckpointError("Unsafe checkpoint directory")
        return path

    def snapshot(self, root, generation):
        path = self.path(root, generation)
        try:
            state = json.loads((path / "state.json").read_text(encoding="utf-8"))
            if state.get("generation") != generation or not (path / "map.dmm").is_file():
                raise ValueError()
        except (OSError, ValueError, AttributeError):
            raise CheckpointError("Checkpoint is incomplete or damaged") from None
        return {"generation": generation, "objects": len(state.get("records", []))}

    def head(self, root):
        try:
            return json.loads((root / "latest.json").read_text(encoding="utf-8"))["generation"]
        except FileNotFoundError:
            return None
        except (OSError, ValueError, KeyError, TypeError):
            raise CheckpointError("Current checkpoint manifest is damaged") from None

    def directories(self, root):
        if not root.exists():
            return []
        return [p.name for p in root.iterdir() if GENERATION.fullmatch(p.name) and self.path(root, p.name).is_dir()]

    def remove(self, root, generation):
        # Verify the final absolute target immediately before recursive deletion.
        path = self.path(root, generation)
        if path.exists():
            shutil.rmtree(path)

    def recover(self, world):
        root = self.root(world)
        journal = root / "rollback-pending.json"
        if not journal.exists():
            return
        pending = json.loads(journal.read_text(encoding="utf-8"))
        target = pending["target"]
        manifest = self.snapshot(root, target)
        if self.head(root) not in (target, pending["previous"]):
            raise CheckpointError("Rollback recovery conflicts with the current checkpoint")
        # Validate every deletion before changing the committed pointer.
        for generation in pending["delete"]:
            self.path(root, generation)
            if order(generation) <= order(target):
                raise CheckpointError("Invalid rollback deletion")
        atomic_json(root / "latest.json", manifest)
        for generation in pending["delete"]:
            self.remove(root, generation)
        # Cached startup data must not continue referring to the abandoned future.
        (root.parent / "resume-state.json").unlink(missing_ok=True)
        journal.unlink()
        self.maintained.pop(world, None)

    def list(self, world):
        self.recover(world)
        root = self.root(world)
        latest = self.head(root)
        if latest is None:
            return {"latest": None, "checkpoints": []}
        self.snapshot(root, latest)  # Never prune history behind a damaged head.
        points = []
        for generation in sorted(self.directories(root), key=order, reverse=True):
            if order(generation) > order(latest):
                continue  # A partially committed save is not a restore point.
            try:
                point = self.snapshot(root, generation)
            except CheckpointError:
                continue
            point["current"] = generation == latest
            points.append(point)
        return {"latest": latest, "checkpoints": points}

    def retain(self, world, expected=None):
        root = self.root(world)
        if not (root / "rollback-pending.json").exists():
            latest = self.head(root)
            if expected is not None and latest != expected:
                return  # Child committed a different generation since status was polled.
            if latest is None or self.maintained.get(world) == (latest, self.keep):
                return
        history = self.list(world)
        latest = history["latest"]
        if latest is None:
            return
        keep = {p["generation"] for p in history["checkpoints"][:self.keep]} | {latest}
        for generation in self.directories(root):
            if generation not in keep and order(generation) < order(latest):
                self.remove(root, generation)
        self.maintained[world] = (latest, self.keep)

    def rollback(self, world, generation, expected_latest):
        self.recover(world)
        root = self.root(world)
        latest = self.head(root)
        if latest != expected_latest:
            raise CheckpointError("Checkpoint history changed. Reopen the checkpoint list.")
        self.snapshot(root, generation)
        if latest is None or order(generation) > order(latest):
            raise CheckpointError("Choose a committed checkpoint")
        newer = [g for g in self.directories(root) if order(g) > order(generation)]
        # The journal makes interrupted deletions resumable before another world start.
        atomic_json(root / "rollback-pending.json", dict(target=generation, previous=latest, delete=newer))
        self.recover(world)
        self.retain(world)
        return {"ok": True, "generation": generation, "deleted": len(newer)}
