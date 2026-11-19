"""Instrument only a disposable exact #397 project, with no game launch."""
import argparse, hashlib, json, pathlib, re

SCENARIO_HEAD="ce1435afb2329a6c1d2d77a8a19923dfd96bd205"
SCENARIO_TREE="03632a0d56e4294f5664859656c8809541766d1b"
MAIN="scripts/main.gd"
MODEL="scripts/core/cafe_model.gd"
DRAW="scripts/rendering/illustrated_cafe.gd"
NATIVE_DRAW="scripts/rendering/cafe_native_draw_node.gd"
SOURCE={
 "project.godot":"09a15b9558d981fe31f4a0fe4b83c6c98bbad4cd7bbc03d840e76ad7da87bf93",
 MAIN:"8c61d1056fc19d206d1bfbfeed6d1f746c94cd32d847ca8c66b0ed84e06b847f",
 MODEL:"14ed712d28bc5ea67dfcb5fbac6e7e1c05da29e0910ded22ad52d8764a9837b5",
 DRAW:"ab7f4942e446c1e0d4116635d8aa5329b2ae82ff5ec6bd0cc99db2c86ee1926b",
 NATIVE_DRAW:"485c298089fb735ccad3e99af0980b19eb4d44b5e434b1f1dc2c1a7c6baa60a3",
}
KEYS=["main_dispatch","duty_sync","input_hud","service_coordination","model_tick","staff_runtime","task_assignment","navigation","autosave","ui_refresh","roster","audio","renderer_update","street_motion","actor_motion","draw_prepare","ground_draw","exterior_draw","depth_sort","entity_draw","draw_finish","native_redraw"]
WRAPS={
 MAIN: [
  ("_process","delta","main_dispatch",False),
  ("_sync_staff_duty","","duty_sync",False),
  ("_tick_live_service","delta","service_coordination",False),
  ("_animate_staff","delta","staff_runtime",False),
  ("_assign_service_job","staff, index","task_assignment",False),
  ("_staff_route","index, destination","navigation",True),
  ("_static_service_path","from, to","navigation",True),
  ("_work_route_length","staff, staff_index, from, cell","navigation",True),
  ("_tick_autosave","delta","autosave",False),
  ("_update_ui","","ui_refresh",False),
  ("_update_people","","roster",False),
  ("_music_tick","delta","audio",False),
 ],
 MODEL:[
  ("tick","delta","model_tick",False),
  ("navigation_signature","","navigation",True),
  ("navigation_cells","","navigation",True),
  ("path_between","start, finish","navigation",True),
 ],
 DRAW:[
  ("_process","delta","renderer_update",False),
  ("_update_street_pedestrians","delta","street_motion",False),
  ("update_motion","delta","actor_motion",False),
  ("_draw","","draw_prepare",False),
 ],
 NATIVE_DRAW:[("_draw","","native_redraw",False)],
}
PIVOTS={
 MAIN: [("if not intro_active:\n\t\tif interaction!=null:","input_hud"),
        ("if not editing and not paused and not save_recovery_blocked:\n\t\tif model.first_guest_pending","main_dispatch")],
 DRAW: [("ground_art.prepare(game.model)","ground_draw"),
        ("# Exterior rear foliage sits behind the cafe shell","exterior_draw"),
        ("# All installed edges share the same local depth-sorted renderer.","depth_sort"),
        ("for e in entities:\n\t\tif e.type==","entity_draw"),
        ("if ground_occlusion_start>=0 and canvas_stream.active","draw_finish")],
}
MARKER="ll397_scopes.gd"
RESOURCE='preload("res://ll397_scopes.gd")'

def sha(data):
 return hashlib.sha256(data).hexdigest()

def isolate(raw,path):
 text=raw.decode().replace("\r\n","\n")
 for anchor,key in PIVOTS.get(path,[]):
  start="\n\t"+anchor
  if text.count(start)!=1:raise ValueError(f"missing/ambiguous marker anchor: {path} {key}")
  text=text.replace(start,f"\n\t{RESOURCE}.switch_to({KEYS.index(key)})"+start,1)
 for func,args,key,value in WRAPS[path]:
  prefix=f"func {func}("
  lines=[line for line in text.splitlines() if line.startswith(prefix)]
  if len(lines)!=1:raise ValueError(f"missing/ambiguous wrapper: {path} {func}")
  line=lines[0];nest=KEYS.index(key)
  ending=f"return _ll397_{func}({args})" if value else f"_ll397_{func}({args});return"
  extra=' or icon_kind!="" or not is_instance_valid(game)' if path==DRAW and func=="_draw" else ""
  result=(f"\tvar ll397_value=_ll397_{func}({args})\n\tll397_scope.leave()\n\treturn ll397_value" if value else
          f"\t_ll397_{func}({args})\n\tll397_scope.leave()")
  # Existing returns (including semicolon returns) stay inside the original
  # body; every wrapper closes the timed scope before giving behavior back.
  wrapper=f"{line}\n\tvar ll397_scope={RESOURCE}.current\n\tif ll397_scope==null or not ll397_scope.enabled or ll397_scope.is_top({nest}){extra}:\n\t\t{ending}\n\tll397_scope.enter({nest})\n{result}\n\n"+line.replace(prefix,f"func _ll397_{func}(",1)
  text=text.replace(line+"\n",wrapper+"\n",1)
 return text.encode()

def prepare(root,destination_guard):
 root=root.resolve(strict=True)
 if (root/".git").exists() or (root.parent/".git").exists():raise ValueError("stage must not be a checked-out source directory")
 if destination_guard.resolve()!=root:raise ValueError("explicit disposable stage required")
 paths={name:root/name for name in SOURCE}
 if any(p.resolve()!=p or not p.is_file() or p.stat().st_nlink!=1 for p in paths.values()):raise ValueError("wrong stage or symlinked source")
 originals={path:p.read_bytes() for path,p in paths.items()}
 if {path:sha(raw) for path,raw in originals.items()}!=SOURCE:raise ValueError("stage is not exact #397 product payload")
 marker=pathlib.Path(__file__).with_name(MARKER).read_bytes()
 expected_list="const KEYS="+json.dumps(KEYS,separators=(",",":"))
 if expected_list not in marker.decode():raise ValueError("catalog mismatch")
 if (root/MARKER).exists():raise ValueError("marker already exists")
 cfg=originals["project.godot"]
 if cfg.count(b"\n[display]\n")!=1 or re.search(rb"(?m)^\[autoload\]",cfg):raise ValueError("unexpected project autoload shape")
 changed={p:isolate(originals[p],p) for p in WRAPS}
 changed["project.godot"]=cfg.replace(b"\n[display]\n",b'\n[autoload]\n\nLL397Scopes="*res://ll397_scopes.gd"\n\n[display]\n')
 for path,data in changed.items():paths[path].write_bytes(data)
 (root/MARKER).write_bytes(marker)
 return {"source_sha":SCENARIO_HEAD,"source_tree":SCENARIO_TREE,
         "base_sha256":SOURCE,"diagnostic_sha256":{p:sha(data) for p,data in {**changed,MARKER:marker}.items()},"keys":KEYS}

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument("--project",required=True,type=pathlib.Path)
 parser.add_argument("--confirm-disposable-copy",required=True,type=pathlib.Path)
 args=parser.parse_args()
 print(json.dumps(prepare(args.project,args.confirm_disposable_copy),indent=2,sort_keys=True))

if __name__=="__main__":
 main()
