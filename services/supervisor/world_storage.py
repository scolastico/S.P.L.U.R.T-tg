"""Filesystem half of journaled, stopped-world expiry."""
from pathlib import Path
import re
import shutil


def delete_world_data(data_directory, world):
    if not re.fullmatch(r"[a-f0-9]{32}", str(world)):
        raise ValueError("Invalid world identifier")
    data = Path(data_directory).resolve()
    worlds, trash = data / "worlds", data / "deleted-worlds"
    for parent in (worlds, trash):
        if parent.resolve().parent != data:
            raise ValueError("World storage escapes its configured data directory")
    source, target = worlds / world, trash / world

    def checked(path, parent):
        if path.is_symlink() or getattr(path, "is_junction", lambda: False)() or path.resolve().parent != parent.resolve():
            raise ValueError("Unsafe world deletion target")

    checked(source, worlds)
    checked(target, trash)
    if source.exists():
        if target.exists():
            raise ValueError("World deletion has conflicting source and trash directories")
        trash.mkdir(parents=True, exist_ok=True)
        # Both final absolute move targets were checked above; neither is supplied by a player.
        source.rename(target)
    if target.exists():
        checked(target, trash)  # Recheck immediately before recursive deletion.
        shutil.rmtree(target)
