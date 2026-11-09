"""Add Babylon's papers to the upstream wreck without maintaining a map copy."""
import argparse
import itertools
import json
from pathlib import Path
import re
import string


def prepare_fresh_map(template, destination):
    template = Path(template)
    source = template / "_maps/RandomRuins/SpaceRuins/skyrat/drones_derelict.dmm"
    recipes = template / "_maps/babylon/lore.json"
    text = source.read_text(encoding="utf-8")
    if not recipes.exists():
        # Small loader fixtures and upstream-only developer checkouts have no lore.
        Path(destination).write_text(text, encoding="utf-8")
        return []
    dictionary = dict(re.findall(r'^"([a-zA-Z]+)" = \(\n(.*?)\)\n(?="|\n|\()', text, re.M | re.S))
    if not dictionary:
        raise ValueError("Babylon wreck must be a TGM map")
    width = len(next(iter(dictionary)))
    columns = list(re.finditer(r'^\((\d+),(\d+),(\d+)\) = \{"\n(.*?)^"\}', text, re.M | re.S))
    grids = [column[4].splitlines() for column in columns]
    keys = ("".join(chars) for chars in itertools.product(string.ascii_letters, repeat=width))
    additions, placed = [], []
    for recipe in json.loads(recipes.read_text(encoding="utf-8")):
        candidates = []
        for col_index, grid in enumerate(grids):
            for row_index, key in enumerate(grid):
                body = dictionary[key]
                if not re.search(re.escape(recipe["area"]) + r"\s*$", body) or "/turf/open/floor/" not in body:
                    continue
                if "/obj/structure/closet" in body or "/obj/structure/girder" in body:
                    continue
                priority = 0 if "/obj/structure/table" in body or "/obj/structure/rack" in body else 1
                candidates.append((priority, col_index, row_index, body))
        if not candidates:
            raise ValueError(f"No safe lore placement in upstream area {recipe['area']}")
        _, col_index, row_index, body = min(candidates)
        key = next(k for k in keys if k not in dictionary)
        dictionary[key] = recipe["paper"] + ",\n" + body
        # The native TGM reader requires the closing ')' on the area line;
        # an extra blank model line makes its fast cache parser fail.
        additions.append(f'"{key}" = (\n{dictionary[key].rstrip()})\n')
        grids[col_index][row_index] = key
        placed.append(dict(paper=recipe["paper"], area=recipe["area"],
                           x=int(columns[col_index][1]),
                           y=int(columns[col_index][2]) + len(grids[col_index]) - row_index - 1))
    # Replace grid bodies back-to-front, preserving every upstream object/turf.
    for column, grid in reversed(list(zip(columns, grids))):
        text = text[:column.start(4)] + "\n".join(grid) + "\n" + text[column.end(4):]
    text = text[:columns[0].start()] + "".join(additions) + text[columns[0].start():]
    Path(destination).write_text(text, encoding="utf-8")
    return placed


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args()
    placed = prepare_fresh_map(arguments.root, arguments.output)
    print(f"Prepared Babylon wreck with {len(placed)} lore papers.")
