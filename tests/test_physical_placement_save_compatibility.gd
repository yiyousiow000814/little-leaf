extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
class TestMain extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():return true
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func write_fixture(path:String,data:Dictionary):
 var file=FileAccess.open(path,FileAccess.WRITE)
 file.store_string(JSON.stringify(data));file.close()
func _initialize():run.call_deferred()
func run():
 if not "saveguard" in OS.get_user_data_dir():quit(2);return
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 await process_frame
 game.model.service_snapshot=game._service_save_snapshot()
 var current="user://physical-current.json"
 check(game.model.save(current),"ordinary initialized staff layout saves with physical body validation")
 var data=JSON.parse_string(FileAccess.get_file_as_string(current))
 check(not data.runtime.service.staff.is_empty(),"fixture exercises actual staff positions and identities")
 var historical=data.duplicate(true)
 historical.version=13;historical.erase("layout_motion_format");historical.runtime.erase("layout_motion_format")
 historical.wall_format=1;historical.erase("shell_segment_format");historical.erase("shell_segment_products")
 var path="user://physical-v13.json";write_fixture(path,historical)
 var digest=FileAccess.get_sha256(path)
 var restored=Model.new()
 var loaded=restored.load_save(path)
 if not loaded:printerr("HISTORICAL_ERROR ",restored.last_error)
 check(loaded,"historical v13 ordinary staff layout remains readable")
 check(restored.coins==game.model.coins and restored.items==game.model.items,"historical import preserves wallet and item identities")
 var canonical=Model.new()
 check(canonical.load_save(current),"current staff snapshot loads for canonical comparison")
 check(JSON.stringify(restored.service_snapshot)==JSON.stringify(canonical.service_snapshot),"historical import preserves canonical staff jobs and body coordinates")
 check(FileAccess.get_sha256(path)==digest,"historical input bytes stay unchanged")
 var malformed=data.duplicate(true)
 var item=game.model.items[0]
 # Use the same vector representation as the saved service snapshot.
 var codec=preload("res://scripts/cafe_runtime_codec.gd").new()
 malformed.runtime.service.staff[0].pos=codec.encode(Vector2(float(item.x)+0.5,float(item.z)+0.5))
 malformed.runtime.service.staff[0].path=[];malformed.runtime.service.staff[0].index=0
 var bad="user://physical-body-invalid.json";write_fixture(bad,malformed)
 var bad_digest=FileAccess.get_sha256(bad)
 var wallet=restored.coins;var items=restored.items.duplicate(true);var service=JSON.stringify(restored.service_snapshot)
 check(not restored.load_save(bad),"solid furniture and actual staff body overlap rejects load")
 check(restored.last_error.contains("physical layout"),"body fixture reaches authoritative physical validation")
 check(restored.coins==wallet and restored.items==items and JSON.stringify(restored.service_snapshot)==service,"rejected body fixture does not replace current state")
 check(FileAccess.get_sha256(bad)==bad_digest,"rejected input bytes stay unchanged")
 game.queue_free();await process_frame
 print("PHYSICAL_PLACEMENT_SAVE_COMPATIBILITY_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
