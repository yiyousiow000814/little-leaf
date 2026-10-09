"""CI-ready, save-isolated startup probe. Import the checkout first."""
import argparse
import hashlib
import json
import os
import platform
import shutil
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def summarize(samples):
    values = sorted(samples)
    if not values:
        return {"samples": 0}
    return {"samples": len(values), **{
        name: values[min(len(values) - 1, int((len(values) - 1) * percentile))]
        for name, percentile in [("p50_us", .5), ("p95_us", .95), ("p99_us", .99), ("max_us", 1)]},
        **{"over_" + str(limit) + "us": sum(x > limit for x in values)
           for limit in [33333, 50000, 100000]}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--headless', action='store_true', help='Logic validation only; no renderer claim')
    parser.add_argument('--expected-head', help='CI requires this exact clean commit')
    parser.add_argument('--import-project', action='store_true')
    args = parser.parse_args()
    head = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    if args.expected_head:
        # Godot may create missing script UID sidecars on first import. They are
        # generated references, not altered runtime source; all are hashed below.
        tracked = subprocess.check_output(['git', '-C', str(ROOT), 'diff', 'HEAD', '--name-only'])
        untracked = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '--others', '--exclude-standard'], text=True).splitlines()
        unexpected = [p for p in untracked if not (p.endswith('.gd.uid') and (ROOT / p[:-4]).is_file())]
        if head != args.expected_head or tracked or unexpected:
            raise RuntimeError('Expected an exact, clean source checkout')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    files = [p for d in ['scripts', 'shaders', 'assets'] for p in (ROOT / d).rglob('*') if p.is_file()]
    files += [ROOT / 'project.godot', ROOT / 'main.tscn', Path(__file__), ROOT / 'qa/profile_startup_transition.gd']
    manifest = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
    binding = {'source_commit': head, 'os': platform.platform(),
               'software_renderer_requested': os.environ.get('LIBGL_ALWAYS_SOFTWARE') == '1',
               'source_sha256': manifest, 'headless': args.headless, 'player_data_used': False}
    receipt = os.environ.get('GODOT_TOOLCHAIN_RECEIPT')
    if receipt:
        binding['toolchain_receipt'] = json.loads(Path(receipt).read_text())
        engine = Path(shutil.which(os.environ.get('GODOT_BIN', 'godot')))
        if hashlib.sha256(engine.read_bytes()).hexdigest() != binding['toolchain_receipt']['godot']['member_sha256']:
            raise RuntimeError('Engine binary differs from checksum-pinned receipt')
    elif args.expected_head:
        raise RuntimeError('CI requires the checksum-pinned toolchain receipt')
    (output / 'source-binding.json').write_text(json.dumps(binding, indent=2))
    with tempfile.TemporaryDirectory(prefix='startup-saveguard-') as temp:
        env = os.environ.copy()
        for key in ['HOME', 'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
            directory = Path(temp) / key.lower(); directory.mkdir(); env[key] = str(directory)
        env['OUTPUT'] = str(output)
        if args.import_project:
            with (output / 'import.log').open('wb') as log_file:
                imported = subprocess.run([env.get('GODOT_BIN', 'godot'), '--headless', '--path', str(ROOT), '--editor', '--import', '--quit'], env=env, stdout=log_file, stderr=subprocess.STDOUT, timeout=300)
            if imported.returncode or 'ERROR:' in (output / 'import.log').read_text():
                raise RuntimeError('Project import failed; inspect import.log')
        command = [env.get('GODOT_BIN', 'godot'), '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility']
        if args.headless:
            command += ['--headless']
        command += ['--path', str(ROOT), '--script', 'res://qa/profile_startup_transition.gd', '--', '--visual-qa', '--fresh-review']
        with (output / 'engine.log').open('wb') as log_file:
            result = subprocess.run(command, env=env, stdout=log_file, stderr=subprocess.STDOUT, timeout=90)
        log = (output / 'engine.log').read_text(errors='replace')
        if result.returncode or 'SCRIPT ERROR:' in log or 'ERROR:' in log:
            raise RuntimeError('Startup probe failed; inspect engine.log. No performance conclusion.')
    report = json.loads((output / 'startup-profile.json').read_text())
    assert len(report['trials']) == 2
    assert [t['trial'] for t in report['trials']] == ['cold_atlases', 'warm_atlases']
    assert report['trials'][0]['atlas_instance_ids'] == report['trials'][1]['atlas_instance_ids']
    for trial in report['trials']:
        assert trial['save_writes_suppressed'] and not trial['player_data_used']
        assert trial['renderer_measured'] == (not args.headless)
        if not args.headless:
            assert len(trial['post_draw_events']) > 1, 'No rendered frame interval evidence'
            assert all(s['state'] == 'ready' for s in trial['atlas_stats'].values()), 'Atlas bake failed or incomplete'
            if trial['trial'] == 'warm_atlases':
                assert trial['initial_atlas_states'] == ['ready'] * 3, 'Warm atlases were not retained'
            else:
                assert trial['initial_atlas_states'] != ['ready'] * 3, 'Cold trial was already warm'
        frames = trial['process_frames']
        assert len(frames) > 1
        # The first interval includes scene construction; report it separately.
        trial['first_process_interval_us'] = frames[0]['interval_us']
        trial['phase_summary'] = {}
        for phase in ['welcome_hold', 'descent', 'restaurant']:
            values = [f for f in frames[1:] if f['phase'] == phase]
            trial['phase_summary'][phase] = summarize([f['interval_us'] for f in values])
            if values:
                trial['phase_summary'][phase].update({
                    'background_rebuild_delta': values[-1]['background_rebuilds'] - values[0]['background_rebuilds'],
                    'shell_rebuild_delta': values[-1]['shell_rebuilds'] - values[0]['shell_rebuilds']})
        trial['completed_descent_observed'] = any(f['phase'] == 'descent' and f['intro_elapsed'] > 6 for f in frames)
        # A stalled intro can legitimately bail out early: retain/report, never pretend it completed.
        trial['first_post_draw_us'] = trial['post_draw_events'][0]['at_us'] if trial['post_draw_events'] else None
        trial['draw_phase_summary'] = {phase: summarize([b['at_us'] - a['at_us'] for a, b in zip(trial['post_draw_events'], trial['post_draw_events'][1:]) if a['phase'] == b['phase'] == phase]) for phase in ['welcome_hold', 'descent', 'restaurant']}
        trial['draw_event_intervals'] = summarize([b['at_us'] - a['at_us'] for a, b in zip(trial['post_draw_events'], trial['post_draw_events'][1:])])
    (output / 'startup-profile.json').write_text(json.dumps(report, indent=2))
    print(json.dumps({'status': 'recorded', 'renderer_measured': not args.headless, 'output': str(output)}))


if __name__ == '__main__':
    main()
