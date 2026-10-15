"""Exact PR158 recovered Car candidate with unchanged approved atlas resources; original control gates preserved."""
import hashlib,importlib.util,json,subprocess
HEAD='53befa34fd42e8561a220cdf2d680ffc86565019'
TREE='94be9130947b9f7cc0ef019e13b765589a483231'
REFERENCE='16a42d9fec434b13b6dea21a0737239ee3cf894b'
def expected_for(label,item,original,declaration):
 if label=='control':return original
 assert label=='candidate' and item==declaration['source']==declaration['proposal']=={'commit':HEAD,'tree':TREE}
 assert declaration['phase']=='CURRENT_APPROVED_THREE_ATLAS_PARITY' and declaration['original_control_expected_rgba']==original
 assert declaration['expected_rgba']==['ba615c7535d6e3806d1b6b27abf2c50575e59486c8b9ab8c08d4eadff401b5ac',*original[1:]]
 assert declaration['asset_overlay'] is None, 'No diagnostic asset overlay permitted'
 return declaration['expected_rgba']
def verify_proposal(work,item,declaration,closure):
 def raw(*args):return subprocess.check_output(['git','-C',str(work),*args])
 def git(*args):return raw(*args).decode().strip()
 def digest(b):return hashlib.sha256(b).hexdigest()
 assert git('rev-parse','HEAD')==item['commit']==HEAD and git('rev-parse','HEAD^{tree}')==item['tree']==TREE
 assert git('show','-s','--format=%P',HEAD).split()==closure['parents']
 for ref in [REFERENCE]:assert git('merge-base',ref,HEAD)==ref
 assert closure['head']==HEAD and closure['tree']==TREE and closure['reference']==REFERENCE and git('rev-parse',REFERENCE+'^{tree}')==closure['reference_tree']
 assert git('diff','--name-only',REFERENCE,HEAD).splitlines()==closure['relative_paths'] and len(closure['relative_paths'])==41
 assert [p for p in closure['relative_paths'] if p.removeprefix('game/') in closure['producer_closure']]==closure['runtime_paths'] and len(closure['runtime_paths'])==7
 assert len(closure['raw_inventory'])==1420 and len(closure['producer_closure'])==81
 modes={}
 for x in raw('ls-tree','-rz',HEAD).split(b'\0'):
  if x:
   meta,n=x.split(b'\t',1);mode,kind,oid=meta.split();assert kind==b'blob';modes[n.decode()]={'mode':mode.decode(),'git_blob':oid.decode()}
 assert set(modes)=={x['path'] for x in closure['raw_inventory']}
 for row in closure['raw_inventory']:
  assert modes[row['path']]=={'mode':row['mode'],'git_blob':row['git_blob']}
  b=(work/row['path']).read_bytes();assert len(b)==row['bytes'] and digest(b)==row['sha256'],row['path']
 # Exact accepted-main preimages for all unrelated files; no wholefile import.
 old={}
 for x in raw('ls-tree','-rz',REFERENCE).split(b'\0'):
  if x:
   meta,n=x.split(b'\t',1);mode,kind,oid=meta.split();assert kind==b'blob';old[n.decode()]={'mode':mode.decode(),'git_blob':oid.decode()}
 assert not set(old)-set(modes)
 for p in old:
  if p not in closure['relative_paths']:assert old[p]==modes[p],p
 manifest=json.loads((work/'game/data/prebaked_atlas_manifest.json').read_text())
 assert raw('show',REFERENCE+':game/data/prebaked_atlas_manifest.json')==(work/'game/data/prebaked_atlas_manifest.json').read_bytes()
 assert set(manifest['source_sha256']) <= set(closure['producer_closure'])
 assert sorted(set(closure['producer_closure'])-set(manifest['source_sha256']))==closure['added_dependencies'] and len(closure['added_dependencies'])==2
 assert sorted(set(manifest['source_sha256'])-set(closure['producer_closure']))==closure['removed_dependencies']==[]
 for n,row in closure['producer_closure'].items():assert git('rev-parse',HEAD+':game/'+n)==row['git_blob'] and digest((work/('game/'+n)).read_bytes())==row['sha256']
 assert sorted(n for n,row in closure['producer_closure'].items() if n in manifest['source_sha256'] and manifest['source_sha256'][n]!=row['sha256'])==closure['stale_sources'] and len(closure['stale_sources'])==5
 for n,v in manifest['source_sha256'].items():assert digest(raw('show',REFERENCE+':game/'+n))==v,n
 spec=importlib.util.spec_from_file_location('unchanged_guard',work/'tools/qualification/verify_prebaked_atlases.py');guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(guard)
 assert guard.sources()=={n:row['sha256'] for n,row in closure['producer_closure'].items()}
 assert len(closure['unchanged_assets_and_imports'])==6
 for n,v in closure['unchanged_assets_and_imports'].items():assert raw('show',REFERENCE+':'+n)==(work/n).read_bytes() and digest((work/n).read_bytes())==v,n
 for n,v in closure['protected_unchanged'].items():assert raw('show',REFERENCE+':'+n)==(work/n).read_bytes() and digest((work/n).read_bytes())==v,n
 return {'source':item,'reference':REFERENCE,'all_raw_files_verified':1420,'source_modes_verified':1420,'closure_verified':81,'relative_files_verified':41,'runtime_files_verified':7,'stale_source_rows_verified':5,'added_dependencies_verified':2,'removed_dependencies_verified':0,'unchanged_assets_and_imports_verified':6,'old_runtime_proof_transferred':False}
