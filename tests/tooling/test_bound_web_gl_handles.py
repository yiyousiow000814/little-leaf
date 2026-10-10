import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
import subprocess
import json
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[2] / "tools/bound_web_gl_handles.py"
spec = importlib.util.spec_from_file_location("bound_web_gl_handles", MODULE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class WebGLHandlePatchTests(unittest.TestCase):
    def test_live_handles_and_retained_capacity_under_repeated_lifecycle(self):
        # Small pinned-function fixture; this digest allowance is test-only.
        # The export guard still requires the complete official runtime hash.
        fixture = b"var GL={" + module.ALLOCATOR + b"};" + (
            b"_emscripten_glDeleteBuffers=(n,buffers)=>{for(var i=0;i<n;i++){"
            b"var id=HEAP32[buffers+i*4>>2];var buffer=GL.buffers[id];"
            b"if(!buffer)continue;GLctx.deleteBuffer(buffer);buffer.name=0;"
            b"GL.buffers[id]=null;if(id==GLctx.currentPixelPackBufferBinding)"
            b"GLctx.currentPixelPackBufferBinding=0;" + module.BUFFERS +
            b"_emscripten_glDeleteVertexArrays=(n,vaos)=>{for(var i=0;i<n;i++){"
            b"var id=HEAP32[vaos+i*4>>2];" + module.VAOS +
            b"_emscripten_glDeleteSync=id=>{if(!id)return;var sync=GL.syncs[id];"
            b"if(!sync){GL.recordError(1281);return}" + module.SYNCS)
        with tempfile.TemporaryDirectory() as folder:
            runtime = Path(folder) / "index.js"
            runtime.write_bytes(fixture)
            with patch.object(module, "INPUT_SHA256", hashlib.sha256(fixture).hexdigest()):
                module.bound_web_gl_handles(runtime)
            result = subprocess.run(
                ["node", str(Path(__file__).with_name("webgl_handle_lifecycle.js")), str(runtime)],
                check=True, capture_output=True, text=True, timeout=10)
            evidence = json.loads(result.stdout)
            self.assertEqual(evidence["result"], "passed")
            self.assertEqual(evidence["cycles"], 20000)

    def apply_fixture(self, data, allow_digest=False):
        with tempfile.TemporaryDirectory() as folder:
            runtime = Path(folder) / "index.js"
            runtime.write_bytes(data)
            digest = hashlib.sha256(data).hexdigest() if allow_digest else module.INPUT_SHA256
            with patch.object(module, "INPUT_SHA256", digest):
                receipt = module.bound_web_gl_handles(runtime)
            return runtime.read_bytes(), receipt

    def test_unknown_runtime_is_unchanged(self):
        with tempfile.TemporaryDirectory() as folder:
            runtime = Path(folder) / "index.js"
            runtime.write_bytes(b"unrecognized")
            with self.assertRaises(RuntimeError):
                module.bound_web_gl_handles(runtime)
            self.assertEqual(runtime.read_bytes(), b"unrecognized")

    def test_all_anchors_are_required_before_write(self):
        for missing in range(len(module.REPLACEMENTS)):
            data = b"\n".join(old for i, (old, _) in enumerate(module.REPLACEMENTS) if i != missing)
            with self.assertRaises(RuntimeError):
                self.apply_fixture(data, allow_digest=True)

    def test_duplicate_anchor_rejected(self):
        data = b"\n".join(old for old, _ in module.REPLACEMENTS) + module.ALLOCATOR
        with self.assertRaises(RuntimeError):
            self.apply_fixture(data, allow_digest=True)

    def test_receipt_and_second_application_rejection(self):
        data = b"\n".join(old for old, _ in module.REPLACEMENTS)
        result, receipt = self.apply_fixture(data, allow_digest=True)
        self.assertEqual(receipt["input_sha256"], hashlib.sha256(data).hexdigest())
        self.assertEqual(receipt["output_sha256"], hashlib.sha256(result).hexdigest())
        self.assertEqual(receipt["tables"], ["buffers", "vaos", "syncs"])
        with self.assertRaises(RuntimeError):
            self.apply_fixture(result, allow_digest=True)


if __name__ == "__main__":
    unittest.main()
