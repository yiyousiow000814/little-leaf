"""Lightweight checks for the additive adapter; does not start any engine."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

from ci.test_customer_wardrobe_contracts import literal_constants, legal_combination

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = literal_constants(ROOT / "scripts/character_appearance_contract.gd")
# Adapter contains two preload declarations, so extract its data constants only.
SOURCE = (ROOT / "scripts/customer_appearance_adapter.gd").read_text()


class AppearanceContracts(unittest.TestCase):
    def test_common_header_shape_and_provider_boundary(self):
        self.assertEqual(set(CONTRACT["FIELDS"]), {"schema", "actor_kind", "identity", "provider", "wardrobe", "expression"})
        self.assertEqual(CONTRACT["ACTOR_KINDS"], ["customer", "staff"])
        self.assertIn('"header_only_provider_validation_required"', (ROOT / "scripts/character_appearance_contract.gd").read_text())
        self.assertIn('Contract.validate_header(envelope, expected_identity, "customer")', SOURCE)
        self.assertIn('Wardrobe.validate(envelope.wardrobe, expected_identity)', SOURCE)

    def test_expression_contracts_are_natural_and_bounded(self):
        self.assertEqual(CONTRACT["EXPRESSIONS"], ["neutral", "soft_smile", "focused", "happy_greeting"])
        self.assertEqual(CONTRACT["EXPRESSION_REVISION"], "natural-face-draft-1")
        self.assertIn('"pending_art_review"', (ROOT / "scripts/character_appearance_contract.gd").read_text())

    def test_namespace_identity_is_stable_and_distinct(self):
        identity = lambda namespace, sequence: hashlib.sha256(f"customer-identity-v1|{namespace}|{sequence}".encode()).hexdigest()[:32]
        self.assertEqual(identity("profile_fixture", 1), "b81a225c289b3283281af5c852098de2")
        self.assertNotEqual(identity("profile_fixture", 1), identity("other_profile", 1))
        self.assertNotEqual(identity("profile_fixture", 1), identity("profile_fixture", 2))
        self.assertIn('"customer-identity-v1|%s|%d"', SOURCE)

    def test_offline_synthetic_boundary(self):
        for filename in ["character_appearance_contract.gd", "customer_appearance_adapter.gd"]:
            text = (ROOT / "scripts" / filename).read_text()
            for forbidden in ["FileAccess", "HTTP", "RandomNumberGenerator", "randf(", "randi(", "res://scripts/cafe_model", "res://scripts/main", "res://scripts/cafe_staff", "res://scripts/cafe_save"]:
                self.assertNotIn(forbidden, text, filename)
        self.assertIn('const KIND = "synthetic_customer"', SOURCE)
        self.assertIn('const MAX_SEQUENCE = 9007199254740991', SOURCE)

    def test_runner_prepares_only_additive_dependencies_and_synthetic_profile(self):
        spec = importlib.util.spec_from_file_location("wardrobe_runner", ROOT / "tests/run_customer_wardrobe.py")
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        files, script, marker = runner.SUITES["adapter"]
        self.assertEqual(script, "tests/test_customer_appearance_adapter.gd")
        self.assertEqual(marker, "CUSTOMER_APPEARANCE_ADAPTER_RESULT ")
        with tempfile.TemporaryDirectory(prefix="adapter-runner-contract-") as scratch:
            project = Path(scratch) / "project"
            env = runner.prepare(project, files)
            actual = {p.relative_to(project).as_posix() for p in project.rglob("*") if p.is_file()}
            self.assertEqual(actual, set(files) | {"project.godot"})
            self.assertNotIn("scripts/main.gd", actual)
            for name in files:
                self.assertEqual((project / name).read_bytes(), (ROOT / name).read_bytes())
            for key in ["HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
                self.assertTrue(Path(env[key]).is_relative_to(project.resolve()))
        self.assertFalse(project.exists())

    def test_handoff_fixture_compatibility_and_identity(self):
        fixtures = json.loads((ROOT / "tests/fixtures/customer_appearance_compatibility.json").read_text())
        self.assertEqual(len(fixtures["valid_customers"]), 6)
        self.assertEqual(len(fixtures["invalid_customers"]), 6)
        for customer in fixtures["valid_customers"]:
            wardrobe = customer["appearance"]["wardrobe"]
            self.assertTrue(legal_combination(wardrobe["species"], wardrobe["items"]))
            expected = "customer_" + hashlib.sha256(f'customer-identity-v1|{customer["namespace"]}|{customer["id"]}'.encode()).hexdigest()[:32]
            self.assertEqual(customer["appearance"]["identity"], expected)
            self.assertEqual(wardrobe["identity"], expected)
        for fixture in fixtures["invalid_customers"]:
            if fixture["name"] in ["rabbit_closed_cap", "fox_low_bow", "red_panda_low_bow", "hat_ribbon_collision"]:
                wardrobe = fixture["customer"]["appearance"]["wardrobe"]
                self.assertFalse(legal_combination(wardrobe["species"], wardrobe["items"]))
        self.assertTrue(fixtures["staff_headers"][0]["wardrobe"]["fixture_only"])

    def test_identity_survives_fixture_reorder_removal_and_json_reload(self):
        customers = json.loads((ROOT / "tests/fixtures/customer_appearance_compatibility.json").read_text())["valid_customers"]
        original = {c["id"]: json.dumps(c["appearance"], sort_keys=True) for c in customers}
        changed = list(reversed(customers))
        changed.pop(2)
        restored = json.loads(json.dumps(changed))
        self.assertEqual(len(restored), 5)
        for customer in restored:
            self.assertEqual(json.dumps(customer["appearance"], sort_keys=True), original[customer["id"]])
        self.assertNotEqual([c["id"] for c in restored], list(range(1, 6)))


if __name__ == "__main__":
    unittest.main()
