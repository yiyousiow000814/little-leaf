"""One finite static #397 diagnostic only; no current-game launches."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess
D=Path(__file__).resolve().parent
COMMIT='ce1435afb2329a6c1d2d77a8a19923dfd96bd205'
TREE='03632a0d56e4294f5664859656c8809541766d1b'
REPO='yiyousiow000814/little-leaf'
REF='refs/heads/qa/backdrop-cache-397'
KIT='tools/diagnostics/backdrop-cache-397/'
WF='.github/workflows/backdrop-cache-397.yml'
CAUSES={'source_binding','source_stage','official_tool','official_engine_identity','static_import','x11_prereq','setup_or_render_inconclusive','bounded_report_rejected','gate_env','geometry','setup','pixel_parity','layer_crop','counter_confound','arm_unstable','pixel_or_invalidation','alpha_opaque','producer_rgba','cached_ground_rgba','composite_rgba','stale_camera','shifted_cache_rgba','duplicate_ground','incompatible_state','cache_counter','ground_alpha','fallback_parity','shifted_parity','restored_parity'}
def need(b):
    if not b:raise ValueError('static diagnostic binding failed')
def sha(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def git(repo,*a):return subprocess.check_output(['git','-C',str(repo),*a]).decode().strip()
def immutable():
    m=json.loads((D/'kit-manifest.json').read_text())
    need(all('/' not in k and not k.startswith('.') and sha(D/k)==v for k,v in m.items()))
    names=set(m)|{'kit-manifest.json','guard.py'}
    need({p.relative_to(D).as_posix() for p in D.rglob('*') if p.is_file()}==names)
    return names
def event(repo,e,env):
    names=immutable();head=env['GITHUB_SHA']
    need(env['GITHUB_EVENT_NAME']=='push' and env['GITHUB_REF']==REF and env['GITHUB_REPOSITORY']==REPO and env['GITHUB_ACTOR']==REPO.split('/')[0] and env['GITHUB_RUN_ATTEMPT']=='1')
    need(e['ref']==REF and all(e.get(k) is False for k in ('created','deleted','forced')) and (e['before'],e['after'])==(COMMIT,head))
    need(git(repo,'rev-list','--parents','-n','1','HEAD').split()==[head,COMMIT] and git(repo,'rev-parse','HEAD^^{tree}')==TREE)
    paths={s for s in git(repo,'diff','--name-only','-z','HEAD^','HEAD').split('\0') if s}
    need(paths=={WF}|{KIT+f for f in names})
def fail(out,why):
    need(why in CAUSES)
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(dict(schema='ll-backdrop-cache-397-v1',status='not_qualified',stage=why,product=COMMIT,historical_comparison=False,measurements_published=False))+'\n')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['event','fail','fixture-fail']);p.add_argument('path',type=Path);p.add_argument('why',nargs='?')
    a=p.parse_args()
    if a.mode=='event':event(a.path,json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text()),os.environ)
    elif a.mode=='fixture-fail':
        try:
            private=Path(a.why)
            need(private.stat().st_size<4096)
            state=json.loads(private.read_text()); code=state.get('stage_code',state.get('stage'))
            need(code in {'gate_env','geometry','setup','pixel_parity','layer_crop','counter_confound','arm_unstable','pixel_or_invalidation','alpha_opaque','producer_rgba','cached_ground_rgba','composite_rgba','stale_camera','shifted_cache_rgba','duplicate_ground','incompatible_state','cache_counter','ground_alpha','fallback_parity','shifted_parity','restored_parity'})
        except (ValueError,OSError,AttributeError,TypeError):code='setup_or_render_inconclusive'
        fail(a.path,code)
    else:fail(a.path,a.why)
