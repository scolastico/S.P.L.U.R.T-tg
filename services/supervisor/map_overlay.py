"""Add Babylon's lore and vault annex to the upstream wreck without maintaining a map copy."""
import argparse
import itertools
import json
from pathlib import Path
import re
import string

from logstream import log

DICTIONARY_PATTERN = r'^"([a-zA-Z]+)" = \(\n(.*?)\)\n(?="|\n|\()'
COLUMN_PATTERN = r'^\((\d+),(\d+),(\d+)\) = \{"\n(.*?)^"\}'
# Objects a lore item must never share a tile with.
BLOCKING = ("/obj/structure/closet", "/obj/structure/girder", "/obj/machinery/door",
            "/obj/machinery/computer", "/obj/structure/babylon")


def prepare_fresh_map(template, destination):
    template = Path(template)
    source = template / "_maps/RandomRuins/SpaceRuins/skyrat/drones_derelict.dmm"
    recipes = template / "_maps/babylon/lore.json"
    annex = template / "_maps/babylon/vault_annex.json"
    text = source.read_text(encoding="utf-8")
    if not recipes.exists():
        # Small loader fixtures and upstream-only developer checkouts have no lore.
        Path(destination).write_text(text, encoding="utf-8")
        return []
    dictionary = dict(re.findall(DICTIONARY_PATTERN, text, re.M | re.S))
    if not dictionary:
        raise ValueError("Babylon wreck must be a TGM map")
    width = len(next(iter(dictionary)))
    columns = list(re.finditer(COLUMN_PATTERN, text, re.M | re.S))
    grids = [column[4].splitlines() for column in columns]
    height = len(grids[0])
    keys = (key for key in ("".join(chars) for chars in itertools.product(string.ascii_letters, repeat=width))
            if key not in dictionary)
    additions, placed = [], []

    def assign(col_index, row_index, body):
        key = next(keys)
        dictionary[key] = body
        # The native TGM reader requires the closing ')' on the area line;
        # an extra blank model line makes its fast cache parser fail.
        additions.append('"' + key + '" = (\n' + body.rstrip() + ')\n')
        grids[col_index][row_index] = key

    # Structural patch first, so recipes can target the annex area.
    if annex.exists():
        for tile in json.loads(annex.read_text(encoding="utf-8"))["tiles"]:
            col_index, row_index = tile["x"] - 1, height - tile["y"]
            if not (0 <= col_index < len(grids) and 0 <= row_index < height):
                raise ValueError("Vault annex tile outside the wreck: %d,%d" % (tile["x"], tile["y"]))
            assign(col_index, row_index, tile["body"])
            placed.append(dict(paper=None, area=tile["body"].splitlines()[-1], x=tile["x"], y=tile["y"]))

    for recipe in json.loads(recipes.read_text(encoding="utf-8")):
        candidates = []
        within = recipe.get("within")
        for col_index, grid in enumerate(grids):
            for row_index, key in enumerate(grid):
                x, y = col_index + 1, height - row_index
                if within and not (within[0] <= x <= within[2] and within[1] <= y <= within[3]):
                    continue
                body = dictionary[key]
                if not re.search(re.escape(recipe["area"]) + r"\s*$", body) or "/turf/open/floor/" not in body:
                    continue
                if any(blocker in body for blocker in BLOCKING):
                    continue
                if recipe.get("hidden") and ("/turf/open/floor/plating" in body or "broken" in body or "burnt" in body):
                    # Under-floor stashes are only hidden while an intact tile covers them.
                    continue
                priority = 0 if "/obj/structure/table" in body or "/obj/structure/rack" in body else 1
                if recipe.get("hidden"):
                    # Under-floor stashes want a bare floor, not a table.
                    priority = 1 - priority
                if "babylon" in body:
                    priority += 2  # spread lore across tiles
                candidates.append((priority, col_index, row_index, body))
        if not candidates:
            raise ValueError("No safe lore placement in upstream area " + recipe["area"])
        _, col_index, row_index, body = min(candidates)
        assign(col_index, row_index, recipe["paper"] + ",\n" + body)
        placed.append(dict(paper=recipe["paper"], area=recipe["area"], x=col_index + 1, y=height - row_index))
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
    papers = sum(1 for entry in placed if entry["paper"])
    log("Prepared Babylon wreck with %d lore placements and %d annex tiles." % (papers, len(placed) - papers))
