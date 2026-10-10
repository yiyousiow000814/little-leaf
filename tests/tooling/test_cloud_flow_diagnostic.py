import hashlib,json,tempfile,unittest,zipfile
from pathlib import Path
from cloud_flow_diagnostic import BASE,validate_changes,unpack,verify,sha,eligibility
class DiagnosticTests(unittest.TestCase):
 def test_only_runtime_and_qa_changes_allowed(self):
  validate_changes(['web/little_leaf_firebase_session.js','firebase/fullflow.test.mjs','ci/build_firebase.py','tests/firebase_session.js'])
  for path in ['scripts/cafe.gd','data/update_notes.json','project.godot','web/little_leaf_vault.js','tests/test_cloud_recovery_ui.gd','tests/fixtures/startup-retry-v15.json','tests/engine_launch_hook.js']:
   with self.assertRaises(ValueError):validate_changes([path])
 def test_ineligible_receipt_never_qualifies_or_weakens_guard(self):
  paths=['web/little_leaf_firebase_boot.mjs','data/release_notes.json','project.godot'];r=eligibility(paths,'a'*40)
  self.assertFalse(r['eligible']);self.assertFalse(r['release_qualification']);self.assertEqual(r['status'],'ineligible_native_source_changed');self.assertEqual(r['unsupported_inputs'],paths[1:])
  with self.assertRaises(ValueError):validate_changes(paths)
  allowed=eligibility(['firebase/fullflow.test.mjs'],'a'*40);self.assertTrue(allowed['eligible']);self.assertFalse(allowed['release_qualification'])
 def test_workflow_gates_retained_execution_and_keeps_receipt(self):
  text=(Path(__file__).resolve().parents[2]/'.github/workflows/cloud-save-flow-diagnostic.yml').read_text()
  self.assertEqual(text.count("if: steps.eligibility.outputs.eligible == 'true'"),4)
  self.assertIn('--eligibility',text);self.assertIn('diagnostic-eligibility.json',text);self.assertIn('if: always()',text)
  self.assertNotIn('continue-on-error',text)
 def test_exact_zip_and_safe_members(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'a.zip'
   with zipfile.ZipFile(p,'w') as z:z.writestr('../escape','x')
   with self.assertRaises(ValueError):unpack(p,Path(d)/'out',sha(p))
   with self.assertRaises(ValueError):unpack(p,Path(d)/'out','0'*64)
 def test_exact_export_native_binding(self):
  with tempfile.TemporaryDirectory() as d:
   w=Path(d);n=w/'native.json';n.write_text(json.dumps({'source_commit':BASE,'status':'passed','player_save_used':False}));(w/'index.pck').write_bytes(b'compiled')
   m={'source_commit':BASE,'test_report_sha256':sha(n),'files':{'index.pck':{'sha256':sha(w/'index.pck'),'bytes':8}}};p=w/'release-manifest.json';p.write_text(json.dumps(m));verify(w,n)
   (w/'index.pck').write_bytes(b'changed!')
   with self.assertRaises(ValueError):verify(w,n)
   m['source_commit']='a'*40;p.write_text(json.dumps(m))
   with self.assertRaises(ValueError):verify(w,n)
if __name__=='__main__':unittest.main()
