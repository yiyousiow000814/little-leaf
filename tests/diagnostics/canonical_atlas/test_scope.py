import unittest
from run import EXPECTED_RGBA,frozen_targets,receipt_passed
class ScopeTests(unittest.TestCase):
 def receipt(self):return {'checks':3,'failures':[],'baseline_sha256':EXPECTED_RGBA.copy(),'candidate_sha256':EXPECTED_RGBA.copy(),'display_server':'X11','renderer':'gl_compatibility','engine':'4.6.3.stable.official.7d41c59c4','adapter':'llvmpipe (LLVM 20.1.2, 256 bits)'}
 def test_exact_reference(self):self.assertTrue(receipt_passed(self.receipt(),0))
 def test_changed_pixels_rejected(self):
  r=self.receipt();r['baseline_sha256']=r['candidate_sha256']=['changed']*3;self.assertFalse(receipt_passed(r,0))
 def test_native_failure_rejected(self):self.assertFalse(receipt_passed(self.receipt(),1))
 def test_wrong_renderer_rejected(self):
  r=self.receipt();r['adapter']='NVIDIA';self.assertFalse(receipt_passed(r,0))
 def test_missing_camera_identity_stops(self):
  with self.assertRaises(AssertionError):frozen_targets({'camera':None})
 def test_scope_excludes_other_targets(self):
  i={n:{'commit':str(k)*40,'tree':str(k+3)*40} for k,n in enumerate(['control','camera','background'])};i['fps128']={'commit':'x'*40,'tree':'x'*40};self.assertEqual(set(frozen_targets(i)),{'control','camera','background'})
if __name__=='__main__':unittest.main()
