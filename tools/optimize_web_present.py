"""Avoid a synchronous GPU state read in the pinned Emscripten presenter.

Both APIs return the current SCISSOR_TEST enable state. Chromium's generic
getParameter path waits for submitted GPU commands; isEnabled reads that same
capability through the dedicated API. Geometry, blitting and state restoration
remain unchanged. Apply only to the recognized generated runtime, before its
distribution hashes are recorded. Never modify the official template archive.
"""
import hashlib
from pathlib import Path

PATCH_ID = "emscripten-present-scissor-is-enabled-v1"
ORIGINAL = (b"blitOffscreenFramebuffer:context=>{var gl=context.GLctx;"
            b"var prevScissorTest=gl.getParameter(3089);")
OPTIMIZED = ORIGINAL.replace(b"gl.getParameter(3089)", b"gl.isEnabled(3089)")


def optimize_presentation(runtime: Path) -> dict:
    original = runtime.read_bytes()
    if original.count(ORIGINAL) != 1 or OPTIMIZED in original:
        raise RuntimeError("Unrecognized Web presenter; review the pinned runtime before applying " + PATCH_ID)
    optimized = original.replace(ORIGINAL, OPTIMIZED, 1)
    runtime.write_bytes(optimized)
    return {
        "id": PATCH_ID,
        "file": runtime.name,
        "input_sha256": hashlib.sha256(original).hexdigest(),
        "output_sha256": hashlib.sha256(optimized).hexdigest(),
    }
