"""Only the fixed #377 attempt 1 data artifacts. Never executes an artifact script."""
import hashlib
import json
import os
from pathlib import Path
import sys
from urllib.request import Request, urlopen

REPO='yiyousiow000814/little-leaf'
RUN=44474276265
BASIS='d484fb22623039c7078a9cce1c06bc3084c9f146'
HEAD='f586b7905c3a50bacd4ee82964955d67d6888699'
OLD='9110ebd9a2d6cbf4d2af303be0e244e660c0f7fc'
TNEW='b7efe2a2f8558860f8a9750cdecdf2eb49f7e0e6'
TOLD='090eba5053b0f891d78d6f0c60b0317325f4f354'
ARTS={
  14505643540:('ci-inputs','bfe940744266b9c9c23c7e3920a05c7c255021514cea3d38d0ff80e2b17ce4f9','web / build'),
  14505502441:('historical','97e1822e9e948b786e763a23207a27af29ad75dac48827fbc701b7c76cdb51d5','web / historical'),
  14505827632:('browser-compatibility-already_open_old','a3b0f8f9d017abf7963f8e651adb6e222fb0204d0b30360750d0e44c0c28cd63','web / compatibility (compatibility, already_open_old)'),
}

def req(path):
    headers={'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'}
    if token:=os.environ.get('GH_TOKEN'):headers['Authorization']='Bearer '+token
    with urlopen(Request(f'https://api.github.com/repos/{REPO}/actions/{path}',headers=headers),timeout=15) as f:
        return json.load(f)

def remote():
    run=req(f'runs/{RUN}')
    assert (run['id'],run['path'],run['event'],run['head_sha'])==(RUN,'.github/workflows/ci.yml','pull_request',HEAD)
    assert run['run_attempt']>=1 and any(p['number']==377 for p in run['pull_requests'])
    attempt=req(f'runs/{RUN}/attempts/1')
    assert (attempt['id'],attempt['run_attempt'],attempt['head_sha'])==(RUN,1,HEAD)
    jobs=req(f'runs/{RUN}/attempts/1/jobs?per_page=100')['jobs']
    summary={}
    for aid,(suffix,digest,jname) in ARTS.items():
        art=req(f'artifacts/{aid}')
        assert not art['expired'] and art['id']==aid and art['size_in_bytes']>0
        assert art['name']==f'little-leaf-{suffix}-{BASIS}-1'
        assert art['digest']=='sha256:'+digest and art['workflow_run']['id']==RUN and art['workflow_run']['head_sha']==HEAD
        j,=[j for j in jobs if j['name']==jname]
        assert j['conclusion']==('failure' if 'already_open_old' in suffix else 'success')
        if 'already_open_old' in suffix:assert j['id']==135392709048
        summary[str(aid)]={'name':art['name'],'sha256':digest,'producer_job':j['id'],'result':j['conclusion']}
    print(json.dumps({'run_id':RUN,'attempt':1,'head_sha':HEAD,'merge_sha':BASIS,'archives':summary},indent=2))

def load(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def local(root):
    current=root/'case-b-current'
    old=root/'case-b-historical'
    evidence=root/'case-b-preflight/web-build/evidence'
    p=evidence/'wall-preflight/preflight.json'; b=load(p)
    failed=load(evidence/'wall-browser/already_open_old/wall-compatibility-browser.json')
    assert (b['status'],b['workflow_run'],b['workflow_attempt'],b['coordinator_source'])==('passed',str(RUN),'1',BASIS)
    assert (b['old_commit'],b['new_commit'],b['old_tree'],b['new_tree'])==(OLD,BASIS,TOLD,TNEW)
    assert failed['status']=='failed' and failed['synthetic_only'] and not failed['browser_verified']
    assert failed['new_ui_edit']['revision_before']==3 and failed['new_ui_edit']['revision_after']==5
    f=failed['inputs']
    assert f['new_commit']==BASIS and f['old_commit']==OLD and f['preflight_sha256']==sha(p)
    assert f['fixture_sha256']==b['fixture_sha256']
    for label,commit,tree,export in [('old',OLD,TOLD,old/'old-web-build/web'),('new',BASIS,TNEW,current/'web-build/web')]:
        m=export/'release-manifest.json'; obj=load(m)
        assert obj['source_commit']==commit and sha(m)==b['export_manifest_sha256'][label]
        if 'source_tree' in obj: assert obj['source_tree']==tree
        assert obj['production_sha256']==b['production_sha256'][label]
        assert obj['files']==f['export_files'][label]
        assert obj['toolchain_receipt']==b['toolchain_receipt']
        lay_dir=export.parent/'evidence/wall-layout'
        sibling=load(lay_dir/'preflight.json')
        assert (sibling['status'],sibling['workflow_run'],sibling['workflow_attempt'],sibling['coordinator_source'])==('passed',str(RUN),'1',BASIS)
        assert sibling['production_sha256'][label]==b['production_sha256'][label]
        assert sibling['export_manifest_sha256'][label]==b['export_manifest_sha256'][label]
        assert sibling['layouts'][label]==b['layouts'][label]
        assert sha(p.parent/f'{label}-layout.json')==sha(lay_dir/f'{label}-layout.json')==b['layouts'][label]['sha256']
        assert sha(p.parent/f'{label}-layout.log')==sha(lay_dir/f'{label}-layout.log')==b['layouts'][label]['log_sha256']
    summ=current/'engine-evidence/summary.json'; aggregate=load(summ)
    assert aggregate['status']=='passed' and aggregate['source_commit']==BASIS
    assert sha(summ)==load(current/'web-build/web/release-manifest.json')['test_report_sha256']
    old_summ=old/'old-engine-evidence/summary.json'; old_aggregate=load(old_summ)
    assert old_aggregate['status']=='passed' and old_aggregate['source_commit']==OLD
    assert sha(old_summ)==load(old/'old-web-build/web/release-manifest.json')['test_report_sha256']
    print(json.dumps({'current':BASIS,'historical':OLD,'preflight_sha256':sha(p),'engine_summary_sha256':sha(summ)},indent=2))
if __name__=='__main__':
    if sys.argv[1]=='remote':remote()
    else:
        assert sys.argv[1]=='local'
        local(Path(sys.argv[2]))
