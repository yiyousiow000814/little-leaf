"""Validate retained compiled inputs for diagnostics only, never release qualification."""
import argparse, hashlib, json, os, subprocess, zipfile
from pathlib import Path
BASE='a7afe3f6c066f44690b1e73895d884b41d4a199b'
ARTIFACTS={
 'web':('11600374596','5f7a391ca4386e0e78f093a122f6d502e415501d6dc2214e371e6d2325b5b517'),
 'evidence':('11602076197','788ea088bcdd2f95de20128286bcf19d1c42cc85ae1ff9c1600e95061a5cad8f')}
RUNTIME={'web/little_leaf_firebase.js','web/little_leaf_firebase_session.js','web/little_leaf_firebase_boot.mjs','web/little_leaf_update.js'}
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def unsupported_changes(paths):
 unsupported=[]
 for p in paths:
  if p=='tests/probe_cloud_recovery_geometry.gd':continue
  if p in RUNTIME or p.startswith(('firebase/','ci/','.github/workflows/')):continue
  if p.startswith('tests/') and p.endswith('.js') and p!='tests/engine_launch_hook.js':continue
  unsupported.append(p)
 return unsupported

def validate_changes(paths):
 unsupported=unsupported_changes(paths)
 if unsupported:raise ValueError('Retained native export cannot cover changed input: '+unsupported[0])

def eligibility(paths,source):
 unsupported=unsupported_changes(paths)
 return {'diagnostic_only':True,'release_qualification':False,'compiled_source':BASE,'harness_source':source,'eligible':not unsupported,'status':'eligible' if not unsupported else 'ineligible_native_source_changed','unsupported_inputs':unsupported,'required_gate':'fresh complete Web/Firebase Stage'}
def unpack(archive,dest,expected):
 if sha(archive)!=expected:raise ValueError('Pinned artifact ZIP hash mismatch')
 with zipfile.ZipFile(archive) as z:
  for info in z.infolist():
   if Path(info.filename).is_absolute() or '..' in Path(info.filename).parts or (info.external_attr >> 16)&0o170000==0o120000:raise ValueError('Unsafe ZIP member')
  z.extractall(dest)
def verify(web,native):
 manifest=json.loads((web/'release-manifest.json').read_text());engine=json.loads(native.read_text())
 if manifest['source_commit']!=BASE or engine['source_commit']!=BASE or engine['status']!='passed' or engine['player_save_used'] is not False:raise ValueError('Retained source/native identity mismatch')
 if manifest['test_report_sha256']!=sha(native):raise ValueError('Native report not bound to export')
 for name,item in manifest['files'].items():
  if Path(name).is_absolute() or '..' in Path(name).parts:raise ValueError('Unsafe exported path')
  p=web/name
  if sha(p)!=item['sha256'] or p.stat().st_size!=item['bytes']:raise ValueError('Export bytes mismatch')
 return manifest
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--artifacts',type=Path);p.add_argument('--eligibility',type=Path);a=p.parse_args()
 paths=subprocess.check_output(['git','diff','--name-only',BASE,'HEAD'],text=True).splitlines()
 if a.eligibility:
  receipt=eligibility(paths,subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip());a.eligibility.parent.mkdir(parents=True,exist_ok=True);a.eligibility.write_text(json.dumps(receipt,indent=2)+'\n')
  if os.environ.get('GITHUB_OUTPUT'):
   with open(os.environ['GITHUB_OUTPUT'],'a') as output:output.write('eligible='+str(receipt['eligible']).lower()+'\n')
  print(receipt['status']+'; fresh complete gate remains mandatory.');raise SystemExit(0)
 if not a.artifacts:p.error('--artifacts or --eligibility required')
 validate_changes(paths)
 for name,(_,digest) in ARTIFACTS.items():unpack(a.artifacts/(name+'.zip'),a.artifacts/name,digest)
 manifest=verify(a.artifacts/'web',a.artifacts/'evidence/engine-evidence/summary.json')
 receipt={'diagnostic_only':True,'release_qualification':False,'compiled_source':BASE,'harness_source':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'changed_paths':paths,'artifact_ids':{k:v[0] for k,v in ARTIFACTS.items()},'artifact_sha256':{k:v[1] for k,v in ARTIFACTS.items()},'export_manifest_sha256':sha(a.artifacts/'web/release-manifest.json')}
 (a.artifacts/'diagnostic-binding.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print('Pinned retained a7 export validated for synthetic diagnostics only; fresh final Stage remains required.')
