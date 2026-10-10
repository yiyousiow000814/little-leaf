import hashlib
from pathlib import Path
import tempfile
import unittest
from optimize_web_present import ORIGINAL, OPTIMIZED, optimize_presentation


class PresenterGuardTest(unittest.TestCase):
    def test_records_exact_artifact_identity_and_preserves_other_calls(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "index.js"
            source = b"header();" + ORIGINAL + b"restore();};other.getParameter(3089);"
            path.write_bytes(source)
            receipt = optimize_presentation(path)
            self.assertEqual(path.read_bytes(), source.replace(ORIGINAL, OPTIMIZED))
            self.assertEqual(receipt["input_sha256"], hashlib.sha256(source).hexdigest())
            self.assertEqual(receipt["output_sha256"], hashlib.sha256(path.read_bytes()).hexdigest())

    def test_unknown_duplicate_or_already_changed_runtime_is_not_written(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "index.js"
            for source in [b"new runtime", ORIGINAL + ORIGINAL, OPTIMIZED, ORIGINAL + OPTIMIZED]:
                with self.subTest(source=source):
                    path.write_bytes(source)
                    with self.assertRaises(RuntimeError):
                        optimize_presentation(path)
                    self.assertEqual(path.read_bytes(), source)


if __name__ == "__main__":
    unittest.main()
