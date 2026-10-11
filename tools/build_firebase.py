"""Stage an unpublished Firebase/itch-entry variant from the exact complete Web gate."""
import argparse, json, shutil, subprocess, re, hashlib, os, base64
from pathlib import Path
from build_web import ROOT, sha256
import artifacts
from project_layout import source_path

def validate_export_inventory(build):
    return artifacts.validate_export_inventory(build / 'web')

def validate_web_gate(build, commit, tree, local_tools=False):
    return artifacts.validate_web_gate(build, commit, tree, local_tools, source_root=ROOT)

def entry_styles():
    """Inline the existing licensed Nunito font; no new external requests."""
    css=source_path(ROOT,'web/little_leaf_entry.css').read_text(encoding='utf-8')
    notice=source_path(ROOT,'assets/fonts/Nunito-OFL.txt').read_text(encoding='utf-8')
    return '/* '+notice+' */\n'+css.replace('$NUNITO_FONT',base64.b64encode(source_path(ROOT,'assets/fonts/Nunito-Variable.ttf').read_bytes()).decode('ascii'))

def auth_verification_html(html, config, origin):
    """Derived diagnostic page: no engine, adapters, vault or preferences scripts."""
    pattern='https://'+re.escape(config['projectId'])+r'--itch-embed-test-[a-z0-9]+\.web\.app'
    if not re.fullmatch(pattern,origin):raise ValueError('Exact own-origin itch preview URL required')
    html='<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Little Leaf · Sign-in check</title><style>'+entry_styles()+'</style></head><body><main class="leaf-entry-page"><section class="leaf-entry-card" aria-labelledby="auth-heading"><p class="leaf-entry-brand">Little Leaf</p><p class="leaf-entry-eyebrow">A little café of your own</p><h1 id="auth-heading" class="leaf-entry-title">Google sign-in check</h1><p class="leaf-entry-intro">Confirm your account in a secure Google popup.</p><div id="auth-verification-slot"></div><p class="leaf-entry-paused">Game and saves remain paused.</p><p class="leaf-entry-note">This check confirms sign-in only. Your existing local progress does not transfer automatically.</p></section></main><p id="status-label" hidden></p></body></html>'
    options={'surface':'trusted-itch-frame','runtimeOrigin':origin,'authVerificationOnly':True}
    injection='<script>window.__littleLeafFirebaseReady=import("./little_leaf_firebase_boot.mjs").then(m=>m.start('+json.dumps(config).replace('<','\\u003c')+','+json.dumps(options)+')).catch(()=>{const label=document.getElementById("status-label"),slot=document.getElementById("auth-verification-slot");if(label)label.textContent="Auth setup did not finish. Game and saves remain paused.";if(slot)slot.textContent="Sign-in setup did not finish. Reload this page to retry.";});</script>'
    if html.count('</body>')!=1:raise ValueError('Diagnostic body contract changed')
    return html.replace('</body>',injection+'</body>')

def stage(build, output, config, trusted_itch_origin=None, auth_verification_only=False):
    validate_export_inventory(build)
    required = {'apiKey','authDomain','projectId','appId'}
    if set(config) != required or any(not isinstance(v,str) or not v or 'REPLACE_' in v for v in config.values()):
        raise ValueError('Supply only approved public Firebase apiKey/authDomain/projectId/appId')
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,28}[a-z0-9]', config['projectId']):
        raise ValueError('Invalid Firebase project ID')
    if config['authDomain'] != config['projectId'] + '.firebaseapp.com':
        raise ValueError('This variant requires its top-level Firebase Hosting authDomain')
    if trusted_itch_origin is not None:
        pattern='https://'+re.escape(config['projectId'])+r'--itch-embed-test-[a-z0-9]+\.web\.app'
        if not re.fullmatch(pattern,trusted_itch_origin):raise ValueError('Exact own-origin itch preview URL required')
    if not isinstance(auth_verification_only,bool) or auth_verification_only and not trusted_itch_origin:
        raise ValueError('Auth verification requires an exact trusted itch preview origin')
    output.mkdir(parents=True,exist_ok=False)
    shutil.copytree(build/'web',output/'public')
    public=output/'public'
    # The inherited HTML hash describes the base Web variant, not this transformed one.
    (public/'release-manifest.json').unlink()
    base_bytes=(build/'web/release-manifest.json').read_bytes();base=json.loads(base_bytes)
    marker={'schema_version':1,'source_commit':base['source_commit'],'source_tree':base['source_tree'],'ci_run_id':base['workflow_run'],'base_web_manifest_sha256':hashlib.sha256(base_bytes).hexdigest(),'version':base['version'],'tag':base.get('tag','')}
    (public/'hosting-release.json').write_text(json.dumps(marker,indent=2)+'\n')
    for name in ['firebase.json','firestore.rules','firestore.indexes.json']:
        shutil.copy2(ROOT/'platform/firebase'/name,output/name)
    for name in ['little_leaf_firebase.js','little_leaf_firebase_session.js','little_leaf_update.js','little_leaf_firebase_boot.mjs']:
        shutil.copy2(ROOT/'platform/web'/name,public/name)
    binding_modules=[] if auth_verification_only else ['little_leaf_google_binding.js','little_leaf_google_binding_ui.js','little_leaf_local_google_entry.js']
    for name in binding_modules:
        shutil.copy2(ROOT/'platform/web'/name,public/name)
    html=(public/'index.html').read_text()
    marker='window.__littleLeafVault.boot()'
    if html.count(marker)!=1: raise ValueError('Web shell boot contract changed')
    html=html.replace(marker,'window.__littleLeafFirebaseReady.then(() => window.__littleLeafVault.boot())')
    preview_options={'surface':'trusted-itch-frame','runtimeOrigin':trusted_itch_origin}
    if auth_verification_only:preview_options['authVerificationOnly']=True
    if not auth_verification_only:preview_options['localBinding']=True
    options=','+json.dumps(preview_options if trusted_itch_origin else {'localBinding':True})
    injection='<script src="little_leaf_update.js"></script><script src="little_leaf_firebase_session.js"></script><script src="little_leaf_firebase.js"></script><script>window.__littleLeafFirebaseReady = import("./little_leaf_firebase_boot.mjs").then(m => m.start('+json.dumps(config).replace('<','\\u003c')+options+'));</script>'
    binding_injection=''.join('<script src="'+name+'"></script>' for name in binding_modules)
    html=html.replace('<script src="index.js"></script>',binding_injection+injection+'<script src="index.js"></script>')
    if injection not in html: raise ValueError('Exported engine script marker changed')
    if auth_verification_only:html=auth_verification_html(html,config,trusted_itch_origin)
    (public/'index.html').write_text(html,encoding='utf-8')
    entry=output/'itch-entry';entry.mkdir()
    url='https://'+config['authDomain']+'/'
    (entry/'index.html').write_text('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Little Leaf</title><h1>Little Leaf</h1><p>Your café follows your Google account.</p><a target="_blank" rel="noopener" href="'+url+'">Open the full game and sign in</a><p>Opens a new tab for secure sign-in and account saves.</p>')
    if trusted_itch_origin:
        preview_config=json.loads((output/'firebase.json').read_text())['hosting']
        preview_config['site']=config['projectId']
        policy="frame-ancestors https://html-classic.itch.zone https://siowyiyou.itch.io"
        preview_config['headers'].extend({'source':path,'headers':[
            {'key':'Content-Security-Policy','value':policy},
            {'key':'Cache-Control','value':'no-store'}]} for path in ['/', '/index.html'])
        (output/'firebase.json').write_text(json.dumps({'hosting':preview_config},indent=2)+'\n')
    (output/'firebase-variant-manifest.json').write_text(json.dumps({'base_web_manifest':base,'base_web_manifest_sha256':hashlib.sha256(base_bytes).hexdigest(),'status':'staged-not-published','files':{p.relative_to(output).as_posix():sha256(p) for p in output.rglob('*') if p.is_file()}},indent=2))

BROWSER_GATES = {
    'firebase-fullflow': ('firebase-fullflow/firebase-fullflow.json', 'passed', True),
    'inbox': ('inbox-browser/compensation-inbox-browser.json', 'passed', True),
    'tutorial': ('fresh-tutorial-browser/fresh-tutorial-browser.json', 'status', 'passed'),
    'compatibility': ('wall-browser/wall-compatibility-browser.json', 'status', 'passed'),
    'save-log': ('save-log-browser/save-log-browser.json', 'passed', True),
    'webkit-recovery': ('connection-recovery-browser/connection-recovery-browser.json', 'passed', True),
}
FOCUSED_LOGS = ['adapter.log', 'delayed-network.log', 'recovery.log', 'choice.log', 'session.log', 'update-notice.log', 'recovery-presentation.log', 'recovery-browser.log', 'staging-tests.log', 'rules.log']

def validate_fresh_ci(build, engine_report, focused_logs, source, tree, run_id, attempt):
    if not re.fullmatch(r'[1-9][0-9]*', str(run_id)) or not re.fullmatch(r'[1-9][0-9]*', str(attempt)):
        raise ValueError('Fresh CI requires this run and attempt identity')
    base=validate_export_inventory(build)
    if (base.get('source_commit')!=source or base.get('source_tree')!=tree
        or str(base.get('workflow_run'))!=str(run_id) or str(base.get('workflow_attempt'))!=str(attempt)
        or base.get('toolchain_verification')!='checksum-pinned-official-archives'
        or base.get('packed_smoke')!='passed' or base.get('test_report_sha256')!=sha256(engine_report)):
        raise ValueError('Fresh source/run/export/native report binding mismatch')
    native=json.loads(engine_report.read_text())
    if (native.get('status')!='passed' or native.get('source_commit')!=source or native.get('player_save_used') is not False
        or native.get('total_checks',0)<=0 or native.get('total_checks')!=base.get('engine_checks')
        or native.get('test_processes',0)<=0 or native.get('test_processes')!=base.get('test_processes')):
        raise ValueError('Complete fresh native gate required')
    export_path=build/'evidence/export-report.json';export=json.loads(export_path.read_text())
    if export.get('manifest')!=base or not export.get('stages') or any(x.get('exit_code')!=0 for x in export['stages']):
        raise ValueError('Fresh export evidence differs')
    records={'native':sha256(engine_report),'export':sha256(export_path)}
    for name,(relative,key,expected) in BROWSER_GATES.items():
        path=build/'evidence'/relative;report=json.loads(path.read_text())
        if report.get(key)!=expected or (key=='passed' and report.get(key) is not True):
            raise ValueError('Fresh browser gate did not pass: '+name)
        if name=='firebase-fullflow':
            expected={'source_commit':source,'source_tree':tree,'export_manifest_sha256':sha256(build/'web/release-manifest.json'),'native_report_sha256':sha256(engine_report),'real_compiled_ui':True,'real_firestore_rules':True,'synthetic_only':True,'browser_sandbox':True,'real_google_sign_in':False,'diagnostic_only':False}
            if any(report.get(k)!=v for k,v in expected.items()) or not report.get('checks'):
                raise ValueError('Compiled Firebase browser/source binding mismatch')
            required=['firebase/fullflow.test.mjs','firebase/fullflow_fixtures.mjs','firebase/fullflow_network.mjs','tests/probe_cloud_recovery_geometry.gd','tools/prepare_browser_qa.py','web/little_leaf_firebase.js','web/little_leaf_firebase_session.js','web/little_leaf_firebase_boot.mjs','web/little_leaf_update.js','firebase/firestore.rules']
            if report.get('source_sha256')!={name:sha256(source_path(ROOT,name)) for name in required}:
                raise ValueError('Compiled Firebase source modules changed')
        if name in {'tutorial','compatibility'} and report.get('browser_verified') is not True:
            raise ValueError('Actual browser validation required: '+name)
        if name=='tutorial' and (report.get('binding',{}).get('source_commit')!=source or report.get('binding',{}).get('diagnostic_only')):
            raise ValueError('A browser-only diagnostic is not a full source gate')
        manifest_hash=sha256(build/'web/release-manifest.json')
        if name=='tutorial':
            binding=report.get('binding',{})
            if binding.get('export_manifest_sha256')!=manifest_hash or binding.get('engine_report_sha256')!=sha256(engine_report):
                raise ValueError('Tutorial export/native binding mismatch')
        elif name=='webkit-recovery':
            if any(report.get(k)!=v for k,v in {'source_commit':source,'source_tree':tree,'export_manifest_sha256':manifest_hash,'native_report_sha256':sha256(engine_report)}.items()) or report.get('export_files')!={k:base['files'][k] for k in ['index.html','index.js','index.wasm','index.pck']}:
                raise ValueError('WebKit export/source binding mismatch')
        elif name=='compatibility':
            if report.get('inputs',{}).get('new_commit')!=source or report.get('inputs',{}).get('export_files',{}).get('new')!=base['files']:
                raise ValueError('Compatibility export/source binding mismatch')
        elif name=='save-log':
            if report.get('export_sha256')!={k:base['files'][k]['sha256'] for k in ['index.html','index.js','index.wasm','index.pck']}:
                raise ValueError('Save-log export binding mismatch')
        elif name=='inbox':
            if report.get('export_manifest_sha256')!=manifest_hash:raise ValueError('Inbox full export binding mismatch')
            if report.get('export_js_sha256')!=base['files']['index.js']['sha256'] or report.get('web_template_sha256')!=base.get('web_template_sha256') or not report.get('source_sha256'):
                raise ValueError('Inbox export binding mismatch')
            expected_sources={'tests/engine_launch_hook.js','tests/fixtures/inbox-vault-018.js','web/little_leaf_vault.js','web/little_leaf_inbox.js','tests/compensation_inbox_suite.js'}
            if set(report['source_sha256'])!=expected_sources:raise ValueError('Incomplete Inbox source binding')
            for relative,digest in report['source_sha256'].items():
                if sha256(source_path(ROOT,relative))!=digest:
                    raise ValueError('Inbox source binding mismatch')
        records[name]=sha256(path)
    for name in FOCUSED_LOGS:
        path=focused_logs/name
        if not path.is_file() or not path.stat().st_size:
            raise ValueError('Missing fresh focused evidence: '+name)
        from run_firebase_focused import COMMANDS
        receipt_path=focused_logs/(name+'.json');receipt=json.loads(receipt_path.read_text())
        expected={'schema_version':1,'status':'passed','exit_code':0,'command':COMMANDS[name],
                  'source_commit':source,'source_tree':tree,'workflow_run':str(run_id),'workflow_attempt':str(attempt),'log_sha256':sha256(path)}
        if receipt!=expected:raise ValueError('Invalid same-run focused success receipt: '+name)
        records['firebase-'+name]=sha256(path)
        records['firebase-'+name+'.json']=sha256(receipt_path)
    return {'schema_version':1,'status':'fresh-gates-passed','source_commit':source,'source_tree':tree,
            'workflow_run':str(run_id),'workflow_attempt':str(attempt),'new_engine_run':True,
            'hosted_acceptance':False,'gate_evidence_sha256':records}

def add_fresh_evidence(build, output, engine_report, focused_logs, proof):
    evidence=output/'evidence';evidence.mkdir()
    shutil.copy2(engine_report,evidence/'native-summary.json')
    shutil.copy2(build/'evidence/export-report.json',evidence/'export-report.json')
    for name,(relative,_,_) in BROWSER_GATES.items():shutil.copy2(build/'evidence'/relative,evidence/(name+'.json'))
    for name in FOCUSED_LOGS:
        for suffix in ['', '.json']:shutil.copy2(focused_logs/(name+suffix),evidence/('firebase-'+name+suffix))
    (evidence/'fresh-ci.json').write_text(json.dumps(proof,indent=2)+'\n')
    manifest_path=output/'firebase-variant-manifest.json';manifest=json.loads(manifest_path.read_text())
    base=manifest['base_web_manifest']
    marker_path=output/'public/hosting-release.json';marker=json.loads(marker_path.read_text())
    marker['engine_source_commit']=base['source_commit'];marker_path.write_text(json.dumps(marker,indent=2)+'\n')
    manifest.update(source_commit=base['source_commit'],source_tree=base['source_tree'],fresh_ci=proof,
                    canonical_game_url='https://little-leaf-41e5d.firebaseapp.com/')
    manifest['files']={p.relative_to(output).as_posix():sha256(p) for p in sorted(output.rglob('*')) if p.is_file() and p.name!='firebase-variant-manifest.json'}
    manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--validated-web-build',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--public-config',type=Path,required=True);p.add_argument('--local-tools',action='store_true')
    p.add_argument('--require-fresh-ci',action='store_true');p.add_argument('--engine-report',type=Path);p.add_argument('--focused-logs',type=Path)
    p.add_argument('--itch-preview-bootstrap',action='store_true')
    a=p.parse_args();git=lambda *args:subprocess.check_output(['git','-C',str(ROOT),*args],text=True).strip()
    if git('status','--porcelain'):raise RuntimeError('Commit/review all source before staging')
    if os.environ.get('GITHUB_ACTIONS')=='true' and (a.local_tools or not a.require_fresh_ci):
        raise RuntimeError('GitHub Firebase staging must use fresh complete CI; local exceptions are forbidden')
    source,tree=git('rev-parse','HEAD'),git('rev-parse','HEAD^{tree}')
    validate_web_gate(a.validated_web_build,source,tree,a.local_tools)
    proof=None
    if a.require_fresh_ci:
        if not a.engine_report or not a.focused_logs:raise ValueError('Fresh CI evidence paths required')
        proof=validate_fresh_ci(a.validated_web_build,a.engine_report,a.focused_logs,source,tree,os.environ.get('GITHUB_RUN_ID',''),os.environ.get('GITHUB_RUN_ATTEMPT',''))
    config=json.loads(a.public_config.read_text())
    if proof and (config.get('projectId')!='little-leaf-41e5d' or config.get('authDomain')!='little-leaf-41e5d.firebaseapp.com'):
        raise ValueError('Fresh preview requires the approved public Firebase project configuration')
    if a.itch_preview_bootstrap:
        if not proof:raise ValueError('Trusted preview bootstrap requires the unchanged fresh CI gates')
        from build_itch_trusted_preview import prepare
        prepare(a.validated_web_build,a.output,config,
                'https://little-leaf-41e5d--itch-embed-test-localfixture.web.app',source,tree)
        # This fresh source build is not the local reviewed-engine reuse candidate.
        path=a.output/'firebase-variant-manifest.json'
        manifest=json.loads(path.read_text());manifest.pop('engine_reuse',None)
        manifest['status']='staged-not-published'
        path.write_text(json.dumps(manifest,indent=2)+'\n')
    else:
        stage(a.validated_web_build,a.output,config)
    if proof:
        add_fresh_evidence(a.validated_web_build,a.output,a.engine_report,a.focused_logs,proof)
        result={'source_sha':source,'manifest_sha256':sha256(a.output/'firebase-variant-manifest.json'),
                'artifact_name':'little-leaf-firebase-'+source+'-'+proof['workflow_attempt']}
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'],'a') as out:
                for key,value in result.items():out.write(key+'='+value+'\n')
        print(json.dumps(result))
if __name__=='__main__':main()
