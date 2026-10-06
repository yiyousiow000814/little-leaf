from pathlib import Path
import subprocess,os,zipfile,io,json,ast,shutil,re,time
w=Path.cwd();r=w/'crazygames-variant';q=r/'qa/crazygames';p=w/'crazygames-native-saveguard-tests3';p.mkdir(exist_ok=False)
# exact WIP tracked source plus dedicated controller-ack test; no original data
archive=subprocess.check_output(['git','-c','safe.directory='+r.as_posix(),'archive','--format=zip','HEAD'],cwd=r)
with zipfile.ZipFile(io.BytesIO(archive)) as z:z.extractall(p)
shutil.copy2(r/'tests/test_crazygames_ack.gd',p/'tests/test_crazygames_ack.gd')
s=p/'scripts/cafe_web_save.gd';code=s.read_text(encoding='utf-8').replace('const STAGING_FILE="/tmp/little_leaf_vault_staging.json"','const STAGING_FILE="res://tests/synthetic_stage.json"').replace('DirAccess.make_dir_recursive_absolute("/tmp")','DirAccess.make_dir_recursive_absolute("res://tests")');s.write_text(code,encoding='utf-8',newline='\n')
tree=ast.parse((r/'tests/run_integration_candidate.py').read_text(encoding='utf-8'));suites=next(ast.literal_eval(x.value) for x in tree.body if isinstance(x,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='SUITES' for t in x.targets))
selected={'test_save_log','test_startup_retry','test_autosave_feedback','test_autosave_feedback_adversarial','test_intro_lifecycle_headless','test_intro_cli_bypass','test_economy_revision','test_hud_layout','test_compensation_inbox','test_inbox_save_cache'}
suites=[(name,marker) for name,marker in suites if name in selected]+[('test_crazygames_ack','CRAZYGAMES_ACK_RESULT')]
records=[]
for name,marker in [('import',None)]+suites:
 env=dict(os.environ)
 for key in ['APPDATA','LOCALAPPDATA','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
  d=p/'synthetic-profiles'/name;d.mkdir(parents=True,exist_ok=True);env[key]=d.as_posix()
 env['LL_INTRO_RESULT']=str(q/'native-intro.json');env['LL_UI_RESULT']=str(q/(name+'-ui.json'))
 args=['--editor','--import','--quit'] if name=='import' else ['--script','res://tests/'+name+'.gd','--','--visual-qa','--fresh-review']+([] if name=='test_intro_lifecycle_headless' else ['--skip-intro'])
 if name in ['test_autosave_feedback','test_autosave_feedback_adversarial']:args=['--script','res://tests/'+name+'.gd','--','--skip-intro']
 start=time.time();out=subprocess.run([str(w/'crazygames-tools/Godot_v4.6.3-stable_win64_console.exe'),'--headless','--path',str(p),*args],env=env,capture_output=True,timeout=150);text=(out.stdout+out.stderr).decode('utf-8','replace');(q/('native-'+name+'.txt')).write_text(text,encoding='utf-8')
 results=[json.loads(line[len(marker)+1:]) for line in text.splitlines() if marker and line.startswith(marker+' ')]
 passed=out.returncode==0 and 'SCRIPT ERROR:' not in text and (not marker or (len(results)==1 and not results[0].get('failures')))
 record={'test':name,'passed':passed,'return_code':out.returncode,'checks':sum(x.get('checks',0) for x in results),'seconds':round(time.time()-start,1)};records.append(record);print(json.dumps(record),flush=True)
 (q/'NATIVE-TEST-SUMMARY.json').write_text(json.dumps({'synthetic_only':True,'real_cloud':False,'source_commit':'6cab8c377b79e1c457600fa7ebeccb1d956e1439','dedicated_ack_test_additional':True,'records':records,'passed':all(x['passed'] for x in records),'total_checks':sum(x['checks'] for x in records)},indent=2)+'\n',encoding='utf-8')
 if not passed:break
