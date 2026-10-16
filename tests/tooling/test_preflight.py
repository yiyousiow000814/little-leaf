"""The local preflight reuses ordinary guard contracts without extra jobs."""
import contextlib
import io
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from ci import preflight


class PreflightTests(unittest.TestCase):
    def test_complete_guard_keeps_one_discovery_and_all_node_fixtures(self):
        commands = [command for _, command in preflight.commands(tag="v0.1.11")]
        self.assertEqual(commands[0][-2:], ["--tag", "v0.1.11"])
        self.assertEqual(commands[1][-1], "tools/qualification/verify_prebaked_atlases.py")
        self.assertEqual(commands[2][1:], ["-m", "unittest", "discover", "-s", "tests/tooling", "-t", ".", "-p", "test_*.py", "-v"])
        self.assertEqual(len(commands), 21)
        self.assertEqual(len({tuple(command) for command in commands}), len(commands))
        self.assertEqual(commands[3:], [["node", *check.split()] for check in preflight.NODE_CHECKS])
        self.assertIn(["node", "tests/persistence/layout_hold_codec.js"], commands[3:])

    def test_release_mode_runs_existing_contracts_once_without_full_discovery(self):
        commands = [command for _, command in preflight.commands(release=True)]
        self.assertEqual(len(commands), 3)
        self.assertNotIn("discover", commands[-1])
        self.assertEqual(len(set(preflight.RELEASE_TESTS)), len(preflight.RELEASE_TESTS))
        suite = unittest.defaultTestLoader.loadTestsFromNames(commands[-1][3:-1])
        def ids(group):
            for test in group:
                yield from ids(test) if isinstance(test, unittest.TestSuite) else [test.id()]
        selected = list(ids(suite))
        self.assertEqual(len(selected), len(set(selected)))
        self.assertIn("tests.tooling.test_common_tag.CommonTagTests.test_explicit_main_fetch_binds_checkout_fetch_head_without_weakening_chronology", selected)
        self.assertIn("tests.tooling.test_common_tag.PlatformTests.test_canonical_attempt_drift_is_refused_before_artifact_access", selected)
        self.assertIn("tests.tooling.test_common_tag.PlatformTests.test_workflow_cli_authenticates_attempt_and_real_fetched_history_together", selected)
        self.assertFalse(any("_FailedTest" in name for name in selected))

    def test_failed_guard_stops_before_other_checks(self):
        with patch.object(preflight.subprocess, "run", side_effect=[SimpleNamespace(returncode=0), SimpleNamespace(returncode=7)]) as run, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(SystemExit, "atlas provenance.*exit 7"):
                preflight.main(["--release"])
        self.assertEqual(run.call_count, 2)
        self.assertTrue(all(call.kwargs == {"cwd": preflight.ROOT} for call in run.call_args_list))


if __name__ == "__main__":
    unittest.main()
