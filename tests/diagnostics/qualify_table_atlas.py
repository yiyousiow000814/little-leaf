"""Regenerate only the corrected table cell; verify imported cache and untouched atlases."""
import argparse, hashlib, json, os, shutil, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from project_layout import stage_project
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',required=True);p.add_argument('--expected-head',required=True);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
 head=subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD'],text=True).strip();assert head==a.expected_head
 out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
 project=out/'project';stage_project(ROOT,project,tests=True,ignore=shutil.ignore_patterns('.godot','__pycache__'))
 env=os.environ.copy()
 for key in ['APPDATA','LOCALAPPDATA','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:env[key]=str(out/'synthetic-profile')
 env.update(TABLE_ATLAS_OUTPUT=str(out),LIBGL_ALWAYS_SOFTWARE='1')
 config=project/'project.godot';original=config.read_text();config.write_text(original+'\n[editor]\nimport/use_multiple_threads=false\n')
 stages=[]
 def run(label,args):
  with (out/(label+'.log')).open('wb') as log:
   process=subprocess.run([a.godot,'--audio-driver','Dummy','--path',str(project),*args],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=120,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
  stages.append({'stage':label,'exit':process.returncode});assert process.returncode==0,label
 run('import',['--headless','--editor','--import','--quit']);config.write_text(original)
 env['TABLE_ATLAS_MODE']='generate';run('generate',['--rendering-method','gl_compatibility','--script','res://tests/diagnostics/table_atlas.gd'])
 generation=json.loads((out/'generate.json').read_text());assert not generation['failures']
 assert generation['engine']=='4.6.3-stable (official)' and generation['display_server']=='X11' and generation['renderer']=='gl_compatibility'
 destination=project/'assets/cache/furniture-atlas.png';shutil.copy2(out/'furniture-atlas.png',destination)
 config.write_text(original+'\n[editor]\nimport/use_multiple_threads=false\n');run('reimport',['--headless','--editor','--import','--quit']);config.write_text(original)
 env['TABLE_ATLAS_MODE']='verify';run('verify',['--rendering-method','gl_compatibility','--script','res://tests/diagnostics/table_atlas.gd'])
 verification=json.loads((out/'verify.json').read_text());assert not verification['failures'] and verification['baseline_sha256']==verification['candidate_sha256']
 assert len(verification['runtime_requests'])==3 and all(x['prebaked'] and x['bake_draws']==0 for x in verification['runtime_requests'])
 (out/'atlas-parity.json').write_text(json.dumps(verification,indent=2))
 tracked=subprocess.check_output(['git','-C',str(ROOT),'ls-files','-z']).decode().split('\0')
 report={'source_head':head,'source_tree':subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD^{tree}'],text=True).strip(),'source_sha256':{n:sha(ROOT/n) for n in tracked if n},'godot_sha256':sha(Path(a.godot)),'stages':stages,'changed_asset':'assets/cache/furniture-atlas.png','new_png_sha256':sha(out/'furniture-atlas.png'),'scope':'owned table_body cell only; moving/head caches unchanged; source-bound native evidence, no release or FPS claim'}
 (out/'source-receipt.json').write_text(json.dumps(report,indent=2))
 shutil.rmtree(project);shutil.rmtree(out/'synthetic-profile',ignore_errors=True)
 print(json.dumps({'status':'passed','head':head,'checks':3}))
if __name__=='__main__':main()
