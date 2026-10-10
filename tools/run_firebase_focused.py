"""Run fixed focused gates and record successful same-run command evidence."""
import argparse,json,os,subprocess,sys
from pathlib import Path
from build_web import ROOT,sha256
COMMANDS={'adapter.log':['node','tests/firebase_storage.js'],
 'delayed-network.log':['node','tests/firebase_delayed_network.js'],
 'recovery.log':['node','tests/firebase_recovery.js'],
 'choice.log':['node','tests/firebase_choice.js'],
 'session.log':['node','tests/firebase_session.js'],
 'update-notice.log':['node','tests/update_notice.js'],
 'recovery-presentation.log':['node','tests/firebase_recovery_presentation.js'],
 'recovery-browser.log':['node','tests/firebase_recovery_browser.js'],
 'staging-tests.log':[sys.executable,'tests/test_firebase_build.py'],
 'rules.log':['npm','--prefix','platform/firebase','run','test:rules']}
def run(name,output):
    output.mkdir(parents=True,exist_ok=True)
    receipt=output/(name+'.json');receipt.unlink(missing_ok=True)
    command=COMMANDS[name]
    with (output/name).open('w') as log:
        result=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=120 if name=='recovery-browser.log' else None)
    print((output/name).read_text(),end='')
    if result.returncode:raise SystemExit(result.returncode)
    git=lambda value:subprocess.check_output(['git','-C',str(ROOT),'rev-parse',value],text=True).strip()
    receipt.write_text(json.dumps({'schema_version':1,'status':'passed','exit_code':0,'command':command,
       'source_commit':git('HEAD'),'source_tree':git('HEAD^{tree}'),
       'workflow_run':os.environ.get('GITHUB_RUN_ID',''),'workflow_attempt':os.environ.get('GITHUB_RUN_ATTEMPT',''),
       'log_sha256':sha256(output/name)},indent=2)+'\n')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--gate',choices=COMMANDS,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();run(a.gate,a.output)
