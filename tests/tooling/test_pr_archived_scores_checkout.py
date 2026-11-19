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
        by_job = {"build": "needs.guard.outputs.ordinary_pr", "play": "env.PLAY_LOCKED_PROVISION"}
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
            if name not in {*by_job, "compatibility"}:
                self.assertNotIn("ARCHIVE_FREE_CHECKOUT", job.get("env", {}))

    def test_compatibility_only_excludes_archived_scores_from_ordinary_current_checkout(self):
        jobs = yaml.safe_load((ROOT / ".github/workflows/build-web.yml").read_text())["jobs"]
        job = jobs["compatibility"]
        self.assertEqual(job["strategy"]["matrix"]["case"], ["old_opened_after_new", "already_open_old"])
        self.assertEqual(job["env"]["ARCHIVE_FREE_CHECKOUT"], PATTERNS)
        self.assertEqual(job["env"]["PR_LOCKED_CHROMIUM_PROVISION"],
                         "${{ github.event_name == 'pull_request' && inputs.release_tag == '' && "
                         "!inputs.firebase_preview && !inputs.itch_preview && !inputs.itch_test_entry && "
                         "inputs.publication_receipt == '' }}")
        current, historical = [step for step in job["steps"] if step.get("uses") == PIN]
        self.assertNotIn("if", current)
        self.assertEqual(current["with"], {
            "fetch-depth": 0,
            "persist-credentials": False,
            "sparse-checkout-cone-mode": False,
            "sparse-checkout": "${{ env.PR_LOCKED_CHROMIUM_PROVISION == 'true' && env.ARCHIVE_FREE_CHECKOUT || '' }}",
        })
        self.assertEqual(historical["with"], {
            "ref": "9110ebd9a2d6cbf4d2af303be0e244e660c0f7fc",
            "path": ".compatibility-old",
            "persist-credentials": False,
        })
