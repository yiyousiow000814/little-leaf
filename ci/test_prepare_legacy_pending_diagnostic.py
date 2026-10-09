import hashlib, tempfile, unittest, zipfile
from pathlib import Path
from prepare_legacy_pending_diagnostic import unpack
class ArchiveGuards(unittest.TestCase):
 def test_archive_guards(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);archive=root/'sample.zip'
   def make(name='safe.txt',symlink=False):
    with zipfile.ZipFile(archive,'w') as z:
     entry=zipfile.ZipInfo(name)
     if symlink:entry.external_attr=(0o120777<<16)
     z.writestr(entry,'synthetic test')
    return hashlib.sha256(archive.read_bytes()).hexdigest()
   digest=make();unpack(archive,root/'valid',digest,{'safe.txt'})
   self.assertEqual((root/'valid/safe.txt').read_text(),'synthetic test')
   with self.assertRaisesRegex(ValueError,'hash mismatch'):unpack(archive,root/'bad','0'*64)
   with self.assertRaisesRegex(ValueError,'Missing selected'):unpack(archive,root/'missing',digest,{'other.txt'})
   for name,link in [('../escape',False),('/absolute',False),('link',True)]:
    digest=make(name,link)
    with self.assertRaisesRegex(ValueError,'Unsafe archive'):unpack(archive,root/'unsafe',digest)
   self.assertFalse((root/'escape').exists())
if __name__=='__main__':unittest.main()
