"""Exact one-shot product provenance; no host profile or player data."""
import argparse, hashlib, json, os, subprocess
from pathlib import Path

D = Path(__file__).resolve().parent
COMMIT = 'ce1435afb2329a6c1d2d77a8a19923dfd96bd205'
TREE = '03632a0d56e4294f5664859656c8809541766d1b'
FIXTURE = 'ed6fcfc1e4a3396389eff71b09f60740d099de9c046eb0e37eabe900e8c1cf4f'
STAGER = '432dff660b88ea8fef54fd90914a38b2e28ea1d566084b864b1815e5d68ea8b3'
ENGINE = 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
REPO = 'yiyousiow000814/little-leaf'
REF = 'refs/heads/qa/current-profile-397'
WF = '.github/workflows/current-profile-397.yml'
KIT = 'tools/diagnostics/current-profile-397/'
STATUS = {'source_binding','fixture_or_sampler_hash','marker_binding','native_tool_install','native_tool_hash',
          'headless_editor_import','display_startup','natural_cooking_not_reached','candidate_session','candidate_timeout',
          'missing_measurement','capped_window_invalid','unexpected_renderer','uncapped_window_invalid','summary_generation',
          'display_or_output_unavailable','initial_cap_not_60','probe_output_failed','engine_script_error','marker_fault'}
def need(ok):
    if not ok:
        raise ValueError('profile source or status binding failed')
def sha(p):
    with Path(p).open('rb') as f:
        return hashlib.file_digest(f,'sha256').hexdigest()
def git(repo,*args):
    return subprocess.check_output(['git','-C',str(repo),*args]).decode().strip()
def data(): return json.loads((D/'input.json').read_text())
def immutable():
    b=data()
    need((b['commit'],b['tree'])==(COMMIT,TREE))
    need(sha(D/'fixture.json')==FIXTURE and sha(D/'stage.py')==STAGER)
    files=json.loads((D/'kit-manifest.json').read_text())
    need(isinstance(files,dict) and len(files)>=6)
    need(all(not f.startswith(('/','.')) and '..' not in f.split('/') and sha(D/f)==v for f,v in files.items()))
    actual={f.relative_to(D).as_posix() for f in D.rglob('*') if f.is_file()}
    need(actual==set(files)|{'kit-manifest.json','guard.py'})
    return files
def event(repo,ev,env):
    files=immutable();head=env['GITHUB_SHA']
    need(env['GITHUB_REPOSITORY']==REPO and env['GITHUB_REF']==REF and env['GITHUB_RUN_ATTEMPT']=='1' and env['GITHUB_ACTOR']==REPO.split('/')[0])
    need(env['GITHUB_EVENT_NAME']=='push' and ev['ref']==REF and all(ev.get(k) is False for k in ('created','deleted','forced')) and ev['after']==head and ev['before']==COMMIT)
    need(git(repo,'rev-list','--parents','-n','1','HEAD').split()==[head,COMMIT])
    need(git(repo,'rev-parse','HEAD^'+'^{tree}')==TREE)
    paths=git(repo,'diff','--name-only','-z','HEAD^','HEAD').split('\0')
    need(set(p for p in paths if p)=={WF}|{KIT+f for f in set(files)|{'kit-manifest.json','guard.py'}})
def staged(stage):
    immutable();b=data();s=json.loads((stage/'diagnostic-source.json').read_text())
    need(s['source']==dict(commit=COMMIT,tree=TREE,archive_sha256=b['archive_sha256'],allowed_project_paths=['game']) and s['staged_project']=='game')
    need(s['diagnostic_patch']['probe_sha256']==sha(D/'probe.gd')==sha(stage/'game/ll_native_draw_probe.gd') and s['diagnostic_patch']['project_after_sha256']==sha(stage/'game/project.godot'))
    fixed=json.loads((D/'markers-binding.json').read_text())
    need((fixed['source_sha'],fixed['source_tree'])==(COMMIT,TREE))
    after=fixed['diagnostic_sha256']
    for k,h in b['reviewed_game_files'].items():
        need(k.startswith('game/') and '..' not in k.split('/') and sha(stage/k)==after.get(k[5:],h))
    for k,h in after.items():
        if k!='project.godot':
            need(sha(stage/'game'/k)==h)
    cfg=(stage/'game/project.godot').read_bytes()
    sampler=b'LLNativeDrawProbe="*res://ll_native_draw_probe.gd"'
    helper=b'LL397Scopes="*res://ll397_scopes.gd"'
    need(cfg.count(helper)==cfg.count(sampler)==1 and helper+b'\n'+sampler in cfg)
    need(hashlib.sha256(cfg.replace(b'\n'+sampler,b'')).hexdigest()==after['project.godot'])
    need(s['diagnostic_patch']['project_before_sha256']==fixed['base_sha256']['project.godot'])
    lines=(stage/'game/project.godot').read_text().splitlines()
    need(lines.count('run/max_fps=60')==1 and lines.count('renderer/rendering_method="gl_compatibility"')==1)
def failure(out,code):
    need(code in STATUS)
    out.parent.mkdir(exist_ok=True,parents=True)
    out.write_text(json.dumps(dict(schema='ll-current-native-profile-summary-v1',product=COMMIT,status='not_qualified',
                                stage=code,measurements_published=False,historical_comparison=False))+'\n')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['event','staged','fail']);p.add_argument('path',type=Path);p.add_argument('code',nargs='?');a=p.parse_args()
    if a.mode=='event':event(a.path,json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text()),os.environ)
    elif a.mode=='staged':staged(a.path)
    else:failure(a.path,a.code)
