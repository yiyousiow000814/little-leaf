"""Exact reviewed sink composition, fixed candidate pixels and immutable old control."""
import hashlib,subprocess
HEAD='d77e41e5eae5ee1d1eea8dc7e59ad2aa8bf56e86'
TREE='16cb8e578bbbab9002b61dd50aa1e68a320e28a4'
REFERENCE='3e828422d7b00d9ab00746bdc3ab9e5e8053141e'
FURNITURE='9e0589bcb4f7ce607d402e667b2638bfe1c728f08fa882df584ac97fd8256ea1'
def expected_for(label,item,original,declaration):
 if label=='control':return original
 assert label=='candidate' and item==declaration['source']==declaration['proposal']=={'commit':HEAD,'tree':TREE}
 assert declaration['artifact']['png_sha256']=='a0e1c4c5d51a857f8e634f29e38362463b056fd637233ddba5b19cc406589a00'
 assert declaration['artifact']['rgba_sha256']==FURNITURE and declaration['artifact']['size']==[1280,3244]
 return [FURNITURE,*original[1:]]
def verify_proposal(work,item,declaration,closure):
 def git(*args):return subprocess.check_output(['git','-C',str(work),*args],text=True).strip()
 assert git('rev-parse','HEAD')==item['commit']==HEAD and git('rev-parse','HEAD^{tree}')==item['tree']==TREE
 assert git('rev-parse','HEAD^')=='eb1587b5552be6410248cac974555e2ad3336993' and closure['parents']==['eb1587b5552be6410248cac974555e2ad3336993']
 assert git('rev-parse','HEAD^^')==REFERENCE
 assert closure['head']==HEAD and closure['tree']==TREE and closure['reference']==REFERENCE
 assert git('rev-parse',REFERENCE+'^{tree}')==closure['reference_tree']
 assert set(git('diff','--name-only',REFERENCE,HEAD).splitlines())==set(closure['relative_delta']) and len(closure['relative_delta'])==11
 def tree(head):return {line.split('\t',1)[1]:line.split('\t',1)[0] for line in git('ls-tree','-r',head).splitlines()}
 before=tree(REFERENCE);after=tree(HEAD);unchanged={p for p in before if p not in closure['relative_delta']}
 assert len(unchanged)==921 and all(after.get(p)==before[p] for p in unchanged)
 expected_runtime={'game/scripts/cafe_model.gd','game/scripts/cafe_dishwashing.gd','game/scripts/cafe_sink_wash_art.gd','game/scripts/directional_character_art.gd','game/scripts/illustrated_cafe.gd','game/scripts/main.gd'}
 assert {p for p in closure['relative_delta'] if p.startswith('game/')}==expected_runtime
 assert len(closure['producer_closure'])==132
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
 return {'source':item,'reference':REFERENCE,'closure_verified':132,'relative_files_verified':11,'runtime_files_verified':6,'other_base_entries_unchanged':921,'unchanged_assets_and_imports_verified':6}
