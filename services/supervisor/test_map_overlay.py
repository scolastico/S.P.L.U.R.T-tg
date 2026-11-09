import json
from pathlib import Path
import re
import tempfile
import unittest

from map_overlay import prepare_fresh_map


class LoreMap(unittest.TestCase):
    def test_adds_six_papers_without_changing_other_map_contents(self):
        root = Path(__file__).resolve().parents[2]
        original = (root / "_maps/RandomRuins/SpaceRuins/skyrat/drones_derelict.dmm").read_text()
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
        self.assertEqual(len(placements), 6)
        self.assertEqual(len(dictionary), len(original_dictionary) + 6)
        for key in dictionary.keys() - original_dictionary.keys():
            self.assertNotIn("", dictionary[key].splitlines())
        changed_cells = 0
        for before, after in zip(original_grids, new_grids):
            self.assertEqual(before[:3], after[:3])
            for old_key, new_key in zip(before[3].splitlines(), after[3].splitlines()):
                if old_key == new_key:
                    self.assertEqual(original_dictionary[old_key], dictionary[new_key])
                else:
                    changed_cells += 1
                    _, body = dictionary[new_key].split(",\n", 1)
                    self.assertEqual(body.rstrip(), original_dictionary[old_key].rstrip())
        self.assertEqual(changed_cells, 6)


if __name__ == "__main__":
    unittest.main()
