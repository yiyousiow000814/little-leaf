"""Protect the ordinary-PR checkout boundary without relaxing source receipts."""
from pathlib import Path
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[2]
PIN = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
PATTERNS = "/*\n!/docs/art-audio/scores/\n"


class PrArchivedScoresCheckoutTests(unittest.TestCase):
    def test_checkout_has_mutually_exclusive_routes_and_one_archive_exclusion(self):
        jobs = yaml.safe_load((ROOT / ".github/workflows/build-web.yml").read_text())["jobs"]
        by_job = {"build": "needs.guard.outputs.ordinary_pr", "play": "env.ORDINARY_PR"}
        for name, selector in by_job.items():
            with self.subTest(job=name):
                job = jobs[name]
                self.assertEqual(job["env"]["ARCHIVE_FREE_CHECKOUT"], PATTERNS)
                checkouts = [step for step in job["steps"] if str(step.get("uses", "")).startswith("actions/checkout@")]
                self.assertEqual(len(checkouts), 1)
                checkout = checkouts[0]
                self.assertEqual(checkout["uses"], PIN)
                self.assertNotIn("if", checkout)
                self.assertEqual(checkout["with"], {
                    "fetch-depth": 1,
                    "persist-credentials": False,
                    "sparse-checkout-cone-mode": False,
                    "sparse-checkout": "${{ " + selector + " == 'true' && env.ARCHIVE_FREE_CHECKOUT || '' }}",
                })
        for name, job in jobs.items():
            if name not in by_job:
                self.assertNotIn("ARCHIVE_FREE_CHECKOUT", job.get("env", {}))
