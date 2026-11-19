"""Create a disposable, source-bound native diagnostic project. No release artifacts."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
from tempfile import TemporaryDirectory

HERE = Path(__file__).resolve().parent
def hexhash(path):
    with Path(path).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()

def stage(repo, commit, tree, target):
    assert git(repo, 'rev-parse', 'HEAD') == commit, 'checkout identity must be exact'
    assert git(repo, 'rev-parse', 'HEAD^{tree}') == tree, 'tree identity mismatch'
    files = set(git(repo, 'ls-tree', '--name-only', commit).splitlines())
    current = 'game' in files
    roots = ['game'] if current else ['project.godot', 'main.tscn', 'export_presets.cfg', 'assets', 'scripts', 'shaders', 'data', 'web']
    target.mkdir(parents=True, exist_ok=False)
    project = target if not current else target / 'game'
    with TemporaryDirectory(dir=target.parent) as scratch:
        tar = Path(scratch) / 'project.tar'
        subprocess.run(['git','-C',str(repo),'archive','-o',str(tar),commit,*roots],check=True)
        source_archive_sha = hexhash(tar)
        with tarfile.open(tar, 'r:') as archive:
            archive.extractall(target, filter='data')
    cfg = project / 'project.godot'
    before = hexhash(cfg)
    data = cfg.read_text()
    autoload = r'^\[autoload\]\s*$'
    row = 'LLNativeDrawProbe="*res://ll_native_draw_probe.gd"'
    assert row not in data
    if re.search(autoload, data, flags=re.M):
        data = re.sub(autoload, '\\g<0>\n'+row, data, count=1, flags=re.M)
    else:
        data += '\n[autoload]\n\n' + row + '\n'
    cfg.write_text(data)
    probe = project / 'll_native_draw_probe.gd'
    shutil.copyfile(HERE/'native_draw_probe.gd', probe)
    receipt = {'source': {'commit':commit,'tree':tree,'allowed_project_paths':roots,'archive_sha256':source_archive_sha},
      'staged_project': str(project.relative_to(target)),
      'diagnostic_patch': {'project_before_sha256':before,'project_after_sha256':hexhash(cfg),'probe_sha256':hexhash(probe)},
      'scope':'diagnostic-only, no release artifact or FPS result'}
    (target/'diagnostic-source.json').write_text(json.dumps(receipt,indent=2)+'\n')
    return project
if __name__=='__main__':
    p=argparse.ArgumentParser()
    for n in ['repo','commit','tree','output']:
      p.add_argument('--'+n,required=True)
    a=p.parse_args()
    print(stage(Path(a.repo).resolve(),a.commit,a.tree,Path(a.output).resolve()))
