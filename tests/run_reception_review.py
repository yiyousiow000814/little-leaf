"""Small native reception-only runner. Never opens an existing player profile."""
import argparse,hashlib,json,os,re,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from project_layout import stage_project
SUITES={'test_reception_private_contract':'RECEPTION_PRIVATE_CONTRACT_RESULT',
        'test_restaurant_reception':'RESTAURANT_RECEPTION_RESULT',
        'test_reception_service':'RECEPTION_SERVICE_RESULT',
        'test_reception_clearance':'RECEPTION_CLEARANCE_RESULT',
        'test_reception_fairness':'RECEPTION_FAIRNESS_RESULT',
        'test_reception_retry':'RECEPTION_RETRY_RESULT',
        'test_reception_scope':'RECEPTION_SCOPE_RESULT'}
def execute():
 p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--output',type=Path,required=True)
 p.add_argument('--only',nargs='+',choices=list(SUITES),default=list(SUITES));p.add_argument('--native-service',action='store_true');args=p.parse_args()
 if args.native_service and args.only!=['test_reception_service']:p.error('--native-service requires --only test_reception_service')
 out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
 project=out/'project';stage_project(ROOT,project,tests=True)
 config=project/'project.godot';text=config.read_text(encoding='utf-8')
 assert 'config/name="Little Leaf Cafe"' in text
 config.write_text(text.replace('config/name="Little Leaf Cafe"','config/name="Little Leaf Reception Review"',1),encoding='utf-8')
 records=[]
 hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for directory in ['game/scripts','tests'] for p in (ROOT/directory).rglob('*') if p.is_file() and p.suffix in ['.gd','.py']}
 def env_for(name):
  scope=out/('saveguard-'+name)
  if name=='test_reception_scope':scope=scope/'Little Leaf Cafe/disposable'
  env=os.environ.copy()
  for key in ['HOME','APPDATA','LOCALAPPDATA','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
   directory=scope/('windows-data' if os.name=='nt' else key.lower());directory.mkdir(parents=True,exist_ok=True);env[key]=str(directory)
  env['LL_RECEPTION_REVIEW_ROOT']=str(scope)
  user=Path(env['APPDATA' if os.name=='nt' else 'XDG_DATA_HOME'])/('Godot' if os.name=='nt' else 'godot')/'app_userdata/Little Leaf Reception Review'
  user.mkdir(parents=True,exist_ok=True)
  sibling=scope/'outside';sibling.mkdir(exist_ok=True)
  if os.name=='nt':
   # Literal native junction in this generated tree only; no credentials/data.
   script="New-Item -ItemType Junction -Path '"+str(user/'escape').replace("'","''")+"' -Target '"+str(sibling).replace("'","''")+"' | Out-Null"
   subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-WindowStyle','Hidden','-Command',script],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  else:(user/'escape').symlink_to(sibling,target_is_directory=True)
  if args.native_service and name=='test_reception_service':
   captures=out/'frames';captures.mkdir(exist_ok=True);env['LL_RECEPTION_CAPTURE']=str(captures)
  return env
 def run(name,extra,env,marker=None):
  start=time.monotonic();cmd=[args.godot,*([] if args.native_service and name=='test_reception_service' else ['--headless']),'--audio-driver','Dummy','--path',str(project),*extra]
  c=subprocess.run(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
  log=c.stdout.decode('utf-8',errors='replace');(out/(name+'.log')).write_text(log,encoding='utf-8')
  payloads=[json.loads(l[len(marker)+1:]) for l in log.splitlines() if marker and l.startswith(marker+' ')]
  row={'name':name,'exit_code':c.returncode,'seconds':round(time.monotonic()-start,2),'payloads':payloads,'script_errors':[l for l in log.splitlines() if 'SCRIPT ERROR' in l or 'Parse Error' in l]}
  records.append(row);(out/'receipt.json').write_text(json.dumps({'source_hashes':hashes,'records':records},indent=2),encoding='utf-8')
  print(json.dumps(row),flush=True)
  if c.returncode or row['script_errors'] or (marker and (len(payloads)!=1 or payloads[0]['failures'])):raise RuntimeError(name+' failed; retained exact log')
 run('import',['--editor','--import','--quit'],env_for('import'))
 for suite in args.only:
  run(suite,['--script','res://tests/'+suite+'.gd','--','--visual-qa','--fresh-review','--reception-candidate','--reception-persistence-candidate','--skip-intro','--skip-tutorial'],env_for(suite),SUITES[suite])
 assert all(hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()==sha for rel,sha in hashes.items())
 print(json.dumps({'checks':sum(p['checks'] for r in records for p in r['payloads']),'source_unchanged':True,'profile_root':str(out)}))
def main():
 # One owned engine lane; refuse rather than overlap a hardware measurement.
 lock_path=Path(os.environ.get('LL_ENGINE_LOCK',ROOT.parent/'.little-leaf-engine.lock'))
 with lock_path.open('a+b') as lock:
  lock.seek(0);lock.write(b'\0');lock.flush();lock.seek(0)
  if os.name=='nt':
   import msvcrt
   msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
  else:
   import fcntl
   fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
  execute()
if __name__=='__main__':main()
