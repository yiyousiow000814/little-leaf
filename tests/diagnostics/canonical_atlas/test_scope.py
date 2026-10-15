import unittest
from run import EXPECTED_RGBA,frozen_targets,receipt_passed,native_fingerprint_passed
class ScopeTests(unittest.TestCase):
 def receipt(self):return {'checks':3,'failures':[],'baseline_sha256':EXPECTED_RGBA.copy(),'candidate_sha256':EXPECTED_RGBA.copy(),'display_server':'X11','renderer':'gl_compatibility','engine':'4.6.3-stable (official)','adapter':'llvmpipe (LLVM 20.1.2, 256 bits)'}
 def test_exact_native_build_required(self):
  log='Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org\nMesa 25.2.8-0ubuntu0.24.04.4';self.assertTrue(native_fingerprint_passed(log));self.assertFalse(native_fingerprint_passed(log.replace('7d41c59c4','wrong')))
 def test_wrong_receipt_engine_rejected(self):
  r=self.receipt();r['engine']='4.6.2-stable (official)';self.assertFalse(receipt_passed(r,0))
 def test_exact_reference(self):self.assertTrue(receipt_passed(self.receipt(),0))
 def test_changed_pixels_rejected(self):
  r=self.receipt();r['baseline_sha256']=r['candidate_sha256']=['changed']*3;self.assertFalse(receipt_passed(r,0))
 def test_native_failure_rejected(self):self.assertFalse(receipt_passed(self.receipt(),1))
 def test_wrong_renderer_rejected(self):
  r=self.receipt();r['adapter']='NVIDIA';self.assertFalse(receipt_passed(r,0))
 def test_missing_camera_identity_stops(self):
  with self.assertRaises(AssertionError):frozen_targets({'candidate':None})
 def test_scope_excludes_other_targets(self):
  i={n:{'commit':str(k)*40,'tree':str(k+3)*40} for k,n in enumerate(['control','candidate'])};i['fps128']={'commit':'x'*40,'tree':'x'*40};self.assertEqual(set(frozen_targets(i)),{'control','candidate'})
if __name__=='__main__':unittest.main()
