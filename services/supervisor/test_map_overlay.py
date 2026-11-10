import json
from pathlib import Path
import re
import tempfile
import unittest

from map_overlay import prepare_fresh_map


class LoreMap(unittest.TestCase):
    def test_adds_lore_and_annex_without_changing_other_map_contents(self):
        root = Path(__file__).resolve().parents[2]
        original = (root / "_maps/RandomRuins/SpaceRuins/skyrat/drones_derelict.dmm").read_text()
        recipes = json.loads((root / "_maps/babylon/lore.json").read_text())
        annex = json.loads((root / "_maps/babylon/vault_annex.json").read_text())["tiles"]
        pattern = r'^"([a-zA-Z]+)" = \(\n(.*?)\)\n(?="|\n|\()'
        original_dictionary = dict(re.findall(pattern, original, re.M | re.S))
        columns = r'^\((\d+),(\d+),(\d+)\) = \{"\n(.*?)^"\}'
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "active.dmm"
            placements = prepare_fresh_map(root, output)
            changed = output.read_text()
        dictionary = dict(re.findall(pattern, changed, re.M | re.S))
        original_grids = re.findall(columns, original, re.M | re.S)
        new_grids = re.findall(columns, changed, re.M | re.S)
        papers = [entry for entry in placements if entry["paper"]]
        self.assertEqual(len(papers), len(recipes))
        self.assertEqual(len(placements), len(recipes) + len(annex))
        self.assertEqual(len(dictionary), len(original_dictionary) + len(placements))
        for key in dictionary.keys() - original_dictionary.keys():
            self.assertNotIn("", dictionary[key].splitlines())
        annex_cells = {(tile["x"], tile["y"]): tile["body"] for tile in annex}
        lore_cells = {(entry["x"], entry["y"]): entry["paper"] for entry in papers}
        height = len(original_grids[0][3].splitlines())
        changed_cells = 0
        for before, after in zip(original_grids, new_grids):
            self.assertEqual(before[:3], after[:3])
            x = int(before[0])
            for row_index, (old_key, new_key) in enumerate(zip(before[3].splitlines(), after[3].splitlines())):
                y = height - row_index
                if old_key == new_key:
                    self.assertEqual(original_dictionary[old_key], dictionary[new_key])
                    continue
                changed_cells += 1
                body = dictionary[new_key].rstrip()
                if (x, y) in lore_cells:
                    # A lore item sits on top of whatever the tile already held.
                    head, rest = body.split(",\n", 1)
                    self.assertEqual(head, lore_cells[(x, y)])
                    underlying = annex_cells.get((x, y), original_dictionary[old_key]).rstrip()
                    self.assertEqual(rest, underlying)
                else:
                    self.assertIn((x, y), annex_cells)
                    self.assertEqual(body, annex_cells[(x, y)].rstrip())
        # Lore placed inside the annex shares a cell with the annex tile it sits on.
        overlap = sum(1 for cell in lore_cells if cell in annex_cells)
        self.assertEqual(changed_cells, len(placements) - overlap)
        # Every lore item is distinct and lands on a floor tile.
        self.assertEqual(len(lore_cells), len(papers))
        for entry in papers:
            self.assertIn("/turf/open/floor/", dictionary[new_grids[entry["x"] - 1][3].splitlines()[height - entry["y"]]])
        # The annex is sealed by indestructible walls on every side.
        walls = {(tile["x"], tile["y"]) for tile in annex if "indestructible/riveted" in tile["body"]}
        self.assertTrue(all((x, 68) in walls for x in range(38, 45)))
        self.assertTrue(all((38, y) in walls and (44, y) in walls for y in range(63, 69)))
        self.assertTrue(all((x, 63) in walls for x in range(38, 45) if x != 41))


if __name__ == "__main__":
    unittest.main()
