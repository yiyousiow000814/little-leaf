"""Frozen successor source predicate, retaining the reviewed candidate pixel vector."""
import hashlib,subprocess
HEAD='cfb5ae9bc5a92fc46c2561b13f97b38e2ba4e9a5'
TREE='db38763f84d7a14b814ef23eb67359ceeeb24e4d'
PARENT='dfd82c49637118f17d914173b8bf8dd43c169600'
REFERENCE='a867c3ba0b5a26943deb3fe221815dbc093e96f2'
REFERENCE_TREE='a7662f13ad69a62834e4ea6456deaf62a4edba76'
FURNITURE='9e0589bcb4f7ce607d402e667b2638bfe1c728f08fa882df584ac97fd8256ea1'
def expected_for(label,item,original,declaration):
 if label=='control':return original
 assert label=='candidate' and item==declaration['proposal']==declaration['source']=={'commit':HEAD,'tree':TREE}
 assert declaration['artifact']['png_sha256']=='a0e1c4c5d51a857f8e634f29e38362463b056fd637233ddba5b19cc406589a00'
 assert declaration['artifact']['rgba_sha256']==FURNITURE and declaration['artifact']['size']==[1280,3244]
 return [FURNITURE,*original[1:]]
def verify_proposal(work,item,declaration,closure):
 def git(*args):return subprocess.check_output(['git','-C',str(work),*args],text=True).strip()
 def blob(head,path):return subprocess.check_output(['git','-C',str(work),'show',head+':'+path])
 assert git('rev-parse','HEAD')==item['commit']==HEAD
 assert git('rev-parse','HEAD^{tree}')==item['tree']==TREE
 assert git('rev-parse','HEAD^')==PARENT and closure['parents']==[PARENT]
 assert git('rev-parse',REFERENCE+'^{tree}')==REFERENCE_TREE
 assert closure['head']==HEAD and closure['tree']==TREE and closure['reference']==REFERENCE
 assert set(git('diff','--name-only',REFERENCE,HEAD).splitlines())==set(closure['relative_delta']) and len(closure['relative_delta'])==9
 assert set(git('diff','--name-only',PARENT,HEAD).splitlines())==set(closure['immediate_delta'])=={'game/scripts/illustrated_cafe.gd','tests/test_bubble_symbol_clarity.gd','tests/test_floor_cleaning_approach.gd'}
 assert {p for p in closure['relative_delta'] if p.startswith('game/')}=={'game/scripts/illustrated_cafe.gd'}
 path='game/scripts/illustrated_cafe.gd';old=blob(PARENT,path);new=blob(HEAD,path)
 broken='\u00e2\u20ac\u00a6'.encode();correct='\u2026'.encode()
 assert old.count(broken)==2 and old.replace(broken,correct)==new,'Runtime delta must be only two original ellipsis literal restorations'
 assert len(closure['producer_closure'])==132
 for resource,row in closure['producer_closure'].items():
  path='game/'+resource
  assert git('rev-parse',HEAD+':'+path)==row['git_blob'],path
  assert hashlib.sha256((work/path).read_bytes()).hexdigest()==row['sha256'],path
 for path,row in closure['relative_delta'].items():
  assert git('rev-parse',HEAD+':'+path)==row['git_blob'] and hashlib.sha256((work/path).read_bytes()).hexdigest()==row['sha256'],path
 assert len(closure['unchanged_assets_and_imports'])==6
 for path,row in closure['unchanged_assets_and_imports'].items():
  assert git('rev-parse',HEAD+':'+path)==git('rev-parse',REFERENCE+':'+path)==row['git_blob'],path
  assert hashlib.sha256((work/path).read_bytes()).hexdigest()==row['sha256'],path
 assert blob(HEAD,'game/data/prebaked_atlas_manifest.json')==blob(REFERENCE,'game/data/prebaked_atlas_manifest.json')
 return {'source':item,'source_reference':REFERENCE,'parent':PARENT,'closure_verified':132,'relative_files_verified':9,'runtime_delta':'two original ellipsis literals only','unchanged_assets_and_imports_verified':6}
