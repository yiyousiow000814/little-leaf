"""Gate a Godot SCons compilation DB and list only five partial object targets.

No compilation, shells, discovery of alternate binaries, or path writes.
"""
import json
from pathlib import Path
import re
import shlex
import shutil
import sys

EXPECTED = {
    "main/main.cpp", "drivers/gles3/rasterizer_gles3.cpp",
    "servers/rendering/renderer_canvas_cull.cpp",
    "servers/rendering/renderer_viewport.cpp",
    "servers/rendering/rendering_server_default.cpp",
}
REQUIRED = {"LINUXBSD_ENABLED", "TOOLS_ENABLED", "DEBUG_ENABLED", "NDEBUG",
            "LL397_ENGINE_DIAG", "GLES3_ENABLED", "X11_ENABLED", "ACCESSKIT_ENABLED"}
FORBIDDEN = {"DEV_ENABLED", "REAL_T_IS_DOUBLE", "SCU_BUILD_ENABLED", "TESTS_ENABLED",
             "GODOT_USE_TRACY", "GODOT_USE_PERFETTO", "GODOT_USE_INSTRUMENTS"}
OBJECT = re.compile(r"(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.linuxbsd\.editor\.x86_64\.o")

def relative(path, cwd, root):
    return (cwd / path).resolve().relative_to(root).as_posix()

def defs(args):
    result=set()
    for i, arg in enumerate(args):
        define=args[i+1] if arg=="-D" and i+1<len(args) else arg[2:] if arg.startswith("-D") else ""
        if define:
            result.add(define.split("=",1)[0])
    return result

def gate(rows, root, compiler, required=REQUIRED):
    found={}
    for row in rows:
        cwd=Path(row["directory"]).resolve(strict=True)
        try:
            source=relative(row["file"],cwd,root)
        except ValueError:
            continue
        if source not in EXPECTED:
            continue
        if source in found:
            raise ValueError("duplicate or mixed profile: "+source)
        args=row.get("arguments") or shlex.split(row["command"])
        if any(item.startswith("@") or item in ("&&","|",";") for item in args):
            raise ValueError("unreviewed response file or command sequence: "+source)
        actual=shutil.which(args[0])
        if not actual or Path(actual).resolve()!=compiler:
            raise ValueError("compiler executable not pinned: "+source)
        features=defs(args)
        if not required<=features or features&FORBIDDEN:
            raise ValueError(f"wrong active feature set {source}: missing={required-features}, extra={features&FORBIDDEN}")
        if "-c" not in args or args.count("-o")!=1 or not any(a in {"-O2","-O3","-Ofast"} for a in args) or "-O0" in args:
            raise ValueError("not a production object compilation: "+source)
        output=relative(args[args.index("-o")+1],cwd,root)
        if not OBJECT.fullmatch(output):
            raise ValueError("wrong object variant: "+output)
        if row.get("output") and relative(row["output"],cwd,root)!=output:
            raise ValueError("output field differs from compiler output")
        found[source]=output
    if set(found)!=EXPECTED or len(set(found.values()))!=len(EXPECTED):
        raise ValueError("incomplete distinct partial TU coverage")
    return [found[source] for source in sorted(found)]

if __name__=="__main__":
    root,compiler,db=map(Path,sys.argv[1:])
    root=root.resolve(strict=True);compiler=compiler.resolve(strict=True)
    for obj in gate(json.loads(db.read_bytes()),root,compiler):
        print(obj)
