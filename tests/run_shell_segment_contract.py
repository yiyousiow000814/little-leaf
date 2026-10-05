"""Run the isolated shell-migration design contract. No assets, editor import or player profile."""
from pathlib import Path
import argparse,fcntl,hashlib,json,os,shutil,subprocess,tempfile,time
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
if any(out.iterdir()):raise SystemExit('Use a new empty output directory')
if hasattr(os,'sched_getaffinity'):os.sched_setaffinity(0,{min(os.sched_getaffinity(0))})
report={'scope':'focused design prototype only','production_code_modified':False,'player_save_used':False,'status':'running'}
with (ROOT.parent/'.little-leaf-engine.lock').open('a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 with tempfile.TemporaryDirectory(prefix='shell-segment-saveguard-') as temp:
  temp=Path(temp);project=temp/'project';project.mkdir()
  (project/'scripts').mkdir()
  legacy_commit='9110ebd9a2d6cbf4d2af303be0e244e660c0f7fc'
  legacy_names=subprocess.check_output(['git','-C',str(ROOT),'ls-tree','-r','--name-only',legacy_commit,'scripts'],text=True).splitlines()
  for name in legacy_names:
   dest=project/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(subprocess.check_output(['git','-C',str(ROOT),'show',legacy_commit+':'+name]))
  report['old_reader_commit']=legacy_commit
  shutil.copytree(ROOT/'qa/prototypes',project/'qa/prototypes')
  (project/'tests').mkdir();shutil.copy2(ROOT/'tests/test_shell_segment_contract.gd',project/'tests/test_shell_segment_contract.gd')
  (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Shell Segment Contract"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
  env=os.environ.copy()
  for name in ['HOME','APPDATA','LOCALAPPDATA','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
   dest=temp/'profiles'/name.lower();dest.mkdir(parents=True);env[name]=str(dest)
  start=time.monotonic();result=subprocess.run([os.environ.get('GODOT_BIN','godot'),'--headless','--audio-driver','Dummy','--path',str(project),'--script','res://tests/test_shell_segment_contract.gd'],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
  text=result.stdout.decode(errors='replace');(out/'contract.log').write_text(text)
  payloads=[json.loads(line.split(' ',1)[1]) for line in text.splitlines() if line.startswith('SHELL_SEGMENT_CONTRACT_RESULT ')]
  report.update(exit_code=result.returncode,seconds=round(time.monotonic()-start,2),payloads=payloads,source_sha256={str(path.relative_to(project)):hashlib.sha256(path.read_bytes()).hexdigest() for path in [*sorted((project/'scripts').glob('*.gd')),project/'qa/prototypes/shell_segment_contract.gd',project/'tests/test_shell_segment_contract.gd']})
  report['status']='passed' if result.returncode==0 and len(payloads)==1 and not payloads[0]['failures'] and 'SCRIPT ERROR:' not in text else 'failed'
  (out/'summary.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:report[k] for k in ['status','exit_code','seconds','payloads']}))
  raise SystemExit(0 if report['status']=='passed' else 1)
