"""Verify exact retained final10a inputs for the bounded synthetic migration diagnostic."""
import argparse, hashlib, json, stat, subprocess, zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE='a6b8a3de4fb0f39529886b426fd7820a2c3c2ddc'
TREE='08bd2d87c4969dce910c7907682f4653b0110b65'
ARTIFACTS={
 'web':('11618320268','a70dde4aad2564f9fdfd9069019c2d16da4969a03d25d99a42dd380d069225df'),
 'evidence':('11617553429','b475db26ea04ef6cc286cfda7e6a87a0ecadf773194fd996d4804ea5b2f71f64')}
MANIFEST='5006f66ff1de43e712cc4b21fd3154d67dd0d5b2cad9d887b373c2a658571be7'
NATIVE='d154bf5691c38657e71f260f746ce675bd2925cff69859b14a887aa2b545c897'
NATIVE_FILES={'engine-evidence/summary.json','engine-evidence/test_cloud_recovery_ui.log','engine-evidence/test_update_notice.log'}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,message):
 if not ok:raise ValueError(message)
def unpack(archive,dest,expected,selected=None):
 require(sha(archive)==expected,'Immutable archive hash mismatch: '+archive.name)
 with zipfile.ZipFile(archive) as z:
  names=z.namelist();require(len(names)==len(set(names)),'Duplicate archive member')
  for entry in z.infolist():
   p=Path(entry.filename)
   require(not p.is_absolute() and '..' not in p.parts and not stat.S_ISLNK(entry.external_attr>>16),'Unsafe archive member')
  if selected is not None:require(selected<=set(names),'Missing selected native evidence')
  for entry in z.infolist():
   if selected is None or entry.filename in selected:z.extract(entry,dest)
def prepare(directory):
 directory=directory.resolve()
 for kind,(_,digest) in ARTIFACTS.items():unpack(directory/(kind+'.zip'),directory/kind,digest,NATIVE_FILES if kind=='evidence' else None)
 receipt=verify(directory/'web',directory/'evidence/engine-evidence/summary.json')
 (directory/'legacy-binding.json').write_text(json.dumps(receipt,indent=2)+'\n');return receipt
def verify(web,native):
 require(sha(web/'release-manifest.json')==MANIFEST,'Exact export manifest required')
 require(sha(native)==NATIVE,'Exact ordinary-run native summary required')
 manifest=json.loads((web/'release-manifest.json').read_text());engine=json.loads(native.read_text())
 require(manifest['source_commit']==SOURCE and manifest['source_tree']==TREE,'Final export source mismatch')
 require(str(manifest['workflow_run'])=='37933440818','Final ordinary run mismatch')
 require(engine['source_commit']==SOURCE and engine['status']=='passed' and engine['player_save_used'] is False,'Native evidence mismatch')
 require(manifest['test_report_sha256']==NATIVE,'Native evidence not bound to export')
 for name,record in manifest['files'].items():
  p=web/name;require(sha(p)==record['sha256'] and p.stat().st_size==record['bytes'],'Export bytes mismatch: '+name)
 for name,digest in manifest['production_sha256'].items():require(sha(ROOT/name)==digest,'Final production input changed: '+name)
 receipt={'diagnostic_only':True,'release_qualification':False,'synthetic_only':True,'compiled_source':SOURCE,'compiled_tree':TREE,'harness_source':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'workflow_run':'37933440818','artifact_ids':{k:v[0] for k,v in ARTIFACTS.items()},'archive_sha256':{k:v[1] for k,v in ARTIFACTS.items()},'export_manifest_sha256':MANIFEST,'native_report_sha256':NATIVE,'verified_production_inputs':len(manifest['production_sha256']),'verified_export_files':len(manifest['files'])}
 return receipt
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--artifacts',type=Path,required=True);a=p.parse_args();print(json.dumps(prepare(a.artifacts),indent=2))
