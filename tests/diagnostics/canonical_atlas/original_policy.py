"""Frozen PR161 source predicate; candidate and control share original exact pixels."""
import hashlib,subprocess
HEAD='35bdb116509c2d07229e4cdb2d48a3b55e0c3d2d'
TREE='ec2587e7187156c8219bed2e121af8871548cfd5'
REFERENCE='50160069fa24fb8cfc0a97a74589526e7f9f5eff'
def expected_for(label,item,original,declaration):
 if label=='control':return original
 assert label=='candidate' and item==declaration['source']==declaration['proposal']=={'commit':HEAD,'tree':TREE}
 assert declaration['expected_rgba']==original
 return original
def verify_proposal(work,item,declaration,closure):
 def git(*args):return subprocess.check_output(['git','-C',str(work),*args],text=True).strip()
 assert git('rev-parse','HEAD')==item['commit']==HEAD and git('rev-parse','HEAD^{tree}')==item['tree']==TREE
 assert git('rev-parse','HEAD^')==REFERENCE and closure['parents']==[REFERENCE]
 assert closure['head']==HEAD and closure['tree']==TREE and closure['reference']==REFERENCE
 assert git('rev-parse',REFERENCE+'^{tree}')==closure['reference_tree']
 assert set(git('diff','--name-only',REFERENCE,HEAD).splitlines())==set(closure['relative_delta']) and len(closure['relative_delta'])==6
 assert {p for p in closure['relative_delta'] if p.startswith('game/')}=={'game/scripts/cafe_model.gd','game/scripts/main.gd','game/scripts/minimal_start.gd'}
 assert len(closure['producer_closure'])==121
 for path,row in list(closure['relative_delta'].items())+ [('game/'+n,r) for n,r in closure['producer_closure'].items()]:
  assert git('rev-parse',HEAD+':'+path)==row['git_blob'],path
  assert hashlib.sha256((work/path).read_bytes()).hexdigest()==row['sha256'],path
 assert len(closure['unchanged_assets_and_imports'])==6
 for path,row in closure['unchanged_assets_and_imports'].items():
  assert git('rev-parse',HEAD+':'+path)==git('rev-parse',REFERENCE+':'+path)==row['git_blob'],path
  assert hashlib.sha256((work/path).read_bytes()).hexdigest()==row['sha256'],path
 for path,digest in closure['protected_unchanged'].items():
  assert git('rev-parse',HEAD+':'+path)==git('rev-parse',REFERENCE+':'+path),path
  assert hashlib.sha256((work/path).read_bytes()).hexdigest()==digest,path
 return {'source':item,'reference':REFERENCE,'closure_verified':len(closure['producer_closure']),'relative_files_verified':6,'runtime_files_verified':3,'unchanged_assets_and_imports_verified':6}
