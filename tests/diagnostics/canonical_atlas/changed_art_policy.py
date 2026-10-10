"""Explicit reviewed PR125 candidate policy; original control is never redefined."""
import hashlib,json,subprocess
PARENT='85e9a058d25cff10089d3bc4885339110fb70735'
TREE='c2a38b8b8b0735029dd106dcfa065f2e2ad35565'
FURNITURE='9e0589bcb4f7ce607d402e667b2638bfe1c728f08fa882df584ac97fd8256ea1'
PNG='a0e1c4c5d51a857f8e634f29e38362463b056fd637233ddba5b19cc406589a00'
PATH='game/assets/cache/furniture-atlas.png'
def expected_for(label,item,original,declaration):
 if label=='control':return original
 assert label=='candidate' and item==declaration['proposal']
 assert declaration['source']=={'commit':PARENT,'tree':TREE}
 assert declaration['artifact']=={'origin_run':38079947249,'origin_source':'3f1912bf546456b7300c9de9058b0cf682cb9c47','path':PATH,'png_sha256':PNG,'rgba_sha256':FURNITURE,'size':[1280,3244]}
 return [FURNITURE,*original[1:]]
def verify_proposal(work,item,declaration,closure):
 def git(*args):return subprocess.check_output(['git','-C',str(work),*args],text=True).strip()
 assert git('rev-parse','HEAD')==item['commit']
 assert git('rev-parse','HEAD^{tree}')==item['tree']
 assert git('rev-parse','HEAD^')==PARENT
 assert git('rev-parse',PARENT+'^{tree}')==TREE
 assert git('diff','--name-only',PARENT,item['commit'])==PATH,'Proposal must change only the furniture PNG'
 assert hashlib.sha256((work/PATH).read_bytes()).hexdigest()==PNG
 assert closure['head']==PARENT and closure['tree']==TREE and len(closure['producer_closure'])==132
 for resource,row in closure['producer_closure'].items():
  path='game/'+resource
  if path==PATH:
   assert git('rev-parse',PARENT+':'+path)==row['git_blob'],path
   original=subprocess.check_output(['git','-C',str(work),'show',PARENT+':'+path])
   assert hashlib.sha256(original).hexdigest()==row['sha256'],path
   continue # Sole declared replacement: new encoded SHA was verified above.
  assert git('rev-parse',item['commit']+':'+path)==row['git_blob'],path
  assert hashlib.sha256((work/path).read_bytes()).hexdigest()==row['sha256'],path
 return {'source':declaration['source'],'proposal':item,'closure_verified':132,'sole_changed_path':PATH,'source_png_sha256':PNG}
