"""Local root binder and strictly verifying hosted reader; never launches an engine."""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess, sys
import audit
D=Path(__file__).resolve().parent
ROOT_PATH='tools/diagnostics/frozen-native-once'
WORKFLOW='.github/workflows/frozen-native-once.yml'
HEX=lambda s,n: isinstance(s,str) and re.fullmatch('[0-9a-f]{'+str(n)+'}',s)
def check(v,m):
 if not v:raise ValueError(m)
def git(repo,*args):return subprocess.check_output(['git','-C',str(repo),*args]).decode().strip()
def product_path(s):
 return isinstance(s,str) and s.startswith('game/') and all(re.fullmatch(r'[a-zA-Z0-9._-]+',p) and p not in ['.','..'] for p in s.split('/'))
def filehash(repo,rev,path):
 with subprocess.Popen(['git','-C',str(repo),'show',rev+':'+path],stdout=subprocess.PIPE) as p:
  with p.stdout as output:h=hashlib.file_digest(output,'sha256').hexdigest()
  check(p.wait()==0,'missing reviewed file');return h
def bind(data):
 check(isinstance(data,dict) and data.get('status')=='ROOT_REVIEWED_FINAL','unbound, do not sample')
 for k,n in [('commit',40),('tree',40),('archive_sha256',64),('integration_base',40)]:
  check(HEX(data.get(k),n),'malformed '+k)
 check(data['frozen_zip_sha256']==audit.ZIP and data['frozen_seal_sha256']==audit.SEAL,'original cannot be replaced')
 check(data['commit'] not in (data['integration_base'],audit.BASE,'2e3c7f6be9a633fff8e05450033ccdb3a2959c5f'),'not a final candidate')
 files=data.get('reviewed_game_files');check(isinstance(files,dict) and len(files)>0 and all(product_path(p) and HEX(v,64) for p,v in files.items()),'missing exact game postimages')
 check(product_path(data.get('projection_file')) and data['projection_file'] in files,'projection not explicitly reviewed')
 return data
def do_bind(a):
 check(os.environ.get('GITHUB_ACTIONS')!='true','local root binder only; Actions may not bind a product')
 dest=D/'binding.json';check(json.loads(dest.read_text()).get('status')=='UNBOUND','already bound; refuse overwriting')
 for n in (a.commit,a.tree,a.integration_base):check(HEX(n,40),'need full git IDs')
 check(git(a.repo,'rev-parse','HEAD')==a.commit and git(a.repo,'rev-parse','HEAD^{tree}')==a.tree,'use exact reviewed product checkout')
 subprocess.run(['git','-C',str(a.repo),'merge-base','--is-ancestor',a.integration_base,a.commit],check=True)
 files={}
 for arg in a.review:
  k,sep,v=arg.rpartition('=');check(sep and product_path(k) and HEX(v,64) and k not in files,'need unique game/path=SHA256')
  check(filehash(a.repo,a.commit,k)==v,'wrong final postimage: '+k);files[k]=v
 check(a.projection_file in files,'review projection postimage')
 check(git(a.repo,'diff','--name-only',a.integration_base,a.commit,'--',a.projection_file)==a.projection_file,'no final projection diff against reviewed integration base')
 with subprocess.Popen(['git','-C',str(a.repo),'archive','--format=tar',a.commit,'game'],stdout=subprocess.PIPE) as p:
  with p.stdout as output:digest=hashlib.file_digest(output,'sha256').hexdigest()
  check(p.wait()==0,'game archive failed')
 data=bind(dict(status='ROOT_REVIEWED_FINAL',commit=a.commit,tree=a.tree,archive_sha256=digest,integration_base=a.integration_base,reviewed_game_files=files,projection_file=a.projection_file,frozen_zip_sha256=audit.ZIP,frozen_seal_sha256=audit.SEAL))
 dest.write_text(json.dumps(data,indent=2)+'\n');print(json.dumps(data))
def do_event(a):
 d=bind(json.loads((D/'binding.json').read_text()));event=json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text());pr=event['pull_request'];repo='yiyousiow000814/little-leaf'
 check(os.environ['GITHUB_REPOSITORY']==repo and os.environ['GITHUB_EVENT_NAME']=='pull_request' and event['action']=='opened' and os.environ['GITHUB_RUN_ATTEMPT']=='1','only first PR-opened attempt')
 check(pr['head']['repo']['full_name']==pr['base']['repo']['full_name']==repo and pr['head']['ref']=='qa/frozen-native-integrated-once' and pr['base']['ref']=='main' and pr['draft'],'only named same-repo diagnostic draft PR')
 check(pr['user']['login']==repo.split('/')[0],'only repository-owner-authored diagnostic')
 head=git(a.repo,'rev-parse','HEAD');check(head==pr['head']['sha'] and git(a.repo,'rev-list','--parents','-n','1','HEAD').split()==[head,d['commit']],'diagnostic must be one direct commit on reviewed product')
 delta=git(a.repo,'diff','--name-only','HEAD^','HEAD').splitlines()
 check(WORKFLOW in delta and ROOT_PATH+'/binding.json' in delta and all(p==WORKFLOW or p.startswith(ROOT_PATH+'/') for p in delta),'unexpected diagnostic paths')
 with open(os.environ['GITHUB_OUTPUT'],'a') as stream:stream.write('commit='+d['commit']+'\ntree='+d['tree']+'\n')
def do_staged(a):
 d=bind(json.loads((D/'binding.json').read_text()));receipt=json.loads((a.stage/'diagnostic-source.json').read_text())
 check(receipt['source']=={k:d[k] for k in ('commit','tree','archive_sha256')}|{'allowed_project_paths':['game']} and receipt['staged_project']=='game','stage does not match root binding')
 check(receipt['diagnostic_patch']['probe_sha256']==audit.HELPERS['native_draw_probe.gd'],'stage sampler substituted')
 with (a.stage/'game/ll_native_draw_probe.gd').open('rb') as stream:check(hashlib.file_digest(stream,'sha256').hexdigest()==audit.HELPERS['native_draw_probe.gd'],'staged sampler bytes differ')
 with (a.stage/'game/project.godot').open('rb') as stream:check(hashlib.file_digest(stream,'sha256').hexdigest()==receipt['diagnostic_patch']['project_after_sha256'],'staged config changed after binding')
 cfg=(a.stage/'game/project.godot').read_text()
 # A candidate with a different configured cap/renderer must not spend the one sample.
 for key,val in [('run/max_fps','60'),('renderer/rendering_method','"gl_compatibility"')]:
  check(re.findall('^'+re.escape(key)+r'=(.*)$',cfg,re.M)==[val],'configured native policy differs: '+key)
 for f,h in d['reviewed_game_files'].items():
  check(filehash(a.repo,d['commit'],f)==h,'committed postimage differed '+f)
  if f=='game/project.godot':check(receipt['diagnostic_patch']['project_before_sha256']==h,'pre-overlay cfg mismatch')
  else:
   with (a.stage/f).open('rb') as stream:check(hashlib.file_digest(stream,'sha256').hexdigest()==h,'staged postimage differed '+f)
def do_preflight(a):
 seal,_,_=audit.archived(D/'frozen.zip',D/'upstream')
 check(a.host.read_text().strip()==seal['fingerprint']['runtime-envelope.txt'],'HOST_INCOMPATIBLE: no candidate sample')
 if a.graphics is not None or a.graphics_log is not None:
  check(a.graphics is not None and a.graphics_log is not None,'complete graphics preflight required');audit.fingerprint(seal,json.loads(a.graphics.read_text()),pre=True)
  check(audit.audio_display(a.graphics_log.read_text()),'GRAPHICS_OR_AUDIO_INCOMPATIBLE: no candidate sample')
def main():
 p=argparse.ArgumentParser();sub=p.add_subparsers(required=True)
 b=sub.add_parser('bind');b.set_defaults(fn=do_bind)
 for k in ('repo','commit','tree','integration-base','projection-file'):b.add_argument('--'+k,required=True)
 b.add_argument('--review',action='append',required=True)
 e=sub.add_parser('event');e.add_argument('--repo',type=Path,required=True);e.set_defaults(fn=do_event)
 s=sub.add_parser('stage');s.add_argument('--repo',type=Path,required=True);s.add_argument('--stage',type=Path,required=True);s.set_defaults(fn=do_staged)
 h=sub.add_parser('envelope');h.add_argument('--host',type=Path,required=True);h.add_argument('--graphics',type=Path);h.add_argument('--graphics-log',type=Path);h.set_defaults(fn=do_preflight)
 a=p.parse_args();a.fn(a)
if __name__=='__main__':main()
