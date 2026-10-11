"""Verify the table-only delta against an exact qualified PR140 control.

Generation produces evidence only. Parity requires an independently frozen PNG
declaration before launching the engine; this helper never writes a manifest.
"""
import argparse,hashlib,json,os,pathlib,re,shutil,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from project_layout import stage_project
NAMES=['furniture','moving','heads']
CONTROL='tests/diagnostics/table_atlas_control.json'
def sha(data):return hashlib.sha256(data).hexdigest()
def git(*args):return subprocess.check_output(['git','-c',f'safe.directory={ROOT.as_posix()}','-C',str(ROOT),*args])
def read(ref,name):return git('show',ref+':'+name)
def function_mask(data,names):
 for name in names:
  m=re.search(rb'^(?:static )?func '+name.encode()+rb'\(',data,re.M)
  assert m,name
  end=re.search(rb'^(?:static )?func ',data[m.end():],re.M)
  finish=m.end()+end.start() if end else len(data)
  data=data[:m.start()]+b'OWNED_TABLE_FUNCTION\n'+data[finish:]
 return data
def verify_control(head,baseline,control):
 assert re.fullmatch('[0-9a-f]{40}',head) and re.fullmatch('[0-9a-f]{40}',baseline)
 assert baseline==control['baseline_head']
 assert git('rev-parse',baseline+'^{tree}').decode().strip()==control['baseline_tree']
 subprocess.run(['git','-c',f'safe.directory={ROOT.as_posix()}','-C',str(ROOT),'merge-base','--is-ancestor',baseline,head],check=True)
 manifest=read(baseline,'game/data/prebaked_atlas_manifest.json')
 assert sha(manifest)==control['manifest_sha256']
 ledger=json.loads(manifest)
 assert ledger['version']==1 and ledger['engine']=='4.6.3'
 # Recompute the complete control closure; no newly introduced edge escapes.
 pending=['scripts/furniture_atlas_painter.gd','scripts/moving_art_painter.gd','scripts/character_head_painter.gd'];found={}
 blobs=set(git('ls-tree','-r','--name-only','-z',baseline).decode().rstrip('\0').split('\0'))
 while pending:
  name=pending.pop()
  if name in found:continue
  data=read(baseline,'game/'+name);found[name]=sha(data)
  if pathlib.Path(name).suffix in {'.gd','.gdshader','.tscn','.tres','.json'}:
   for dep in re.findall(r'res://([^"\'\s]+)',data.decode('utf-8')):
    if 'game/'+dep in blobs:pending.append(dep)
 assert dict(sorted(found.items()))==ledger['source_sha256']
 for name in NAMES:
  info=control['atlases'][name];assert info==ledger['atlases'][name]
  assert sha(read(baseline,'game/assets/cache/'+name+'-atlas.png'))==info['png_sha256']
  assert sha(read(baseline,'game/assets/cache/'+name+'-atlas.png.import'))==info['import_sha256']
  assert (ROOT/'game/assets/cache'/f'{name}-atlas.png.import').read_bytes()==read(baseline,'game/assets/cache/'+name+'-atlas.png.import')
  if name!='furniture':assert (ROOT/'game/assets/cache'/f'{name}-atlas.png').read_bytes()==read(baseline,'game/assets/cache/'+name+'-atlas.png')
 changed=set(git('diff','--name-only',baseline,head,'--','game').decode().splitlines())
 assert changed<={'game/scripts/dining_style_art.gd','game/scripts/illustrated_cafe.gd','game/assets/cache/furniture-atlas.png','game/data/prebaked_atlas_manifest.json'},changed
 owned={'game/scripts/dining_style_art.gd':['_cottage_table','_retro_table','_refined_table'],'game/scripts/illustrated_cafe.gd':['_table_body']}
 for path,names in owned.items():
  assert function_mask(read(baseline,path),names)==function_mask((ROOT/path).read_bytes(),names),path
 return ledger
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--godot',required=True);p.add_argument('--expected-head',required=True)
 p.add_argument('--baseline-ref',required=True);p.add_argument('--phase',choices=['generate','parity'],required=True)
 p.add_argument('--proposal-declaration',type=pathlib.Path);p.add_argument('--proposal-png',type=pathlib.Path)
 p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
 head=git('rev-parse','HEAD').decode().strip();assert head==a.expected_head and not git('status','--porcelain')
 control=json.loads((ROOT/CONTROL).read_text(encoding='utf-8'));ledger=verify_control(head,a.baseline_ref,control)
 declaration=None
 if a.phase=='parity':
  assert a.proposal_declaration and a.proposal_png
  declaration=json.loads(a.proposal_declaration.read_text(encoding='utf-8'))
  assert declaration['source_head']==head and declaration['baseline_head']==a.baseline_ref
  assert declaration['source_tree']==git('rev-parse','HEAD^{tree}').decode().strip()
  assert sha(a.proposal_png.read_bytes())==declaration['png_sha256']
  assert re.fullmatch('[0-9a-f]{64}',declaration['rgba_sha256'])
 out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);project=out/'project'
 stage_project(ROOT,project,tests=True,ignore=shutil.ignore_patterns('.godot','__pycache__'))
 # Compare candidate regeneration with immutable qualified before pixels.
 for name in NAMES:(project/'assets/cache'/f'{name}-atlas.png').write_bytes(read(a.baseline_ref,'game/assets/cache/'+name+'-atlas.png'))
 env=os.environ.copy()
 for key in ['APPDATA','LOCALAPPDATA','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:env[key]=str(out/'synthetic-profile')
 env.update(TABLE_ATLAS_OUTPUT=str(out),LIBGL_ALWAYS_SOFTWARE='1',TABLE_EXPECTED_RGBA=json.dumps([ledger['atlases'][n]['rgba_sha256'] for n in NAMES]))
 if declaration:env['TABLE_PROPOSAL_RGBA']=declaration['rgba_sha256']
 config=project/'project.godot';original=config.read_text(encoding='utf-8');stages=[]
 def run(label,args):
  with (out/(label+'.log')).open('wb') as log:r=subprocess.run([a.godot,'--audio-driver','Dummy','--path',str(project),*args],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=120,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
  stages.append({'stage':label,'exit':r.returncode});assert r.returncode==0,label
 config.write_text(original+'\n[editor]\nimport/use_multiple_threads=false\n',encoding='utf-8')
 run('import',['--headless','--editor','--import','--quit']);config.write_text(original,encoding='utf-8')
 env['TABLE_ATLAS_MODE']='generate';run('generate',['--rendering-method','gl_compatibility','--script','res://tests/diagnostics/table_atlas.gd'])
 generation=json.loads((out/'generate.json').read_text(encoding='utf-8'));assert not generation['failures']
 assert generation['engine']=='4.6.3-stable (official)' and generation['display_server']=='X11' and generation['renderer']=='gl_compatibility'
 if declaration:
  assert generation['baseline_sha256'][0]==declaration['rgba_sha256']
  shutil.copyfile(a.proposal_png,project/'assets/cache/furniture-atlas.png')
  config.write_text(original+'\n[editor]\nimport/use_multiple_threads=false\n',encoding='utf-8')
  run('reimport',['--headless','--editor','--import','--quit']);config.write_text(original,encoding='utf-8')
  env['TABLE_ATLAS_MODE']='verify';run('verify',['--rendering-method','gl_compatibility','--script','res://tests/diagnostics/table_atlas.gd'])
  verification=json.loads((out/'verify.json').read_text(encoding='utf-8'))
  assert not verification['failures'] and verification['baseline_sha256']==verification['candidate_sha256']
  assert len(verification['runtime_requests'])==3 and all(x['prebaked'] and x['bake_draws']==0 for x in verification['runtime_requests'])
  (out/'atlas-parity.json').write_text(json.dumps(verification,indent=2)+'\n',encoding='utf-8')
 tracked=git('ls-files','-z').decode().split('\0')
 report={'status':'passed' if declaration else 'generated_pending_independent_declaration','source_head':head,'source_tree':git('rev-parse','HEAD^{tree}').decode().strip(),'baseline_head':a.baseline_ref,'control_sha256':sha((ROOT/CONTROL).read_bytes()),'source_sha256':{n:sha((ROOT/n).read_bytes()) for n in tracked if n},'godot_sha256':sha(pathlib.Path(a.godot).read_bytes()),'stages':stages,'new_png_sha256':sha((out/'furniture-atlas.png').read_bytes()),'table_mask_only':True,'moving_heads_unchanged':True,'manifest_written':False,'proposal_declaration_sha256':sha(a.proposal_declaration.read_bytes()) if declaration else None}
 (out/'source-receipt.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 assert not git('status','--porcelain')
 print(json.dumps({'status':report['status'],'head':head,'baseline':a.baseline_ref,'manifest_written':False}))
if __name__=='__main__':main()
