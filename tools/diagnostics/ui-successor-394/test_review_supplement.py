import os
import struct
import zlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import review_supplement as m

def write_png(path,w,h,color=6,metadata=False,variation=0):
    def chunk(name,body):
        return struct.pack(">I",len(body))+name+body+struct.pack(">I",zlib.crc32(name+body))
    pixel=bytes([1,2,3+variation,255] if color==6 else [1,2,3+variation])
    data=chunk(b"IHDR",struct.pack(">IIBBBBB",w,h,8,color,0,0,0))
    if metadata:data+=chunk(b"tEXt",b"purpose\0different metadata")
    data+=chunk(b"IDAT",zlib.compress((b"\0"+pixel*w)*h))+chunk(b"IEND",b"")
    path.write_bytes(b"\x89PNG\r\n\x1a\n"+data)

class SupplementTests(unittest.TestCase):
    def test_same_rgba_with_different_png_container_is_parity(self):
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder); a,b=p/"a",p/"b";a.mkdir();b.mkdir()
            write_png(a/"one.png",3,2)
            write_png(b/"one.png",3,2,color=2,metadata=True)
            c=m.read_frames(a,{"one.png":(3,2)});h=m.read_frames(b,{"one.png":(3,2)})
            self.assertNotEqual(c["one.png"]["png_sha256"],h["one.png"]["png_sha256"])
            self.assertEqual(m.compare({"one":c},{"one":h}),1)
            write_png(b/"one.png",3,2,variation=1)
            with self.assertRaisesRegex(ValueError,"pixel mismatch"):
                m.compare({"one":c},{"one":m.read_frames(b,{"one.png":(3,2)})})
    def test_missing_extra_and_wrong_size_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)
            with self.assertRaisesRegex(ValueError,"missing or extra"):
                m.read_frames(p,{"one.png":(3,2)})
            write_png(p/"one.png",2,2)
            with self.assertRaisesRegex(ValueError,"unsupported viewport PNG"):
                m.read_frames(p,{"one.png":(3,2)})
            write_png(p/"extra.png",3,2)
            with self.assertRaisesRegex(ValueError,"missing or extra"):
                m.read_frames(p,{"one.png":(2,2)})
            with self.assertRaisesRegex(ValueError,"surface set"):
                m.compare({"one":{}},{"two":{}})
    def test_corrupt_crc_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder);write_png(p/"one.png",3,2)
            b=bytearray((p/"one.png").read_bytes());b[30]^=1
            (p/"one.png").write_bytes(b)
            with self.assertRaisesRegex(ValueError,"CRC mismatch"):
                m.read_frames(p,{"one.png":(3,2)})
    def test_missing_native_marker_player_save_or_failed_assertion_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)
            variants=[
                "",
                'STORAGE_UI_RESULT {"checks":120,"failures":[],"player_save_used":true}',
                'STORAGE_UI_RESULT {"checks":120,"failures":["bad"],"player_save_used":false}',
                'STORAGE_UI_RESULT {"checks":30,"failures":[],"player_save_used":false}',
            ]
            for line in variants:
                with self.subTest(line=line), self.assertRaisesRegex(ValueError,"invalid actual Storage UI"):
                    m.storage_frames(p,line)
            with self.assertRaisesRegex(ValueError,"incomplete"):
                m.storage_frames(p,'STORAGE_UI_RESULT {"checks":120,"failures":[],"player_save_used":false}')
    def test_wrong_tree_and_unapproved_extra_path_rejected(self):
        with patch.object(m,"git",return_value=b"unreviewed\n"):
            with self.assertRaisesRegex(ValueError,"wrong tree"):
                m.bind(Path("/unused"))
        def pretend(repo,*args):
            if args[0]=="rev-parse":return m.TREES[args[-1].split("^")[0]].encode()
            if args[0]=="cat-file":return f"tree {m.TREES[m.HEAD]}\nparent {m.BASE}\n\nex".encode()
            if args[0]=="diff":return ("\n".join(m.POST)+"\nunreviewed.gd").encode()
            raise AssertionError(args)
        with patch.object(m,"git",side_effect=pretend):
            with self.assertRaisesRegex(ValueError,"unreviewed paths"):
                m.bind(Path("/unused"))

if __name__=="__main__":unittest.main()
