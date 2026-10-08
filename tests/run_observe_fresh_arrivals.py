"""Real-time, normal-startup arrival observation in generated isolated profiles."""
import argparse, fcntl, json, os, pathlib, shutil, subprocess
p=argparse.ArgumentParser()
p.add_argument('--project',type=pathlib.Path,default=pathlib.Path(__file__).resolve().parents[1])
p.add_argument('--output',type=pathlib.Path,required=True)
p.add_argument('--scenario',choices=['untouched','skip','controls','tutorial'],default='untouched')
p.add_argument('--until',choices=['spawned','seated','paid'],default='paid')
a=p.parse_args()
out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
project=out/'project'
shutil.copytree(a.project,project,ignore=shutil.ignore_patterns('.git','.godot','qa-project','__pycache__'))
shutil.copy2(pathlib.Path(__file__).with_name('observe_fresh_arrivals.gd'),project/'tests/observe_fresh_arrivals.gd')
env=os.environ.copy()
for key in ['HOME','APPDATA','LOCALAPPDATA','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
 folder=out/key.lower();folder.mkdir();env[key]=str(folder)
env['LL_ARRIVAL_SCENARIO']=a.scenario;env['LL_ARRIVAL_UNTIL']=a.until;env['LL_ARRIVAL_OUTPUT']=str(out/'result.json')
godot=env.get('GODOT_BIN','godot')
with open('/workspace/shared/.little-leaf-engine.lock','w') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 for stage,args in [('import',['--editor','--import','--quit']),('observe',['--script','res://tests/observe_fresh_arrivals.gd'])]:
  with open(out/(stage+'.log'),'w') as log:
   proc=subprocess.run([godot,'--headless','--path',str(project),*args],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=220)
  text=(out/(stage+'.log')).read_text()
  if proc.returncode or 'SCRIPT ERROR:' in text:
   print(text);raise SystemExit(proc.returncode or 1)
r=json.loads((out/'result.json').read_text());r['engine_error_lines']=[line for line in (out/'observe.log').read_text().splitlines() if 'ERROR:' in line];(out/'result.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'path':str(out),'scenario':a.scenario,'checks':r['checks'],'failures':r['failures'],'events':r['events']},indent=2))
