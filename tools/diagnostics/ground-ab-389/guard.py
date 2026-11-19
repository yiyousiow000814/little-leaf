"""Allow only an exact #389 single-child diagnostic push; upload bounded facts."""
import hashlib, json, os, subprocess, sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
COMMIT='1556f2ad1e9985c723f7f3634a3f48535cc411a2'
TREE='f449331e7ae64da7f19fa62b3554062381cb887c'
REPO='yiyousiow000814/little-leaf'
REF='refs/heads/qa/ground-ab-389'
WORKFLOW='.github/workflows/ground-ab-389.yml'
KIT='tools/diagnostics/ground-ab-389/'
def git(repo,*args):
 return subprocess.check_output(['git','-C',str(repo),*args],text=True).strip()
def need(value):
 if not value: raise ValueError('diagnostic gate failed')
def event(repo,ev,env):
 head=env['GITHUB_SHA']
 need(env['GITHUB_REPOSITORY']==REPO and env['GITHUB_REF']==REF and env['GITHUB_RUN_ATTEMPT']=='1' and env['GITHUB_ACTOR']==REPO.split('/')[0])
 need(env['GITHUB_EVENT_NAME']=='push' and ev['ref']==REF and not any(ev.get(k) for k in ('created','deleted','forced')) and ev['after']==head and ev['before']==COMMIT)
 need(git(repo,'rev-list','--parents','-n','1','HEAD').split()==[head,COMMIT])
 allowed={WORKFLOW,*(KIT+n for n in ('background.patch','guard.py','probe.gd','report.py','run.sh'))}
 need(set(git(repo,'diff','--name-only','HEAD^','HEAD').splitlines())==allowed)
def failure(path,reason):
 need(reason in {'source_binding','source_stage','headless_import','native_tool','display','probe_rgba_or_capture','report_rejected'})
 path.parent.mkdir(parents=True,exist_ok=True)
 path.write_text(json.dumps({'schema':'ll-ground-ab-389-v1','product':COMMIT,'status':'not_qualified','stage':reason})+'\n')
if __name__=='__main__':
 mode=sys.argv[1]
 if mode=='event':event(Path(sys.argv[2]),json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text()),os.environ)
 elif mode=='fail':failure(Path(sys.argv[2]),sys.argv[3])
 else:raise ValueError('unknown gate')
