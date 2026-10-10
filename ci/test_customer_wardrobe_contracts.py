"""Engine-free catalog acceptance. This does not execute GDScript or save adapters."""
import ast
import hashlib
import itertools
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def literal_constants(path):
    """Read only literal data from the actual catalog; never eval source code."""
    result = {}
    lines = path.read_text(encoding="utf-8").splitlines()
    for i, line in enumerate(lines):
        if not line.startswith("const "):
            continue
        name, value = line[6:].split(" = ", 1)
        for extra in lines[i + 1:] + [None]:
            try:
                result[name] = ast.literal_eval(value)
                break
            except SyntaxError:
                if extra is None:
                    raise
                value += "\n" + extra
    return result


C = literal_constants(ROOT / "scripts/customer_wardrobe_catalog.gd")


def legal_combination(species, selected):
    """Check the catalog's constraints as a complete combination, not slot order."""
    selected_ids = set(selected.values())
    for slot, item_id in selected.items():
        if item_id == "none":
            if slot not in C["OPTIONAL"]:
                return False
            continue
        item = C["ITEMS"][item_id]
        if species not in item.get("species", C["SPECIES"]):
            return False
        if selected_ids.intersection(item.get("excludes", [])):
            return False
        if any(selected.get(key) != value for key, value in item.get("requires", {}).items()):
            return False
    return True


class CatalogContracts(unittest.TestCase):
    def test_six_species_and_natural_fur(self):
        self.assertEqual(set(C["SPECIES"]), {"bear", "rabbit", "fox", "cat", "dog", "red_panda"})
        self.assertEqual(set(C["FIT"]), set(C["SPECIES"]))
        self.assertEqual(set(C["FUR"]), set(C["SPECIES"]))
        for species, patterns in C["FUR"].items():
            self.assertGreaterEqual(len(patterns), 2)
            self.assertEqual(len({f["id"] for f in patterns}), len(patterns))
            for fur in patterns:
                self.assertEqual(set(fur), {"id", "coat", "markings"})
                self.assertTrue(fur["coat"] and fur["markings"])
        self.assertIn("asymmetric_droop_pink_inner", C["FIT"]["rabbit"]["ears"])
        for fur in C["FUR"]["red_panda"]:
            self.assertIn("face_mask", fur["markings"])
            self.assertIn("ringed_tail", fur["markings"])

    def test_curated_palette_roles_complete(self):
        self.assertGreaterEqual(len(C["PALETTES"]), 3)
        self.assertEqual(set(C["COLOR_ROLES"]), set(C["SLOTS"]))
        for palette in C["PALETTES"].values():
            self.assertEqual(set(palette), set(C["COLOR_ROLES"].values()))
            self.assertEqual(len(set(palette.values())), 5)

    def test_constraint_references_and_selection_dependencies(self):
        slots = C["SLOTS"]
        for item_id, item in C["ITEMS"].items():
            self.assertIn(item["slot"], slots)
            self.assertTrue(item["anchor"] and item["fit"])
            self.assertTrue(set(item.get("species", C["SPECIES"])).issubset(C["SPECIES"]))
            for other in item.get("excludes", []):
                self.assertIn(other, C["ITEMS"])
                self.assertNotEqual(other, item_id)
            for slot, required_id in item.get("requires", {}).items():
                self.assertEqual(C["ITEMS"][required_id]["slot"], slot)
                self.assertLess(slots.index(slot), slots.index(item["slot"]))

    def test_every_supported_item_reachable_in_complete_outfits(self):
        slots = C["SLOTS"]
        choices = [[item_id for item_id, item in C["ITEMS"].items() if item["slot"] == slot]
                   + (["none"] if slot in C["OPTIONAL"] else []) for slot in slots]
        for species in C["SPECIES"]:
            reachable, pairs, count = set(), set(), 0
            for parts in itertools.product(*choices):
                selected = dict(zip(slots, parts))
                if legal_combination(species, selected):
                    count += 1
                    reachable.update(parts)
                    pairs.add((selected["top"], selected["lower"]))
            self.assertGreater(count, 32, species)
            self.assertEqual(len(pairs), 4, species)  # independent upper/lower parts
            for item_id, item in C["ITEMS"].items():
                if species in item.get("species", C["SPECIES"]):
                    self.assertIn(item_id, reachable, species)

    def test_ear_tail_and_attachment_constraints(self):
        self.assertNotIn("rabbit", C["ITEMS"]["headwear_closed_cap"]["species"])
        self.assertNotIn("fox", C["ITEMS"]["bow_low_back"]["species"])
        self.assertNotIn("red_panda", C["ITEMS"]["bow_low_back"]["species"])
        self.assertEqual(C["ITEMS"]["bow_upper_back"]["anchor"], "upper_back")
        self.assertIn("body_facing", C["ITEMS"]["bow_upper_back"]["fit"])
        self.assertIn("ear_clear", C["ITEMS"]["ribbon_head"]["fit"])
        self.assertEqual(C["ITEMS"]["legwear_tights"]["requires"], {"lower": "lower_skirt"})
        self.assertIn("legwear_socks", C["ITEMS"]["shoes_boots"]["excludes"])

    def test_golden_digest_for_cross_target_contract(self):
        seed = hashlib.sha256(b"synthetic-fixture").hexdigest()
        payload = f'{C["REVISION"]}|{seed}|fixture|species'.encode("ascii")
        # Fixed SHA256 fixture is also exercised by the eventual GDScript suite.
        self.assertEqual(seed, "3a3436765885cdf2edc179512c22dd4c4259410f0d18f391cbc8d83a837c678e")
        self.assertEqual(int(hashlib.sha256(payload).hexdigest()[:8], 16), 952861608)

    def test_pure_module_boundary(self):
        for filename in ["customer_wardrobe.gd", "customer_wardrobe_catalog.gd", "customer_wardrobe_record.gd"]:
            source = (ROOT / "scripts" / filename).read_text()
            for forbidden in ["FileAccess", "ResourceLoader", "RandomNumberGenerator", "randf(", "randi(", "cafe_model", "cafe_staff", "cafe_save", "HTTP", "load_save"]:
                self.assertNotIn(forbidden, source, filename)


if __name__ == "__main__":
    unittest.main()
