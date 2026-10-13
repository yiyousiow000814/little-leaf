"""Real shallow snapshots preserve current-source identity; ancestry jobs keep history."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CICheckoutTests(unittest.TestCase):
    def test_current_source_snapshot_keeps_exact_identity_and_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            source, shallow = (Path(directory) / name for name in ('source', 'shallow'))
            source.mkdir()
            def git(folder, *args):
                return subprocess.check_output(['git', '-C', str(folder), *args], text=True).strip()
            git(source, 'init', '-q')
            git(source, 'config', 'user.name', 'Synthetic CI')
            git(source, 'config', 'user.email', 'ci@example.invalid')
            tracked = source / 'tracked.txt'
            for content in ('historical bytes', 'current exact bytes'):
                tracked.write_text(content)
                git(source, 'add', 'tracked.txt')
                git(source, 'commit', '-qm', content)
            subprocess.run(['git', 'clone', '--quiet', '--no-local', '--depth', '1',
                            source.as_uri(), str(shallow)], check=True)
            self.assertEqual(git(shallow, 'rev-parse', '--is-shallow-repository'), 'true')
            self.assertEqual(git(shallow, 'rev-list', '--count', 'HEAD'), '1')
            for args in [('rev-parse', 'HEAD'), ('rev-parse', 'HEAD^{tree}'), ('ls-files', '-z')]:
                self.assertEqual(git(shallow, *args), git(source, *args))
            self.assertEqual((shallow / 'tracked.txt').read_bytes(), tracked.read_bytes())
            self.assertEqual(git(shallow, 'status', '--porcelain', '--untracked-files=no'), '')
            (shallow / 'tracked.txt').write_text('unreviewed change')
            self.assertNotEqual(git(shallow, 'status', '--porcelain', '--untracked-files=no'), '')

    def test_only_current_snapshot_jobs_trim_history(self):
        text = (ROOT / '.github/workflows/build-web.yml').read_text()
        headings = list(re.finditer(r'^  ([a-z_]+):$', text, re.MULTILINE))
        jobs = {h.group(1): text[h.end():headings[i + 1].start() if i + 1 < len(headings) else len(text)]
                for i, h in enumerate(headings)}
        for name in ('engine', 'build', 'browser', 'gate'):
            with self.subTest(job=name):
                self.assertEqual(re.findall(r'fetch-depth: (\d+)', jobs[name]), ['1'])
                self.assertIn('persist-credentials: false', jobs[name])
        for name in ('guard', 'historical', 'compatibility', 'firebase'):
            with self.subTest(job=name):
                self.assertIn('fetch-depth: 0', jobs[name])
        # Tag ancestry and exact-main reuse stay in their independent full-history lane.
        self.assertIn('fetch-depth: 0', (ROOT / '.github/workflows/ci.yml').read_text())


if __name__ == '__main__':
    unittest.main()
