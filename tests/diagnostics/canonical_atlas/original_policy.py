"""Frozen private reception source predicate; candidate and control share original exact pixels."""
import hashlib,subprocess
HEAD='608491523be576a11c713353ef72d6dc7c6964c5'
TREE='bdc2db9e86f7a3c0fbcd3019139751a6673bcc23'
REFERENCE='50160069fa24fb8cfc0a97a74589526e7f9f5eff'
def expected_for(label,item,original,declaration):
 if label=='control':return original
 assert label=='candidate' and item==declaration['source']==declaration['proposal']=={'commit':HEAD,'tree':TREE}
 assert declaration['expected_rgba']==original
 return original
def verify_proposal(work,item,declaration,closure):
 def git(*args):return subprocess.check_output(['git','-C',str(work),*args],text=True).strip()
 assert git('rev-parse','HEAD')==item['commit']==HEAD and git('rev-parse','HEAD^{tree}')==item['tree']==TREE
 assert git('rev-parse','HEAD^')=='1e33781f2c324ba2e7cb4993373f2654dae68615' and closure['parents']==['1e33781f2c324ba2e7cb4993373f2654dae68615']
 assert git('rev-parse','HEAD^^')==REFERENCE
 assert closure['head']==HEAD and closure['tree']==TREE and closure['reference']==REFERENCE
 assert git('rev-parse',REFERENCE+'^{tree}')==closure['reference_tree']
 assert set(git('diff','--name-only',REFERENCE,HEAD).splitlines())==set(closure['relative_delta']) and len(closure['relative_delta'])==36
 assert {p for p in closure['relative_delta'] if p.startswith('game/')}=={'game/scripts/cafe_admission_log.gd', 'game/scripts/cafe_reception_review.gd.uid', 'game/scripts/cafe_table_occupancy.gd.uid', 'game/scripts/cafe_reception.gd.uid', 'game/scripts/cafe_reception_review.gd', 'game/scripts/main.gd', 'game/scripts/cafe_table_occupancy.gd', 'game/scripts/cafe_parking.gd', 'game/scripts/cafe_floor_tasks.gd', 'game/scripts/cafe_departing_bodies.gd', 'game/scripts/cafe_save_contract.gd', 'game/scripts/cafe_reception.gd', 'game/scripts/cafe_admission_log.gd.uid', 'game/scripts/cafe_furniture_motion.gd', 'game/scripts/cafe_runtime_codec.gd', 'game/scripts/illustrated_cafe.gd', 'game/scripts/cafe_departing_bodies.gd.uid', 'game/scripts/cafe_model.gd'}
 assert len(closure['producer_closure'])==126
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
 return {'source':item,'reference':REFERENCE,'closure_verified':len(closure['producer_closure']),'relative_files_verified':36,'runtime_files_verified':18,'unchanged_assets_and_imports_verified':6}
