"""Run one matched native profile with save storage confined to its output."""
import argparse,os,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--project',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--godot',type=Path,required=True);a=p.parse_args()
q=a.output.resolve()
if (q.parent/'PAUSE_BENCHMARKS').exists():raise SystemExit('Timing runs paused: shared desktop contention/crash investigation')
q.mkdir(parents=True,exist_ok=False)
env=os.environ.copy()
for key in ['APPDATA','LOCALAPPDATA','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
 env[key]=str(q/'profile')
env['OUTPUT']=str(q)
d=subprocess.run([str(a.godot),'--path',str(a.project.resolve()),'--script','res://qa/performance_profile.gd','--','--visual-qa'],env=env,capture_output=True,timeout=120,creationflags=subprocess.CREATE_NO_WINDOW)
(q/'run.log').write_bytes(d.stdout+d.stderr)
assert d.returncode==0 and (q/'profile.json').is_file(),d.stderr.decode(errors='replace')
print(q)
