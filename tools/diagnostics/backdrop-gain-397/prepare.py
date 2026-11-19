"""Exact product -> DISPOSABLE diagnostic only. Never edit the product checkout."""
import hashlib, json, os, subprocess, sys, tarfile
from pathlib import Path
D=Path(__file__).resolve().parent
HEAD='ce1435afb2329a6c1d2d77a8a19923dfd96bd205'
TREE='03632a0d56e4294f5664859656c8809541766d1b'
ARCHIVE='5a236669cca594a1437b289f4b4b8a933a204ddab064844485d2868ce8ee1406'
FIXTURE='ed6fcfc1e4a3396389eff71b09f60740d099de9c046eb0e37eabe900e8c1cf4f'
PRE={'project.godot':'09a15b9558d981fe31f4a0fe4b83c6c98bbad4cd7bbc03d840e76ad7da87bf93',
 'scripts/main.gd':'8c61d1056fc19d206d1bfbfeed6d1f746c94cd32d847ca8c66b0ed84e06b847f',
 'scripts/rendering/illustrated_cafe.gd':'ab7f4942e446c1e0d4116635d8aa5329b2ae82ff5ec6bd0cc99db2c86ee1926b',
 'scripts/rendering/cafe_background_cache.gd':'11cb8b2ff175dc354533c1ce043c53520ea062797aca7a837c168520549d14fd'}
h=lambda value:hashlib.sha256(value).hexdigest()
def need(x):
 if not x:raise ValueError('source/diagnostic stage mismatch')
def git(repo,*args):return subprocess.check_output(['git','-C',str(repo),*args]).decode().strip()
def prepare(repo,target):
 repo=repo.resolve(strict=True);target=target.resolve();need(not target.exists() and not target.is_relative_to(repo))
 need(git(repo,'rev-parse','HEAD')==HEAD and git(repo,'rev-parse','HEAD^{tree}')==TREE)
 command=['git','-C',str(repo),'archive','--format=tar','--mtime=2000-01-01T00:00:00Z',TREE,'game']
 with subprocess.Popen(command,stdout=subprocess.PIPE) as proc:
  need(hashlib.file_digest(proc.stdout,'sha256').hexdigest()==ARCHIVE and proc.wait()==0)
 target.mkdir(mode=0o700)
 with subprocess.Popen(command,stdout=subprocess.PIPE) as proc:
  with tarfile.open(fileobj=proc.stdout,mode='r|') as archive:archive.extractall(target,filter='data')
  proc.stdout.read()
  need(proc.wait()==0)
 game=target/'game'
 need(all(h((game/n).read_bytes())==d for n,d in PRE.items()))
 cfg=game/'project.godot';artist=game/'scripts/rendering/illustrated_cafe.gd'
 bb=cfg.read_bytes();need(b'[autoload]' not in bb and bb.count(b'\n[display]\n')==1 and bb.count(b'run/main_scene="res://main.tscn"')==1)
 cfg.write_bytes(bb.replace(b'\n[display]\n',b'\n[autoload]\n\nLL397BackdropGain="*res://ll397_gain_probe.gd"\n\n[display]\n'))
 existing=b'var background_cache=preload("res://scripts/rendering/cafe_background_cache.gd").new()'
 alternative=b'var background_cache=preload("res://ll397_active_backdrop.gd").new()'
 bb=artist.read_bytes();need(bb.count(existing)==1 and alternative not in bb);artist.write_bytes(bb.replace(existing,alternative))
 for src,dst in [('probe.gd','ll397_gain_probe.gd'),('ll397_active_backdrop.gd','ll397_active_backdrop.gd'),('ll397_forensic_diff.gd','ll397_forensic_diff.gd')]:
  with (game/dst).open('xb') as f:f.write((D/src).read_bytes())
 fixture=(D/'fixture.json').read_bytes();need(h(fixture)==FIXTURE)
 data=target/'private/data/godot/app_userdata/Little Leaf Cafe';data.mkdir(parents=True)
 with (data/'little_leaf_cafe_layout_motion_v15.json').open('xb') as f:f.write(fixture)
 for name in ('home','cache','config'):(target/'private'/name).mkdir()
 names=['project.godot','scripts/rendering/illustrated_cafe.gd','ll397_gain_probe.gd','ll397_active_backdrop.gd','ll397_forensic_diff.gd']
 receipt={'head':HEAD,'tree':TREE,'game_before_sha256':ARCHIVE,'synthetic_fixture':FIXTURE,'staged_postimages':{n:h((game/n).read_bytes()) for n in names}}
 (target/'diagnostic-source.json').write_text(json.dumps(receipt,indent=2)+'\n')
 return receipt
if __name__=='__main__':print(json.dumps(prepare(*(Path(x) for x in sys.argv[1:])),sort_keys=True))
