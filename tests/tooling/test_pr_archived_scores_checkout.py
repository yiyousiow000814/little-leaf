"""Protect ordinary build/Play checkout without relaxing source receipts."""
from pathlib import Path
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[2]
PIN = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
PATTERNS = "/*\n!/docs/art-audio/scores/\n"


class PrArchivedScoresCheckoutTests(unittest.TestCase):
    def test_checkout_has_mutually_exclusive_routes_and_one_archive_exclusion(self):
        jobs = yaml.safe_load((ROOT / ".github/workflows/build-web.yml").read_text())["jobs"]
        by_job = {"build": "needs.guard.outputs.ordinary_pr", "play": "env.LOCKED_BROWSER_PROVISION", "engine": "env.NATIVE_ARCHIVE_FREE"}
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
        self.assertEqual(jobs["play"]["env"]["LOCKED_BROWSER_PROVISION"], "${{ needs.build.outputs.locked_browser }}")
        self.assertEqual(jobs["build"]["outputs"]["locked_browser"], "${{ needs.guard.outputs.locked_browser }}")
        guard = next(step for step in jobs["guard"]["steps"] if step.get("id") == "engine_plan")
        self.assertEqual(guard["env"]["LOCKED_BROWSER"],
            "${{ (github.event_name == 'pull_request' || (github.event_name == 'push' && github.ref == 'refs/heads/main')) && inputs.release_tag == '' && !inputs.firebase_preview && !inputs.itch_preview && !inputs.itch_test_entry && inputs.publication_receipt == '' }}")
        native = "${{ needs.guard.outputs.locked_browser == 'true' && needs.guard.outputs.ordinary_pr == 'false' }}"
        self.assertEqual(jobs["engine"]["env"]["NATIVE_ARCHIVE_FREE"], native)
        merge = next(step for step in jobs["build"]["steps"] if "engine_shards.py merge" in step.get("run", ""))
        self.assertEqual(merge["env"]["NATIVE_ARCHIVE_FREE"], native)
        self.assertEqual(jobs["engine"]["strategy"]["matrix"]["shard"], "${{ fromJSON(needs.guard.outputs.engine_matrix) }}")
        for name, job in jobs.items():
            if name not in by_job:
                self.assertNotIn("ARCHIVE_FREE_CHECKOUT", job.get("env", {}))
