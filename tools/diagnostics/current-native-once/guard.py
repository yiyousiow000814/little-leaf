"""Current-only provenance and allowlisted operational status. No host records."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess
D=Path(__file__).resolve().parent
COMMIT='1556f2ad1e9985c723f7f3634a3f48535cc411a2'
TREE='f449331e7ae64da7f19fa62b3554062381cb887c'
ARCHIVE='959cb8b47173be82ea921d96144fb6cd91870adccac1191141ddd41ac1ed8229'
ENGINE='f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
FIXTURE='ed6fcfc1e4a3396389eff71b09f60740d099de9c046eb0e37eabe900e8c1cf4f'
STAGER='3536c465bbbe5b9694105580ba9945c9dd51f493699990a702c4d0375856b627'
REPO='yiyousiow000814/little-leaf'
REF='refs/heads/qa/current-native-389-once'
WF='.github/workflows/current-native-389-once.yml'
KIT='tools/diagnostics/current-native-once/'
STATUSES={'source_binding','fixture_or_sampler_hash','native_tool_install','native_tool_hash','headless_editor_import','display_startup','natural_cooking_not_reached','candidate_session','candidate_timeout','missing_measurement','capped_window_invalid','unexpected_renderer','uncapped_window_invalid','summary_generation','display_or_output_unavailable','initial_cap_not_60','probe_output_failed','engine_script_error'}
def need(ok): 
 if not ok: raise ValueError('source or input gate failed')
def sha(p):
 with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def git(repo,*args):return subprocess.check_output(['git','-C',str(repo),*args]).decode().strip()
def data():return json.loads((D/'input.json').read_text())
def immutable():
 b=data();need((b['commit'],b['tree'],b['archive_sha256'])==(COMMIT,TREE,ARCHIVE));need(sha(D/'fixture.json')==FIXTURE and sha(D/'stage.py')==STAGER)
 expected=json.loads((D/'probe-sha256.json').read_text());need(expected=={'probe.gd':sha(D/'probe.gd')})
def event(repo,ev,env):
 head=env['GITHUB_SHA']
 need(env['GITHUB_REPOSITORY']==REPO and env['GITHUB_REF']==REF and env['GITHUB_RUN_ATTEMPT']=='1' and env['GITHUB_ACTOR']==REPO.split('/')[0])
 need(env['GITHUB_EVENT_NAME']=='push' and ev['ref']==REF and not ev.get('created') and not ev.get('deleted') and not ev.get('forced') and ev['after']==head and ev['before']==COMMIT)
 need(git(repo,'rev-list','--parents','-n','1','HEAD').split()==[head,COMMIT])
 paths=git(repo,'diff','--name-only','HEAD^','HEAD').splitlines();need(WF in paths and KIT+'input.json' in paths and all(p==WF or p.startswith(KIT) for p in paths));immutable()
def staged(stage):
 immutable();b=data();s=json.loads((stage/'diagnostic-source.json').read_text())
 need(s['source']==dict(commit=COMMIT,tree=TREE,archive_sha256=ARCHIVE,allowed_project_paths=['game']) and s['staged_project']=='game')
 need(s['diagnostic_patch']['probe_sha256']==sha(D/'probe.gd')==sha(stage/'game/ll_native_draw_probe.gd') and s['diagnostic_patch']['project_after_sha256']==sha(stage/'game/project.godot'))
 for key,h in b['reviewed_game_files'].items():
  need(key.startswith('game/') and '..' not in key.split('/') and sha(stage/key)==h)
 cfg=(stage/'game/project.godot').read_text().splitlines();need(cfg.count('run/max_fps=60')==1 and cfg.count('renderer/rendering_method="gl_compatibility"')==1)
def failure(out,code):
 need(code in STATUSES)
 out.parent.mkdir(exist_ok=True,parents=True);out.write_text(json.dumps(dict(schema='ll-current-native-summary-v1',product=COMMIT,status='not_qualified',stage=code,measurements_published=False,historical_comparison=False))+'\n')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('mode',choices=['event','staged','fail']);p.add_argument('path',type=Path);p.add_argument('code',nargs='?');a=p.parse_args()
 if a.mode=='event':event(a.path,json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text()),os.environ)
 elif a.mode=='staged':staged(a.path)
 else:failure(a.path,a.code)
