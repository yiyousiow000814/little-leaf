from pathlib import Path
import subprocess, os, json, zipfile, io, hashlib
ROOT=Path(__file__).resolve().parents[3]
BASE='a5dd2b2b3a0cfee9c79fcd75eb870a9892afbf27'
HEAD='0323bcde8145d40374b6bffc16f57654b6a4a514'
out=Path(os.environ['RUNNER_TEMP'])/'stove-atlas';out.mkdir()
reports=[]
for label,sha in [('baseline',BASE),('candidate',HEAD)]:
    folder=out/label;folder.mkdir()
    data=subprocess.check_output(['git','-C',str(ROOT),'-c','core.autocrlf=false','archive','--format=zip',sha])
    with zipfile.ZipFile(io.BytesIO(data)) as archive:archive.extractall(folder/'source')
    project=folder/'source/game'
    (project/'atlas_render.gd').write_bytes((Path(__file__).parent/'render.gd').read_bytes())
    env=os.environ.copy()
    for key in ['HOME','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
        path=folder/'saveguard'/key;path.mkdir(parents=True);env[key]=str(path)
    for stage,args in [('import',['--headless','--editor','--import']),('render',['--rendering-method','gl_compatibility','--audio-driver','Dummy','--resolution','32x32','--script','res://atlas_render.gd','--','--runtime-atlases'])]:
        with (folder/(stage+'.log')).open('w') as log:
            result=subprocess.run([os.environ['GODOT_BIN'],'--path',str(project),*args],stdout=log,stderr=subprocess.STDOUT,env=env,timeout=120)
        assert result.returncode==0,(label,stage)
    report=json.loads((project/'atlas-render-result.json').read_text())
    report['source']=sha;report['tree']=subprocess.check_output(['git','rev-parse',sha+'^{tree}'],cwd=ROOT,text=True).strip()
    reports.append(report)
    (out/(label+'-receipt.json')).write_text(json.dumps(report,indent=2))
    assert report['checks']==3 and not report['failures'] and all(report['matches_existing_cache']),report
assert reports[0]['rgba_sha256']==reports[1]['rgba_sha256'],reports
receipt={'checks':3,'failures':[],'baseline_sha256':reports[0]['rgba_sha256'],'candidate_sha256':reports[1]['rgba_sha256'],'reports':reports,'synthetic_only':True}
(out/'atlas-parity.json').write_text(json.dumps(receipt,indent=2))
print(json.dumps(receipt))
