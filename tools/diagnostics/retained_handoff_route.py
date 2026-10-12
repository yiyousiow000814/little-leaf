"""Finite retained-a897 Linux diagnostic route; never release qualification."""
import argparse
import ctypes
from datetime import datetime, timezone
import hashlib
import importlib.util
import ipaddress
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import signal
import socket
import stat
import subprocess
import time
import zipfile

SOURCE = 'a897a31f20ad4b95a6f350b219cc12f56a17f3b6'
TREE = 'd03b593cef63a8137049ac20de1416884917ba98'
RUN = 38171476207
BASE = '69f33801aac66844f2eaa1e15d4d767544d0d663'
ARTIFACTS = {
    'web': (11714480498, 'little-leaf-web-'+SOURCE+'-1', '83411d33680157c3a3e3f6c75b86227b2c1871b338136abeeabaf6ae25ec45e6'),
    'evidence': (11713229962, 'little-leaf-firebase-evidence-'+SOURCE+'-1', '268808b4a80b6b971ad71cf87d75df9326350cc94f7487b6f9cdabe7502c8ce8'),
}
DRIVER = '9c2d1c6508a4f4e06df87d6b5696c4c465ddffcf8d01f3e284091b3d3f98dd1a'
NETWORK = '0565ca829a4ad1249492d72888f986e4689ceb9445085830be5cf65835a27049'
LOCK = 'a8d7fc1d28f1eb12441ff397220a196a37c25b25247f03f85b6a5f650cd5ba2d'
JAR = '049ee7814741b481ae5becfdaa7b55693bdf7a03363cd184e35c36c1595a9643'
# Exact Linux serialization of the retained transformer. The previous 4d9ec006
# digest binds the preserved Windows CRLF packet, not the original Linux entry.
VARIANT = '28f34875e3ba21a7d4cdb44ded7f962d3390a373bef1b9133de65b649d40e61f'
EMBEDDED_ENTRY = 'd2b01428612d764dce386b5c644a212b26d7f3e8703385187c90a3e848d514ac'
CHROME = '154.0.8037.97'
IMAGE = '20261004.327.1'

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def validate_metadata(kind, artifact, run):
    identifier, name, digest = ARTIFACTS[kind]
    if (type(artifact.get('id')) is not int or artifact['id'] != identifier or artifact.get('name') != name
            or artifact.get('expired') is not False or artifact.get('digest') != 'sha256:'+digest
            or artifact.get('workflow_run', {}).get('id') != RUN
            or artifact.get('workflow_run', {}).get('head_sha') != SOURCE
            or run.get('id') != RUN or type(run.get('run_attempt')) is not int or run['run_attempt'] != 1
            or run.get('head_sha') != SOURCE or run.get('status') != 'completed'
            or run.get('conclusion') != 'failure' or run.get('event') != 'workflow_dispatch'
            or run.get('path') != '.github/workflows/stage-firebase.yml'):
        raise ValueError('Exact retained failed-stage metadata required')
    expiry = datetime.fromisoformat(artifact.get('expires_at', '').replace('Z', '+00:00'))
    if expiry.tzinfo is None or expiry <= datetime.now(timezone.utc):
        raise ValueError('Retained artifact expired; no rebuilding fallback')

def unpack(archive, destination, expected, selected=None):
    if destination.exists() or sha(archive) != expected:
        raise ValueError('Fresh output and pinned archive required')
    with zipfile.ZipFile(archive) as zipped:
        entries = zipped.infolist()
        names = [entry.filename for entry in entries]
        if (len(names) != len(set(names)) or len(names) > 5000
                or sum(entry.file_size for entry in entries) > 1024**3 or zipped.testzip() is not None):
            raise ValueError('Archive integrity or size mismatch')
        for entry in entries:
            path = PurePosixPath(entry.filename)
            if (entry.orig_filename != entry.filename or path.is_absolute() or '..' in path.parts
                    or chr(92) in entry.orig_filename or ':' in entry.filename
                    or stat.S_ISLNK(entry.external_attr >> 16)):
                raise ValueError('Unsafe archive member')
        if selected and not set(selected).issubset(names):
            raise ValueError('Retained geometry/native evidence missing')
        destination.mkdir(parents=True)
        for entry in entries:
            if selected is not None and entry.filename not in selected:
                continue
            if entry.is_dir():
                continue
            target = destination / entry.filename
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('xb') as stream:
                stream.write(zipped.read(entry))

def image_gate(env):
    if env.get('ImageOS') != 'ubuntu24' or env.get('ImageVersion') != IMAGE:
        raise ValueError('Original Linux runner image required; no replacement installation')

def validate_derived_variant(root):
    manifest_hash = sha(root/'variant/firebase-variant-manifest.json')
    entry_hash = sha(root/'variant/public/itch/index.html')
    if manifest_hash == VARIANT and entry_hash == EMBEDDED_ENTRY:
        return
    # Hashes only: preserve a preparation failure without exporting configuration
    # or letting an unavailable evidence write replace the original rejection.
    evidence = {'diagnostic_only': True, 'release_qualification': False, 'deployable': False,
        'phase': 'prepare-derived-variant', 'expected_manifest_sha256': VARIANT,
        'actual_manifest_sha256': manifest_hash, 'expected_entry_sha256': EMBEDDED_ENTRY,
        'actual_entry_sha256': entry_hash, 'runtime_started': False}
    try:
        with (root/'diagnostic-prepare-failure.json').open('x', encoding='utf-8', newline='\n') as stream:
            stream.write(json.dumps(evidence, indent=2)+'\n')
    except OSError:
        pass
    raise ValueError('Original derived variant not reproduced; preserve and STOP')

def prepare(root, coordinator):
    source = root / 'source'
    run = json.loads((root / 'run.metadata.json').read_bytes())
    for kind in ARTIFACTS:
        validate_metadata(kind, json.loads((root / (kind+'.metadata.json')).read_bytes()), run)
    def git(value):
        return subprocess.check_output(['git', '-C', str(source), 'rev-parse', value], timeout=15).decode().strip()
    if git('HEAD') != SOURCE or git('HEAD^{tree}') != TREE:
        raise ValueError('Exact retained source checkout required')
    frozen = coordinator / 'platform/firebase/diagnostics'
    if sha(frozen/'retained_handoff_driver.mjs') != DRIVER or sha(frozen/'retained_handoff_network.mjs') != NETWORK:
        raise ValueError('Reviewed observer bytes required')
    if sha(source/'platform/firebase/package-lock.json') != LOCK:
        raise ValueError('Original SDK/emulator lock required')
    unpack(root/'web.zip', root/'build/web', ARTIFACTS['web'][2])
    prefix = 'web-build/evidence/firebase-fullflow/'
    names = ['engine-evidence/summary.json', 'engine-evidence/test_cloud_recovery_ui.log',
             'engine-evidence/test_update_notice.log', prefix+'geometry-1-input.json', prefix+'geometry-1-result.json']
    unpack(root/'evidence.zip', root/'evidence', ARTIFACTS['evidence'][2], names)
    native = root/'evidence/engine-evidence/summary.json'
    manifest = json.loads((root/'build/web/release-manifest.json').read_bytes())
    engine = json.loads(native.read_bytes())
    if (manifest.get('source_commit') != SOURCE or manifest.get('source_tree') != TREE
            or engine.get('source_commit') != SOURCE or engine.get('status') != 'passed'
            or engine.get('player_save_used') is not False or manifest.get('test_report_sha256') != sha(native)):
        raise ValueError('Retained native/export identity required')
    for name, item in manifest['files'].items():
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or chr(92) in name or ':' in name:
            raise ValueError('Unsafe export inventory')
        target = root/'build/web'/name
        if sha(target) != item['sha256'] or target.stat().st_size != item['bytes']:
            raise ValueError('Compiled export changed')
    # Use the exact original transformer without a Godot/import/export/test call.
    import sys
    sys.path.insert(0, str(source/'tools'))
    spec = importlib.util.spec_from_file_location('retained_original_transform', source/'tools/build_itch_trusted_preview.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.prepare_stable(root/'build', root/'variant', json.loads((source/'platform/firebase/public-config.json').read_bytes()), SOURCE, TREE)
    validate_derived_variant(root)
    # Transparent test-only overlay. Production boot/session/client bytes are untouched.
    shutil.copyfile(frozen/'retained_handoff_driver.mjs', source/'platform/firebase/fullflow.test.mjs')
    shutil.copyfile(frozen/'retained_handoff_network.mjs', source/'platform/firebase/fullflow_network.mjs')
    receipt = {'diagnostic_only': True, 'release_qualification': False, 'deployable': False,
        'compiled_source': SOURCE, 'compiled_tree': TREE, 'observer_base': BASE, 'observer_sha256': DRIVER,
        'network_observer_sha256': NETWORK, 'variant_manifest_sha256': VARIANT,
        'export_manifest_sha256': sha(root/'build/web/release-manifest.json'), 'native_sha256': sha(native),
        'geometry_input_sha256': sha(root/'evidence'/prefix/'geometry-1-input.json'),
        'geometry_result_sha256': sha(root/'evidence'/prefix/'geometry-1-result.json'),
        'new_engine_or_geometry': False, 'source_overlay_not_git_head': True}
    with (root/'diagnostic-binding.json').open('x', encoding='utf-8') as stream:
        stream.write(json.dumps(receipt, indent=2)+'\n')
    return receipt

def proc_identity(pid):
    try:
        text = Path('/proc', str(pid), 'stat').read_text()
    except FileNotFoundError:
        return None
    parts = text[text.rfind(')')+2:].split()
    return {'pid': pid, 'state': parts[0], 'parent': int(parts[1]), 'group': int(parts[2]), 'start': parts[19]}

def descendants():
    rows = [proc_identity(int(path.name)) for path in Path('/proc').iterdir() if path.name.isdecimal()]
    known = {os.getpid()}
    for _ in range(128):
        added = {row['pid'] for row in rows if row and row['parent'] in known}
        if added.issubset(known):
            return [row for row in rows if row and row['pid'] in known and row['pid'] != os.getpid()]
        known.update(added)
    raise RuntimeError('Owned process tree unstable')

def listener_owned(pid):
    inodes = set()
    for link in Path('/proc', str(pid), 'fd').iterdir():
        try:
            target = os.readlink(link)
        except FileNotFoundError:
            continue
        if target.startswith('socket:['):
            inodes.add(target[8:-1])
    listeners = []
    for name, ipv6 in [('tcp', False), ('tcp6', True)]:
        for line in Path('/proc/net', name).read_text().splitlines()[1:]:
            fields = line.split()
            addr, port = fields[1].split(':')
            if fields[3] != '0A' or int(port, 16) != 8080:
                continue
            raw = bytes.fromhex(addr)
            if ipv6:
                value = ipaddress.IPv6Address(b''.join(raw[i:i+4][::-1] for i in range(0, 16, 4)))
                exact = value.ipv4_mapped == ipaddress.IPv4Address('127.0.0.1')
            else:
                exact = ipaddress.IPv4Address(raw[::-1]) == ipaddress.IPv4Address('127.0.0.1')
            listeners.append(exact and fields[9] in inodes)
    return bool(listeners) and all(listeners)

def display_owned(pid):
    inodes = set()
    for link in Path('/proc', str(pid), 'fd').iterdir():
        try:
            target = os.readlink(link)
        except FileNotFoundError:
            continue
        if target.startswith('socket:['):
            inodes.add(target[8:-1])
    rows = [line.split() for line in Path('/proc/net/unix').read_text().splitlines()[1:]]
    matches = [row for row in rows if len(row) == 8 and row[7] == '/tmp/.X11-unix/X199']
    return bool(matches) and all(row[6] in inodes for row in matches)

def cleanup_timeout(hard, cap, observed):
    return max(0, min(cap, hard-observed))

def completion_flags(physical, durable, hard, observed):
    within = observed <= hard
    return {'physically_released': physical, 'durable_terminal_written': durable,
        'complete_within_hard_cap': physical and durable and within,
        'queue_release': physical and durable and within}

def run(root, env):
    image_gate(env)
    start = float(env['LL_RETAINED_START_MONOTONIC'])
    work, hard = start+420, start+480
    if time.monotonic() >= work:
        raise TimeoutError('Preparation exhausted original work budget')
    if env.get('GITHUB_RUN_ATTEMPT') != '1':
        raise ValueError('No workflow retry permitted')
    output = root/'diagnostic-output'
    output.mkdir(exist_ok=False)
    errors, roots, logs = [], [], []
    facts = {'diagnostic_only': True, 'deployable': False, 'release_qualification': False,
        'roots': [], 'cleanup_errors': errors, 'owned_tree_zero': False, 'queue_release': False}
    def save():
        temporary = output/'terminal.tmp'
        with temporary.open('w', encoding='utf-8') as stream:
            stream.write(json.dumps(facts, indent=2)+'\n'); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, output/'terminal.json')
    def attempt(label, fn):
        try:
            return fn()
        except BaseException as exc:
            errors.append({'operation': label, 'type': type(exc).__name__})
            return None
    def remaining(limit):
        value = limit-time.monotonic()
        if value <= 0:
            raise TimeoutError('Absolute diagnostic budget exhausted')
        return value
    child_env = {'PATH': env['PATH'], 'DISPLAY': ':199', 'FIRESTORE_EMULATOR_HOST': '127.0.0.1:8080',
        'GCLOUD_PROJECT': 'demo-little-leaf', 'GOOGLE_CLOUD_PROJECT': 'demo-little-leaf',
        'PLAYWRIGHT_MODULE': env['LL_RETAINED_PLAYWRIGHT'], 'PLAYWRIGHT_CHROMIUM_CHANNEL': 'chrome',
        'DEBUG': 'pw:browser', 'LANG': 'C.UTF-8'}
    for name in ['HOME', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'TMPDIR']:
        folder = output/'disposable'/name; folder.mkdir(parents=True); child_env[name] = str(folder)
    def launch(name, command):
        remaining(work)
        fact = {'name': name, 'pid': None, 'start': None, 'exit_code': None, 'log_closed': False}
        facts['roots'].append(fact)
        log = (output/(name+'.log')).open('xb'); logs.append((fact, log))
        process = subprocess.Popen(command, cwd=root/'source/platform/firebase', env=child_env,
            stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        roots.append((process, fact))
        fact['pid'] = process.pid
        identity = proc_identity(process.pid)
        fact['start'] = identity['start']
        save()
        return process
    def version(name, command, expected):
        process = launch(name, command)
        process.wait(timeout=min(10, remaining(work)))
        observed = (output/(name+'.log')).read_text().strip()
        matches = observed == expected if name != 'java-version' else expected in observed
        if process.returncode != 0 or not matches:
            raise ValueError('Pinned '+name+' required; no install/fallback')
        facts.setdefault('tool_sha256', {})[name] = sha(Path(shutil.which(command[0]) or command[0]).resolve())
    try:
        if ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) != 0:
            raise RuntimeError('Owned subreaper unavailable')
        version('node-version', ['node', '--version'], 'v22.23.3')
        version('chrome-version', ['google-chrome', '--version'], 'Google Chrome '+CHROME)
        version('java-version', [env['JAVA_HOME_21_X64']+'/bin/java', '-version'], 'version "21.')
        for name, expected in [('firebase', '12.19.0'), ('firebase-tools', '15.12.0'), ('@firebase/rules-unit-testing', '5.0.0')]:
            package = root/'source/platform/firebase/node_modules'/name/'package.json'
            if json.loads(package.read_bytes()).get('version') != expected:
                raise ValueError('Pinned synthetic dependency required')
        if json.loads((Path(env['LL_RETAINED_PLAYWRIGHT'])/'package.json').read_bytes()).get('version') != '1.63.0':
            raise ValueError('Pinned Playwright required')
        jar = root/'cloud-firestore-emulator-v1.20.4.jar'
        if sha(jar) != JAR:
            raise ValueError('Pinned emulator required')
        if Path('/tmp/.X11-unix/X199').exists() or Path('/tmp/.X199-lock').exists():
            raise RuntimeError('Display already occupied')
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 8080))
        xvfb = launch('xvfb', ['Xvfb', ':199', '-screen', '0', '1360x880x24', '-nolisten', 'tcp'])
        display_end = min(work, time.monotonic()+10)
        while not Path('/tmp/.X11-unix/X199').exists():
            if xvfb.poll() is not None:
                raise RuntimeError('Owned display exited')
            time.sleep(min(.1, remaining(display_end)))
        if not display_owned(xvfb.pid):
            raise RuntimeError('Display socket ownership unverified')
        java = launch('java', [env['JAVA_HOME_21_X64']+'/bin/java', '-Duser.language=en', '-jar', str(jar),
            '--host', '127.0.0.1', '--port', '8080', '--project_id', 'demo-little-leaf',
            '--rules', str(root/'source/platform/firebase/firestore.rules')])
        ready_end = min(work, time.monotonic()+30)
        while not listener_owned(java.pid):
            if java.poll() is not None:
                raise RuntimeError('Owned emulator exited')
            time.sleep(min(.1, remaining(ready_end)))
        node = launch('scenario', ['node', str(root/'source/platform/firebase/fullflow.test.mjs'),
            '--web-build', str(root/'build/web'), '--output', str(output/'scenario'),
            '--engine-report', str(root/'evidence/engine-evidence/summary.json'),
            '--itch-test-variant', str(root/'variant'), '--diagnostic-only',
            '--retained-geometry-input', str(root/'evidence/web-build/evidence/firebase-fullflow/geometry-1-input.json'),
            '--retained-geometry-result', str(root/'evidence/web-build/evidence/firebase-fullflow/geometry-1-result.json')])
        while node.poll() is None:
            if java.poll() is not None or xvfb.poll() is not None or not listener_owned(java.pid):
                raise RuntimeError('Owned fixture service lost')
            try:
                node.wait(timeout=min(1, remaining(work)))
            except subprocess.TimeoutExpired:
                pass
        facts['scenario_exit_code'] = node.returncode
    except BaseException as exc:
        facts['failure_type'] = type(exc).__name__
    finally:
        # Each cleanup operation is independent; unresolved facts always HOLD.
        for process, fact in roots:
            current = attempt('root-identity', lambda: proc_identity(process.pid))
            running = attempt('root-poll', process.poll) is None
            if running and (fact['start'] is None or current and current['start'] == fact['start']):
                attempt('group-term', lambda p=process: os.killpg(p.pid, signal.SIGTERM))
        end = min(hard, time.monotonic()+10)
        for process, fact in roots:
            attempt('root-wait', lambda p=process: p.wait(timeout=cleanup_timeout(end, 10, time.monotonic())))
        children = attempt('owned-descendants', descendants)
        for row in children or []:
            current = attempt('child-identity', lambda p=row['pid']: proc_identity(p))
            if current and current['start'] == row['start']:
                attempt('owned-child-kill', lambda p=row['pid']: os.kill(p, signal.SIGKILL))
        for process, fact in roots:
            fact['exit_code'] = attempt('final-root-wait', lambda p=process: p.wait(timeout=cleanup_timeout(hard, 5, time.monotonic())))
        def reap():
            while True:
                try:
                    pid, _ = os.waitpid(-1, os.WNOHANG)
                except ChildProcessError:
                    return
                if pid == 0:
                    return
        attempt('reap', reap)
        end = min(hard, time.monotonic()+10)
        while time.monotonic() < end:
            attempt('reap', reap)
            observed = attempt('wait-owned-tree', descendants)
            if observed == []:
                break
            time.sleep(min(.1, max(0, end-time.monotonic())))
        for fact, log in logs:
            attempt('log-close', log.close)
            fact['log_closed'] = log.closed
        final = attempt('final-owned-tree', descendants)
        facts['owned_tree_zero'] = final == []
        facts['remaining_owned_pids'] = None if final is None else [r['pid'] for r in final]
        physical = facts['owned_tree_zero'] and all(f['exit_code'] is not None and f['log_closed'] for f in facts['roots']) and not errors
        observed = time.monotonic()
        facts.update(completion_flags(physical, False, hard, observed))
        facts['elapsed_seconds'] = observed-start
        facts['status'] = 'PHYSICAL_TERMINAL_PENDING_DURABILITY' if physical else 'HOLD_CLEANUP_UNRESOLVED'
        saved = attempt('durable-terminal', lambda: (save(), True)[1])
        observed = time.monotonic()
        facts.update(completion_flags(physical, saved is True, hard, observed))
        facts['elapsed_seconds'] = observed-start
        facts['status'] = ('TERMINAL_RELEASED' if facts['queue_release'] else
            'LATE_PHYSICAL_TERMINAL_INCOMPLETE' if physical and saved is True else 'HOLD_CLEANUP_UNRESOLVED')
        sealed = attempt('durable-completion', lambda: (save(), True)[1])
        observed = time.monotonic()
        if sealed is not True or observed > hard:
            facts.update(completion_flags(physical, sealed is True, hard, observed))
            facts['elapsed_seconds'] = observed-start
            facts['status'] = 'LATE_PHYSICAL_TERMINAL_INCOMPLETE' if physical and sealed is True else 'HOLD_CLEANUP_UNRESOLVED'
            attempt('durable-incomplete', save)
    if not facts['queue_release'] or facts.get('scenario_exit_code') != 0 or facts.get('failure_type'):
        raise SystemExit(1)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--coordinator', type=Path, required=True)
    parser.add_argument('--run', action='store_true')
    args = parser.parse_args()
    if args.run:
        run(args.root.resolve(), os.environ)
    else:
        prepare(args.root.resolve(), args.coordinator.resolve())

if __name__ == '__main__':
    main()
