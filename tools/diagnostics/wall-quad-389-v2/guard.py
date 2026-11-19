"""One push, one reviewed patch, no release path. Archive only the #389 game."""
from pathlib import Path
import hashlib, json, os, shutil, subprocess as sp, sys, tarfile
D=Path(__file__).resolve().parent
SRC='1556f2ad1e9985c723f7f3634a3f48535cc411a2';TREE='f449331e7ae64da7f19fa62b3554062381cb887c'
ARCHIVE='959cb8b47173be82ea921d96144fb6cd91870adccac1191141ddd41ac1ed8229'
PATCH='ed6c2b1affbfebf76df67c9548900be4ca37607738d9d95963d0517c0afa1512'
FIXTURE='ed6fcfc1e4a3396389eff71b09f60740d099de9c046eb0e37eabe900e8c1cf4f'
OWNER='yiyousiow000814';REPO=OWNER+'/little-leaf';REF='refs/heads/qa/wall-quad-389-v2'
WORKFLOW='.github/workflows/wall-quad-389-v2.yml';PREFIX='tools/diagnostics/wall-quad-389-v2/'
FILES={'game/scripts/rendering/'+s+'.gd' for s in ('illustrated_cafe','illustrated_openings','cafe_character_pick_geometry','cafe_shape_2d')}|{'tests/building/test_centered_wall_visuals.gd'}
def need(v):
 if not v:raise ValueError('binding, environment or evidence mismatch')
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def git(r,*args,env=None):
 return sp.check_output(['git','-C',str(r),*args],env=env).decode().strip()
def inputs():
 b=json.loads((D/'binding.json').read_text());need((b['source'],b['tree'],b['patch_sha256'])==(SRC,TREE,PATCH));need(set(b['files'])==FILES)
 need(sha(D/'product.patch')==PATCH and sha(D/'fixture.json')==FIXTURE)
 m=json.loads((D/'diagnostic-files.json').read_text());need(set(m)=={p.name for p in D.iterdir() if p.is_file()}-{'diagnostic-files.json'} and all(sha(D/k)==v for k,v in m.items()));return b
def event(r,env,ev):
 h=env['GITHUB_SHA'];need(env['GITHUB_EVENT_NAME']=='push' and env['GITHUB_REF']==REF and env['GITHUB_ACTOR']==OWNER and env['GITHUB_REPOSITORY']==REPO and env['GITHUB_RUN_ATTEMPT']=='1')
 need(ev['ref']==REF and ev['before']==SRC and ev['after']==h and all(ev.get(k) is False for k in ('created','forced','deleted')))
 need(git(r,'rev-list','--parents','-n','1','HEAD').split()==[h,SRC])
 # No edits (or deletions) of existing files; includes exactly the published kit, no executable product edits.
 paths=set(git(r,'diff','--name-only','HEAD^','HEAD').splitlines())
 need(paths=={WORKFLOW}|{PREFIX+p.name for p in D.iterdir() if p.is_file()})
 need(not git(r,'diff','--name-only','--diff-filter=MDTCRUXB','HEAD^','HEAD'));inputs()
def stage(repo,tmp):
 repo=repo.resolve();tmp=tmp.resolve();b=inputs();tmp.mkdir(parents=True,exist_ok=False)
 need(git(repo,'rev-parse','HEAD')==SRC and git(repo,'rev-parse','HEAD^{tree}')==TREE)
 tar=tmp/'game.tar';sp.run(['git','-C',str(repo),'archive','-o',str(tar),SRC,'game'],check=True);need(sha(tar)==ARCHIVE)
 for arm in ('control','candidate'):
  p=tmp/arm;p.mkdir()
  with tarfile.open(tar) as t:t.extractall(p,filter='data')
 # Apply the full five-file patch in a throwaway index/object store (never the product checkout).
 idx=tmp/'index';objs=tmp/'objects';objs.mkdir()
 env=os.environ|{'GIT_INDEX_FILE':str(idx),'GIT_OBJECT_DIRECTORY':str(objs),'GIT_ALTERNATE_OBJECT_DIRECTORIES':git(repo,'rev-parse','--path-format=absolute','--git-path','objects')}
 git(repo,'read-tree',SRC,env=env);git(repo,'apply','--cached','--check',str(D/'product.patch'),env=env);git(repo,'apply','--cached',str(D/'product.patch'),env=env)
 need(set(git(repo,'diff','--cached','--name-only',SRC,env=env).splitlines())==FILES)
 for name,pins in b['files'].items():
  ref=sp.check_output(['git','-C',str(repo),'show',SRC+':'+name]);after=sp.check_output(['git','-C',str(repo),'show',':'+name],env=env)
  need(hashlib.sha256(ref).hexdigest()==pins['before'] and hashlib.sha256(after).hexdigest()==pins['after'])
  if name.startswith('game/'):
   need((tmp/'control'/name).read_bytes()==ref and (tmp/'candidate'/name).read_bytes()==ref)
   (tmp/'candidate'/name).write_bytes(after)
 for arm in ('control','candidate'):
  p=tmp/arm/'game';shutil.copyfile(D/'capture.gd',p/'capture_wall_quad_parity.gd');shutil.copyfile(D/'fixture.json',p/'wall_quad_parity_21walls.json')
 need(git(repo,'write-tree',env=env)=='d7a4f461f5111820340e322701adba2b44b0b7cc')
 (tmp/'source.json').write_text(json.dumps(dict(source=SRC,tree=TREE,candidate_tree=git(repo,'write-tree',env=env),patch=PATCH,game_archive=ARCHIVE)))
if __name__=='__main__':
 if sys.argv[1]=='event':event(Path('.'),os.environ,json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text()))
 elif sys.argv[1]=='stage':stage(Path(sys.argv[2]),Path(sys.argv[3]))
 else:raise ValueError('unsupported')
