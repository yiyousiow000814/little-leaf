"""Disposable native geometry probe for the compiled-browser QA harness."""
import argparse,json,os,shutil,subprocess
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tests"))
from run_integration_candidate import EXCLUDE
from build_web import sha256
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();out=a.output.resolve()
 if out.exists():raise ValueError('Use a new disposable geometry directory')
 out.mkdir(parents=True);project=out/'project';shutil.copytree(ROOT,project,ignore=EXCLUDE)
 env=dict(os.environ,XDG_DATA_HOME=str(out/'data'),XDG_CONFIG_HOME=str(out/'config'),XDG_CACHE_HOME=str(out/'cache'))
 godot=os.environ.get('GODOT_BIN','godot');subprocess.run([godot,'--headless','--path',str(project),'--editor','--import'],env=env,stdout=(out/'import.log').open('w'),stderr=subprocess.STDOUT,timeout=120,check=True)
 regressions=[]
 for width,height in [(1360,880),(390,844)]:
  previous=None
  for label,reason in [('short','Paused.'),('wrapped','Your game was opened on another device. Current progress is protected while you choose where to continue.'),('protected','Your game was opened on another device.')]:
   name=f'{width}-{label}';input_file=out/(name+'-input.json');output_file=out/(name+'-result.json')
   value={'viewport':{'width':width,'height':height},'snapshot':{'available':False,'serverOwnership':True,'ownershipPaused':True,'status':'other-device','canRequestTakeover':True,'reason':reason}}
   if label=='protected':value['nativeCallback']={'method':'preserveOwnerRuntime','result':{'ok':True,'durable':True,'profileId':'synthetic-profile','revision':2}}
   input_file.write_text(json.dumps(value))
   subprocess.run([godot,'--headless','--audio-driver','Dummy','--path',str(project),'--script','res://tests/probe_cloud_recovery_geometry.gd','--',str(input_file),str(output_file)],env=env,stdout=(out/(name+'.log')).open('w'),stderr=subprocess.STDOUT,timeout=30,check=True)
   result=json.loads(output_file.read_text());x,y,w,h=result['buttons']['switch']
   if reason not in result['text'] or not (0<=x<x+w<=width and 0<=y<y+h<=height):raise ValueError('Exact-message native geometry invalid')
   if label=='protected' and 'Current progress is protected on this device.' not in result['text']:raise ValueError('Native callback message missing')
   if label=='wrapped' and previous is not None and y==previous:raise ValueError('Wrapped-message regression did not change measured button location')
   previous=y;regressions.append({'viewport':value['viewport'],'message':label,'switch':result['buttons']['switch']})
 (out/'regressions.json').write_text(json.dumps(regressions,indent=2)+'\n')
 receipt={'synthetic_only':True,'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'source_sha256':{n:sha256(ROOT/n) for n in ['tests/probe_cloud_recovery_geometry.gd','tests/test_cloud_recovery_ui.gd','scripts/cafe_compact_ui.gd','scripts/cafe_web_save.gd']},'project':str(project)}
 (out/'binding.json').write_text(json.dumps(receipt,indent=2)+'\n')
if __name__=='__main__':main()
