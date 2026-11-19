"""Only the fixed #393 attempt 1 data artifacts. Never executes an artifact script."""
import hashlib
import json
import os
from pathlib import Path
import sys
from urllib.request import Request, urlopen

REPO='yiyousiow000814/little-leaf'
RUN=44490633657
BASIS='8f38cd8b46345603d41f4fe2199904e26dad4a52'
HEAD='94f694d94f64364ff8f05a2385c3bf108f539cbe'
OLD='9110ebd9a2d6cbf4d2af303be0e244e660c0f7fc'
TNEW='f0f25cd657a5cad740f4177a3908e7b81b426d91'
TOLD='090eba5053b0f891d78d6f0c60b0317325f4f354'
ARTS={
  14512263968:('pinned-chromium','3809c88b351d388fcf651c78f723d3cbf3e1f33c1d11a36117ac821e21ca3a09','web / preflight'),
  14513166331:('ci-inputs','0fa7a1491fd59545c5398a801e241c5be60e6c593bbc597b5536bcb415bb3092','web / build'),
  14512109708:('historical','65918d59fbf18e2145e7ec09dbce79d5898eac234795a05e36c3f517eba9f95a','web / historical'),
  14512418475:('browser-compatibility-already_open_old','6ad8ae2caf2d60e4e0b179e4e5322f046db4d7127d82f99bbf4ff36f0c12b0ce','web / compatibility (compatibility, already_open_old)'),
}

def req(path):
    headers={'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'}
    if token:=os.environ.get('GH_TOKEN'):headers['Authorization']='Bearer '+token
    with urlopen(Request(f'https://api.github.com/repos/{REPO}/actions/{path}',headers=headers),timeout=15) as f:
        return json.load(f)

def remote():
    run=req(f'runs/{RUN}')
    assert (run['id'],run['path'],run['event'],run['head_sha'])==(RUN,'.github/workflows/ci.yml','pull_request',HEAD)
    assert run['run_attempt']>=1 and any(p['number']==393 and p['base']['ref']=='main' and p['base']['sha']=='8c415d94fdb86e68dd0ce90d3482f9e668e8805d' for p in run['pull_requests'])
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
        assert j['id']=={'web / preflight':135445221417,'web / build':135446499862,'web / historical':135445221602,'web / compatibility (compatibility, already_open_old)':135447043203}[jname]
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
    elif sys.argv[1]=='bundle':
        import importlib.util
        source=Path(sys.argv[3])
        spec=importlib.util.spec_from_file_location('orig',source/'tools/ci/play_provision.py')
        mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
        import stat, subprocess
        bundle=Path(sys.argv[2]);lock=load(mod.LOCK)
        names={Path(v['file']).name:k for k,v in lock.items()}
        assert len(names)==len(lock)
        assert not bundle.is_symlink() and {p.name for p in bundle.iterdir()}==set(names)
        for basename,k in names.items():
            p=bundle/basename;L=lock[k]
            assert stat.S_ISREG(p.lstat().st_mode) and sha(p)==L['sha256']
            for field,accepted in [('Package',{k}),('Version',{L['version']}),('Architecture',{'amd64','all'})]:
                assert subprocess.check_output(['dpkg-deb','-f',str(p),field],text=True).strip() in accepted
        print(f'All {len(names)} exact locked package files independently verified')
    else:
        assert sys.argv[1]=='local'
        local(Path(sys.argv[2]))
