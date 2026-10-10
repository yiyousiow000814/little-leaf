"""Selected preparation behavior with synthetic coordinates; never start Godot."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import prepare_browser_qa as qa


class PreparationTests(unittest.TestCase):
    def test_dispatch_runs_only_requested_scenario(self):
        for scenario in ('wall', 'cloud'):
            with patch.object(qa, 'wall_main') as wall, patch.object(qa, 'cloud_main') as cloud:
                qa.main([scenario, '--output', 'synthetic-output'])
                selected, other = (wall, cloud) if scenario == 'wall' else (cloud, wall)
                selected.assert_called_once_with(['--output', 'synthetic-output'])
                other.assert_not_called()

    def test_profiles_are_disposable_for_all_platforms(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / 'profile'
            env = qa.synthetic_profile(folder)
            for key in ('HOME', 'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
                self.assertEqual(Path(env[key]).parent, folder)
                self.assertTrue(Path(env[key]).is_dir())

    def test_existing_output_refused_before_copy_or_engine(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(qa.shutil, 'copytree') as copy, patch.object(qa.subprocess, 'run') as engine:
            with self.assertRaises(ValueError):
                qa.main(['cloud', '--output', tmp])
            copy.assert_not_called()
            engine.assert_not_called()

    def cloud(self, invalid=False):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'output'
            def run(command, **kwargs):
                if '--script' not in command:
                    return
                value = json.loads(Path(command[-2]).read_text())
                width = value['viewport']['width']
                reason = value['snapshot']['reason']
                text = reason + (' Current progress is protected on this device.' if 'nativeCallback' in value else '')
                result = {'text': text, 'buttons': {'switch': [width if invalid else 1, len(reason), 20, 20]}}
                Path(command[-1]).write_text(json.dumps(result))
            with patch.object(qa.shutil, 'copytree'), patch.object(qa.subprocess, 'run', side_effect=run) as engine, patch.object(qa.subprocess, 'check_output', return_value='synthetic-source\n'), patch.object(qa, 'sha256', return_value='synthetic-hash'):
                if invalid:
                    with self.assertRaises(ValueError):
                        qa.main(['cloud', '--output', str(out)])
                    self.assertFalse((out / 'binding.json').exists())
                else:
                    qa.main(['cloud', '--output', str(out)])
                    self.assertEqual(engine.call_count, 7)  # one import, six layouts
                    layouts = json.loads((out / 'regressions.json').read_text())
                    self.assertEqual(len(layouts), 6)
                    self.assertEqual({x['message'] for x in layouts}, {'short', 'wrapped', 'protected'})
                    self.assertTrue(json.loads((out / 'binding.json').read_text())['synthetic_only'])
                    for call in engine.call_args_list:
                        self.assertTrue(Path(call.kwargs['env']['HOME']).is_relative_to(out))

    def test_cloud_retains_six_layouts_and_receipt(self):
        self.cloud()

    def test_bad_coordinates_cannot_produce_success_receipt(self):
        self.cloud(invalid=True)


if __name__ == '__main__':
    unittest.main()
