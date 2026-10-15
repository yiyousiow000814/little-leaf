"""Launch only the prepared, hash-bound native pilot after runtime coordination."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(output, engine, shared_lock):
    import msvcrt
    identity = json.loads((output / 'identity.json').read_text(encoding='utf-8'))
    debug_view = identity.get('capture_mode') == 'debug_view'
    project = output / 'project'
    assert sha(project / 'scripts/rendering/illustrated_cafe.gd') == identity['staged_artist_sha256']
    for name in ['capture_depth_occlusion.gd', 'depth_occlusion_probe_hooks.gd.txt']:
        key = 'tests/diagnostics/' + name
        assert sha(project / key) == identity['files'][key]
    if debug_view:
        for name in ['capture_depth_debug.gd', 'depth_debug_overlay.gd']:
            key = 'tests/diagnostics/' + name
            assert sha(project / key) == identity['files'][key]
    assert engine.is_file() and shared_lock.is_file()
    profile = output / 'saveguard-native-profile'
    env = os.environ.copy()
    for key in ['APPDATA', 'LOCALAPPDATA', 'HOME', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
        target = profile / key
        target.mkdir(parents=True, exist_ok=True)
        env[key] = str(target)
    env['DEPTH_PROBE_OUTPUT'] = str(output)
    env['DEPTH_PROBE_SOURCE'] = identity['head']
    receipt = {'head': identity['head'], 'tree': identity['tree'],
               'engine_sha256': sha(engine), 'profile': str(profile),
               'shared_lock': str(shared_lock), 'own_lock': str(output / 'diagnostic.lock'),
               'player_profiles_accessed': False, 'no_auth': True,
               'browser_launched': False, 'server_launched': False,
               'records': [], 'locks_released': False, 'status': 'not_started'}
    locks = []
    started = time.monotonic()
    try:
        for path in [shared_lock, output / 'diagnostic.lock']:
            handle = path.open('a+b')
            if path.stat().st_size == 0:
                handle.write(b'\0'); handle.flush()
            handle.seek(0)
            try:
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            except BaseException:
                handle.close()
                raise
            locks.append(handle)
        receipt['status'] = 'running'
        (output / 'launch-receipt.json').write_text(json.dumps(receipt, indent=2), encoding='utf-8')
        commands = [('import', ['--headless', '--editor', '--import', '--quit']),
                    ('pilot', ['--rendering-method', 'gl_compatibility',
                               '--script', 'res://tests/diagnostics/' + ('capture_depth_debug.gd' if debug_view else 'capture_depth_occlusion.gd'),
                               '--quit-after', '5400'])]
        if debug_view:
            commands[1][1].extend(['--', '--skip-intro'])
        # One combined import+pilot deadline; no follow-on retry or broad suite.
        for label, args in commands:
            remaining = 90 - (time.monotonic() - started)
            if remaining <= 0:
                raise TimeoutError('combined 90-second deadline expired')
            before = time.monotonic()
            command = [str(engine), '--audio-driver', 'Dummy', '--path', str(project), *args]
            with (output / (label + '.log')).open('wb') as log:
                child = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                                         creationflags=subprocess.CREATE_NO_WINDOW)
                try:
                    code = child.wait(timeout=remaining)
                except BaseException as error:
                    if child.poll() is None:
                        child.kill()
                    child.wait()
                    receipt['records'].append({'phase': label, 'pid': child.pid,
                                               'exit': child.returncode, 'process_exited': True,
                                               'terminated_on_abort': True,
                                               'terminated_on_deadline': isinstance(error, subprocess.TimeoutExpired)})
                    raise
            receipt['records'].append({'phase': label, 'pid': child.pid, 'exit': code,
                                       'seconds': round(time.monotonic() - before, 3),
                                       'process_exited': child.poll() is not None})
            if code:
                raise RuntimeError(label + ' exited ' + str(code))
            log_text = (output / (label + '.log')).read_text(encoding='utf-8', errors='replace')
            if 'SCRIPT ERROR:' in log_text or 'Parse Error:' in log_text:
                raise RuntimeError(label + ' logged an engine script/parse error')
        assert (output / 'capture.json').is_file(), 'pilot must write terminal capture'
        data = json.loads((output / 'capture.json').read_text(encoding='utf-8'))
        receipt['capture_sha256'] = sha(output / 'capture.json')
        receipt['frames'] = len(data['frames'])
        receipt['failures'] = data['failures']
        assert 0 < len(data['frames']) <= 720, 'nonempty bounded completed-frame evidence required'
        assert not data['failures'], 'fixture assertions failed'
        assert all(row['dropped'] == 0 for row in data['frames']), 'observation budget overflow'
        if debug_view:
            assert len(data['frames']) == 6, 'exactly three debug overlay-off/on pairs required'
            required = {f'debug-{state}-{overlay}' for state in ['tree-front', 'tree-back', 'chair-parts'] for overlay in ['off', 'on']}
        else:
            required = {'tree-front-to-back', 'tree-back-to-front', 'tree-diagonal-crown-trunk-edge'}
            for item in [101, 102]:
                for rotation in range(4):
                    for state in ['selected', 'preview', 'confirm', 'cancel-preview', 'cancel']:
                        required.add(f'decorate-{item}-r{rotation}-{state}')
        actual = {row['label'] for row in data['frames']}
        assert required <= actual, 'required pilot cases missing: ' + str(sorted(required - actual))
        numbers = [row['frame'] for row in data['frames']]
        assert all(b > a for a, b in zip(numbers, numbers[1:])), 'completed frame IDs must increase'
        receipt['status'] = 'captured' if not data['failures'] else 'diagnostic_failed'
    except BaseException as error:
        receipt['status'] = 'failed'
        receipt['error'] = type(error).__name__ + ': ' + str(error)
    finally:
        for handle in reversed(locks):
            handle.seek(0); msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1); handle.close()
        receipt['locks_released'] = True
        receipt['seconds'] = round(time.monotonic() - started, 3)
        (output / 'launch-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepared', type=Path, required=True)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--shared-lock', type=Path, required=True)
    args = parser.parse_args()
    result = run(args.prepared.resolve(), args.engine.resolve(), args.shared_lock.resolve())
    print(json.dumps(result))
    raise SystemExit(0 if result['status'] == 'captured' else 1)
