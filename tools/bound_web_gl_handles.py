"""Recycle deleted names in the pinned generated WebGL bookkeeping tables.

Only buffers, vertex arrays and syncs showed continuous churn in the disposable
game profile. Preserve global allocation for other tables and for empty pools.
Apply after the existing presenter optimization, before distribution hashing.
Official template archives and the Wasm binary remain unchanged.
"""
import hashlib
from pathlib import Path

PATCH_ID = "emscripten-webgl-freed-handle-reuse-v1"
INPUT_SHA256 = "926bd39c551fc2f802ea426d37fdcfb0265b2471222af220132288e0b0e56a7b"
ALLOCATOR = b"getNewId:table=>{var ret=GL.counter++;for(var i=table.length;i<ret;i++){table[i]=null}return ret}"
BUFFERS = b"if(id==GLctx.currentPixelUnpackBufferBinding)GLctx.currentPixelUnpackBufferBinding=0}};"
VAOS = b"GLctx.deleteVertexArray(GL.vaos[id]);GL.vaos[id]=null}};"
SYNCS = b"GLctx.deleteSync(sync);sync.name=0;GL.syncs[id]=null};"
REPLACEMENTS = (
    (ALLOCATOR, ALLOCATOR.replace(b"var ret=", b"if(table.littleLeafFreeIds&&table.littleLeafFreeIds.length)return table.littleLeafFreeIds.pop();var ret=")),
    (BUFFERS, BUFFERS.replace(b"=0}};", b"=0;(GL.buffers.littleLeafFreeIds||(GL.buffers.littleLeafFreeIds=[])).push(id)}};")),
    (VAOS, b"var vao=GL.vaos[id];if(!vao)continue;GLctx.deleteVertexArray(vao);vao.name=0;GL.vaos[id]=null;(GL.vaos.littleLeafFreeIds||(GL.vaos.littleLeafFreeIds=[])).push(id)}};"),
    (SYNCS, SYNCS.replace(b"=null};", b"=null;(GL.syncs.littleLeafFreeIds||(GL.syncs.littleLeafFreeIds=[])).push(id)};")),
)


def bound_web_gl_handles(runtime: Path) -> dict:
    original = runtime.read_bytes()
    digest = hashlib.sha256(original).hexdigest()
    if digest != INPUT_SHA256 or any(original.count(old) != 1 or new in original
                                     for old, new in REPLACEMENTS):
        raise RuntimeError("Unrecognized WebGL runtime; review the pinned runtime before applying " + PATCH_ID)
    patched = original
    for old, new in REPLACEMENTS:
        patched = patched.replace(old, new, 1)
    runtime.write_bytes(patched)
    return {"id": PATCH_ID, "file": runtime.name, "input_sha256": digest,
            "output_sha256": hashlib.sha256(patched).hexdigest(),
            "tables": ["buffers", "vaos", "syncs"]}
