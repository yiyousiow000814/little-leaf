"""Synthetic staging checks; does not claim an engine export or publish."""
import sys, tempfile, json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'ci'))
from build_firebase import stage, ROOT
from build_web import sha256
with tempfile.TemporaryDirectory() as d:
    d=Path(d);build=d/'build';(build/'web').mkdir(parents=True)
    shell=(ROOT/'web/little_leaf_shell.html').read_text().replace('$GODOT_URL','index.js')
    (build/'web/index.html').write_text(shell);(build/'web/release-manifest.json').write_text(json.dumps({'source_commit':'synthetic-commit','source_tree':'synthetic-tree','workflow_run':'local','version':'0.1.10','files':{'index.html':{'sha256':sha256(build/'web/index.html'),'bytes':(build/'web/index.html').stat().st_size}}}))
    config={'apiKey':'synthetic-public-key','authDomain':'demo-little-leaf.firebaseapp.com','projectId':'demo-little-leaf','appId':'synthetic-app-id'}
    stage(build,d/'out',config)
    result=(d/'out/public/index.html').read_text()
    assert '__littleLeafFirebaseReady.then(() => window.__littleLeafVault.boot())' in result
    assert result.index('window.__littleLeafFirebaseReady =') < result.index('<script src="index.js">')
    assert (build/'web/index.html').read_text()==shell
    assert 'target="_blank"' in (d/'out/itch-entry/index.html').read_text()
    marker=json.loads((d/'out/public/hosting-release.json').read_text());assert marker['source_commit']=='synthetic-commit';assert marker['ci_run_id']=='local'
    assert not (d/'out/public/release-manifest.json').exists()
    assert 'firebase-firestore' in (d/'out/public/little_leaf_firebase.js').read_text()
    try:stage(build,d/'invalid',{**config,'authDomain':'evil.test'})
    except ValueError:pass
    else:raise AssertionError('wrong auth domain accepted')
print('Firebase staging synthetic checks passed; default Web source unchanged')
