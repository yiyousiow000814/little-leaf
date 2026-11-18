"""One bounded synthetic ABBA CPU diagnostic on actual READY native atlases."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
BASE = 'd81afcd5b760eb4cc70eb941b4c28795f8c04df6'
PARENT = '86b225edfab6b290bdfcb958ea4f236ed11e0d07'
FIXTURE = 'tests/diagnostics/profile_stable_actor_atlas_ready.gd'
PROBE = 'tests/diagnostics/stable_actor_cpu_probe.gd'
FILES = {FIXTURE, PROBE, 'tools/diagnostics/stable_actor_atlas_ready_cpu.py', '.github/workflows/stable-actor-atlas-ready-cpu.yml'}
PINS = {FIXTURE: '6b28cc9067166422d9b15783a230bf4711b881cd93d325cfe12b5705ba1d59be', PROBE: '02418912c5604fa97a690f91fc46aa08efc4fa05ec4c0914edc9006e5d03ca4a'}
PRODUCTION = {'game/scripts/rendering/illustrated_cafe.gd': '144eea1e8866ff9bd55e20f23eddecb0b158e1226ca5bbd7b107526fc40ab5fc', 'game/scripts/rendering/cafe_character_pick_geometry.gd': '5157e40693b445219b0648c695652c6b17fe7854bc0159cf215166f0495b1c06'}
PROFILE_KEYS = ('HOME', 'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME')
TIMERS = {'scripts/main.gd': ['_process'], 'scripts/rendering/illustrated_cafe.gd': ['_draw', '_finish_native_objects'], 'scripts/rendering/cafe_native_draw_node.gd': ['_draw']}
COUNTERS = {'scripts/rendering/character_head_atlas.gd': {'draw_head': 'heads.sprite'}, 'scripts/rendering/moving_art_atlas.gd': {'draw_limb': 'limbs.sprite'}, 'scripts/rendering/illustrated_cafe.gd': {'_draw_head_legacy': 'heads.vector', '_round_limb_legacy': 'limbs.vector'}, 'scripts/rendering/illustrated_furniture.gd': {'_cached_part': 'furniture.sprite', 'draw_static_part': 'furniture.vector', 'try_draw_static': 'furniture.try_static'}}


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args]).decode().strip()


def save(path, data):
    temporary = path.with_suffix(path.suffix + '.pending')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(path)


def verify_source(head):
    require(git('rev-parse', 'HEAD') == head, 'Unexpected head')
    require(not git('status', '--porcelain', '--untracked-files=no'), 'Tracked checkout changed')
    require(git('rev-parse', 'HEAD^') == PARENT, 'One-shot source parent changed')
    require(set(git('diff', '--name-only', PARENT, 'HEAD').splitlines()) == FILES, 'Only four approved diagnostic files may change')
    require(len(PINS) == 2 and all(sha(ROOT / p) == h for p, h in PINS.items()), 'Fixture/probe pins changed')
    require(all(sha(ROOT / p) == h for p, h in PRODUCTION.items()), 'Runtime changed')
    require(set(git('diff', '--name-only', BASE, '--', 'game', 'platform').splitlines()) == set(PRODUCTION) | {'game/data/prebaked_atlas_manifest.json'}, 'Unexpected production drift')
    require(sha(ROOT / 'game/data/prebaked_atlas_manifest.json') == '7d34ba9a00aaa572010f0fe2caf3953bcc1d535d222243e36f96032f07bfca16', 'Qualified manifest changed')
    guard = module('stable_cpu_atlas_guard', ROOT / 'tools/qualification/verify_prebaked_atlases.py')
    manifest = json.loads((ROOT / 'game/data/prebaked_atlas_manifest.json').read_text())
    require(guard.sources() == manifest['source_sha256'] and len(guard.sources()) == 83, 'Atlas source closure is stale')
    return {'head': head, 'tree': git('rev-parse', 'HEAD^{tree}'), 'baseline': BASE, 'parent': PARENT, 'production': PRODUCTION, 'fixture_probe': PINS}


def instrument(project, candidate):
    timers = {p: list(names) for p, names in TIMERS.items()}
    if candidate:
        timers['scripts/rendering/illustrated_cafe.gd'] += ['_begin_native_owners', '_commit_native_order', '_native_actor_current']
    receipts = {}
    for relative in sorted(set(timers) | set(COUNTERS)):
        path = project / relative
        original = path.read_bytes()
        source = original.decode()
        declaration = 'const StableCpuProbe=preload("res://' + PROBE + '")\n'
        require('StableCpuProbe' not in source, 'Unexpected existing probe')
        position = source.index('\n', source.index('extends ')) + 1
        source = source[:position] + declaration + source[position:]
        wrappers = []
        renames = []
        for name in list(dict.fromkeys(timers.get(relative, []) + list(COUNTERS.get(relative, {})))):
            match = re.search(r'^func ' + re.escape(name) + r'\(([^\n]*)\)([^\n]*):[ \t]*\r?\n', source, re.M)
            require(match is not None, 'Missing reviewed function ' + relative + ':' + name)
            args, ret = match[1], match[2].strip()
            # Selected signatures have only scalar/default Vector2.ZERO arguments.
            require(not re.search(r'=\s*Vector2\(', args), 'Review comma-containing defaults')
            params = [re.split(r'[:=]', value.strip())[0].strip() for value in args.split(',') if value.strip()]
            old = '_stable_cpu_original_' + name
            source = source[:match.start()] + source[match.start():].replace('func ' + name + '(', 'func ' + old + '(', 1)
            renames.append((old, name))
            call = old + '(' + ','.join(params) + ')'
            wrapper = '\nfunc ' + name + '(' + args + ')' + ret + ':\n'
            timed = name in timers.get(relative, [])
            counter = COUNTERS.get(relative, {}).get(name)
            if relative == 'scripts/main.gd' and name == '_process':
                wrapper += '\tStableCpuProbe.observe_delta(delta)\n'
            if timed:
                wrapper += '\tStableCpuProbe.enter(' + repr(relative + ':' + name) + ')\n'
            if counter and counter != 'furniture.try_static':
                wrapper += '\tStableCpuProbe.count(' + repr(counter) + ')\n'
            void = 'void' in ret
            wrapper += ('\t' + call + '\n') if void else ('\tvar result=' + call + '\n')
            if counter == 'furniture.try_static':
                wrapper += '\tStableCpuProbe.count("furniture.try_static_hit" if result else "furniture.try_static_fallback")\n'
            if timed:
                wrapper += '\tStableCpuProbe.leave()\n'
            if not void:
                wrapper += '\treturn result\n'
            wrappers.append(wrapper)
            source += wrapper
        recovered = source
        for wrapper in reversed(wrappers):
            require(recovered.endswith(wrapper), 'Wrapper tail changed')
            recovered = recovered[:-len(wrapper)]
        recovered = recovered.replace(declaration, '', 1)
        for old, name in renames:
            recovered = recovered.replace('func ' + old + '(', 'func ' + name + '(', 1)
        require(recovered.encode() == original, 'Instrumentation cannot restore exact original bytes')
        path.write_bytes(source.encode())
        receipts[relative] = {'original_sha256': hashlib.sha256(original).hexdigest(), 'instrumented_sha256': sha(path), 'normalization_exact': True, 'timers': timers.get(relative, []), 'counters': COUNTERS.get(relative, {})}
    return receipts


def bounded_control(command, env, log):
    started = time.monotonic()
    peak = 0
    reason = None
    with log.open('wb') as stream:
        process = subprocess.Popen(command, env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        while process.poll() is None:
            try:
                status = Path('/proc/' + str(process.pid) + '/status').read_text()
                peak = max(peak, int(status.split('VmRSS:')[1].split()[0]))
            except (FileNotFoundError, IndexError):
                pass
            if 'ERROR:' in log.read_text(errors='replace'):
                reason = 'engine error'
            elif peak > 1048576:
                reason = '1GiB RSS cap'
            elif time.monotonic() - started > 180:
                reason = '180s control cap'
            if reason:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                break
            time.sleep(.1)
    if 'ERROR:' in log.read_text(errors='replace'):
        reason = reason or 'engine error in final log'
    return {'exit_code': process.returncode, 'stop_reason': reason, 'peak_rss_kib': peak, 'wall_seconds': time.monotonic() - started, 'command': command, 'log_sha256': sha(log)}


def compare(reports):
    # Filled against the frozen fixture schema; fail closed if controls differ.
    labels = ['1-baseline', '2-candidate', '3-candidate', '4-baseline']
    first = reports[labels[0]]
    for label in labels:
        current = reports[label]
        require(current['valid'] and current['frames'] == 600, 'Invalid/incomplete control')
        for key in ('setup', 'initial_state', 'warmup_state', 'final_state', 'population_frames', 'observations'):
            require(current[key] == first[key], 'Simulation/input mismatch: ' + key + ' in ' + label)
        require(len(current['main_deltas']) == 600 and all(len(row) == 1 and abs(row[0] - 1/60) < 1e-9 for row in current['main_deltas']), 'Fixed Main ticks differ')
        require(current['teardown']['game_freed'], 'Sampled Main survived teardown')
        require(len(current['population_frames']) == 600 and len(current['observations']) == 11, 'Population/activity receipt incomplete')
        for phase in ('sample_start', 'sample_end'):
            atlases = current['atlas_ready'][phase]
            require(set(atlases) == {'furniture', 'heads', 'moving'}, 'Atlas receipt set changed')
            require(all(row['ready'] and row['state'] == 'ready' and row['prebaked'] and row['texture_path'] == row['expected_path'] for row in atlases.values()), 'Actual prebaked READY gate failed')
        for branch in ('heads.sprite', 'limbs.sprite', 'furniture.sprite'):
            require(sum(current['branches'][phase]['totals'].get(branch, 0) for phase in ('warmup', 'measured')) > 0, 'Actual sprite branch absent: ' + branch)
    rows = {}
    for label, current in reports.items():
        rows[label] = {'timings': {k: {'calls': v['calls'], 'inclusive_ms_per_frame': v['inclusive_us'] / 600000, 'selected_self_ms_per_frame': v['self_us_excluding_instrumented_children'] / 600000} for k, v in current['timings'].items()}, 'inventory_end': current['inventory_end'], 'owner_capacity_end': current['owner_capacity_end'], 'teardown': current['teardown'], 'atlas_ready': current['atlas_ready'], 'branches': current['branches']}
    pairs = []
    for baseline, candidate in ((labels[0], labels[1]), (labels[3], labels[2])):
        parent = 'scripts/rendering/illustrated_cafe.gd:_draw'
        native = 'scripts/rendering/cafe_native_draw_node.gd:_draw'
        def total(label):
            return sum(rows[label]['timings'][key]['inclusive_ms_per_frame'] for key in (parent, native))
        pairs.append({'baseline': baseline, 'candidate': candidate, 'baseline_parent_plus_native_ms': total(baseline), 'candidate_parent_plus_native_ms': total(candidate), 'saving_ms': total(baseline) - total(candidate)})
    return {'rows': rows, 'pairs': pairs, 'limits': 'Four instrumented native X11/Mesa controls, fixed synthetic above-cap staff roster; CPU and retained capacity only, not browser/hardware GPU/FPS or leak proof. Parent includes finish/reconcile/commit; native includes current-owner guard.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-head', required=True)
    parser.add_argument('--godot', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    binding = verify_source(args.expected_head)
    if args.verify_only:
        print(json.dumps(binding)); return
    require(args.godot and args.output and not args.output.exists(), 'Fresh external output and engine required')
    output = args.output.resolve()
    require(not output.is_relative_to(ROOT), 'Evidence must be outside checkout')
    output.mkdir(parents=True)
    helper = module('stable_cpu_native_helper', ROOT / 'tools/diagnostics/storage_native_review.py')
    require(sha(args.godot) == helper.ENGINE_SHA, 'Official engine checksum differs')
    stage = module('stable_cpu_project', ROOT / 'tools/build/project_layout.py').stage_project
    result = dict(binding, status='running', controls=[], renderer_limit='X11 Mesa software rendering; not Web/hardware FPS')
    save(output / 'summary.json', result)
    try:
        with tempfile.TemporaryDirectory(prefix='stable-actor-cpu-saveguard-') as temporary:
            temp = Path(temporary)
            base = temp / 'baseline-source'; base.mkdir()
            with subprocess.Popen(['git', '-C', str(ROOT), 'archive', BASE, 'game', 'platform/web'], stdout=subprocess.PIPE) as archive:
                subprocess.run(['tar', '-x', '-C', str(base)], stdin=archive.stdout, check=True)
                archive.stdout.close(); require(archive.wait() == 0, 'Baseline archive failed')
            reports = {}
            for index, mode in enumerate(('baseline', 'candidate', 'candidate', 'baseline'), 1):
                label = str(index) + '-' + mode
                project = temp / (label + '-project')
                stage(base if mode == 'baseline' else ROOT, project, ignore=shutil.ignore_patterns('.godot', '__pycache__'))
                for relative in (FIXTURE, PROBE):
                    target = project / relative; target.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(ROOT / relative, target)
                original = {p.relative_to(project).as_posix(): sha(p) for p in project.rglob('*') if p.is_file()}
                wrapped = instrument(project, mode == 'candidate')
                staged = {p.relative_to(project).as_posix(): sha(p) for p in project.rglob('*') if p.is_file()}
                save(output / (label + '-sources.json'), {'original': original, 'instrumentation': wrapped, 'staged': staged})
                env = os.environ.copy()
                for key in PROFILE_KEYS:
                    folder = temp / (label + '-saveguard') / key; folder.mkdir(parents=True); env[key] = str(folder)
                env.update(OUTPUT=str(output / (label + '.json')), CASE=label, LIBGL_ALWAYS_SOFTWARE='1')
                engine = [str(args.godot.resolve()), '--path', str(project), '--audio-driver', 'Dummy']
                code, reason = helper.execute_native(engine + ['--headless', '--editor', '--import', '--quit'], env, output / (label + '-import.log'), timeout=120)
                import_log = output / (label + '-import.log')
                import_error = 'ERROR:' in import_log.read_text(errors='replace')
                save(output / (label + '-import-run.json'), {'exit_code': code, 'stop_reason': reason, 'final_log_error': import_error, 'log_sha256': sha(import_log)})
                require(code == 0 and not reason and not import_error, 'Import failed: ' + label)
                command = engine + ['--rendering-method', 'gl_compatibility', '--fixed-fps', '60', '--script', 'res://' + FIXTURE]
                receipt = bounded_control(command, env, output / (label + '.log'))
                save(output / (label + '-run.json'), receipt)
                result['controls'].append(dict(label=label, **receipt)); save(output / 'summary.json', result)
                require(receipt['exit_code'] == 0 and not receipt['stop_reason'], 'Failed control: ' + label)
                require(all(sha(project / p) == h for p, h in staged.items()), 'Staged input changed')
                reports[label] = json.loads((output / (label + '.json')).read_text())
            comparison = compare(reports)
            save(output / 'comparison.json', comparison)
            result['status'] = 'completed_pending_review'
            result['comparison_sha256'] = sha(output / 'comparison.json')
    except Exception as error:
        result['status'] = 'failed'; result['error'] = str(error); raise
    finally:
        save(output / 'summary.json', result)


if __name__ == '__main__':
    main()
