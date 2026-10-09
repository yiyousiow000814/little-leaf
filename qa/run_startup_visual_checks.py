"""Untimed source-bound atlas parity and fixed-position production scene capture."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--expected-head', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--atlas-parity', action='store_true')
    args = parser.parse_args()
    source = args.source_root.resolve()
    head = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    assert head == args.expected_head
    assert not subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'])
    output = args.output.resolve();output.mkdir(parents=True, exist_ok=False)
    scripts = ['qa/capture_startup_positions.gd']
    if args.atlas_parity:scripts.append('qa/check_atlas_warmup_parity.gd')
    with tempfile.TemporaryDirectory(prefix='startup-visual-saveguard-') as temp:
        temp = Path(temp);project = temp / 'project'
        archive = subprocess.check_output(['git','-C',str(source),'archive','--format=zip',head])
        with zipfile.ZipFile(io.BytesIO(archive)) as z:
            assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in z.namelist())
            z.extractall(project)
        originals = {str(p.relative_to(project)):hashlib.sha256(p.read_bytes()).hexdigest() for p in project.rglob('*') if p.is_file()}
        helpers = {}
        for script in scripts:
            content = (ROOT / script).read_bytes()
            if script in originals:assert hashlib.sha256(content).hexdigest() == originals[script]
            (project / script).write_bytes(content)
            helpers[script] = hashlib.sha256(content).hexdigest()
        env = os.environ.copy()
        for key in ['HOME','APPDATA','LOCALAPPDATA','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
            path = temp / key;path.mkdir();env[key] = str(path)
        env['OUTPUT'] = str(output)
        engine = env.get('GODOT_BIN','godot')
        def run(name, arguments):
            result = subprocess.run([engine,'--audio-driver','Dummy','--path',str(project),*arguments],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
            log = result.stdout.decode(errors='replace');(output / (name+'.log')).write_text(log)
            assert result.returncode == 0 and 'ERROR:' not in log, name+' failed'
            return log
        run('import',['--headless','--editor','--import','--quit'])
        run('captures',['--rendering-method','gl_compatibility','--script','res://qa/capture_startup_positions.gd','--','--visual-qa','--fresh-review','--skip-tutorial'])
        if args.atlas_parity:
            log = run('atlas-parity',['--rendering-method','gl_compatibility','--script','res://qa/check_atlas_warmup_parity.gd'])
            payload = [json.loads(line.split(' ',1)[1]) for line in log.splitlines() if line.startswith('ATLAS_RENDER_PARITY_RESULT ')]
            assert len(payload) == 1 and payload[0]['checks'] == 3 and not payload[0]['failures']
            (output/'atlas-parity.json').write_text(json.dumps(payload[0],indent=2))
        assert all(hashlib.sha256((project/name).read_bytes()).hexdigest() == digest for name,digest in originals.items())
        (output/'source-binding.json').write_text(json.dumps({'source_commit':head,'source_sha256':originals,'diagnostic_sha256':helpers,'player_data_used':False,'timing_claim':False},indent=2))

if __name__ == '__main__':main()
