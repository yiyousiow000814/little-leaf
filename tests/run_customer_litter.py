#!/usr/bin/env python3
"""Run isolated headless Godot litter checks without reading a player profile."""
from pathlib import Path
import fcntl, json, os, shutil, subprocess, sys, tempfile
repo = Path(__file__).resolve().parents[1]
output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else repo / 'docs/customer-litter'
output.mkdir(parents=True, exist_ok=True)
godot = shutil.which('godot') or shutil.which('godot4')
if not godot:
    raise SystemExit('Godot 4.6.3 is required')
with tempfile.TemporaryDirectory(prefix='little-leaf-litter-') as temp:
    env = os.environ.copy()
    for name, folder in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
        dest = Path(temp) / folder
        dest.mkdir()
        env[name] = str(dest)
    env['LL_LITTER_EVIDENCE'] = str(output / 'headless-results.json')
    with (repo.parent / '.little-leaf-engine.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        result = subprocess.run([godot, '--headless', '--path', str(repo), '--script', 'tests/test_customer_litter.gd'], env=env, text=True, capture_output=True, timeout=120)
    log = result.stdout + result.stderr
    (output / 'headless.log').write_text(log)
    print(log, end='')
    report = json.loads((output / 'headless-results.json').read_text()) if (output / 'headless-results.json').exists() else {}
    passed = result.returncode == 0 and report.get('checks', 0) >= 56 and report.get('failures') == [] and 'SCRIPT ERROR' not in log and '\nERROR:' not in log
    raise SystemExit(0 if passed else 1)
