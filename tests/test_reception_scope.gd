extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Review=preload("res://scripts/cafe_reception_review.gd")
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label)
func _initialize():run.call_deferred()
func run():
 var data=Review.canonical(OS.get_user_data_dir())
 check("saveguard" in data and "/little leaf cafe/disposable/" in data,"generated nested ordinary-name fixture")
 check(not Review.scope_allowed(),"ordinary profile ancestor refuses scope")
 var m=Model.new();m.coins=777
 check(not m.enable_reception_review() and not m.reception_review_enabled and m.coins==777,"enable refuses before mode/state mutation")
 var path="user://nested-scope.json";FileAccess.open(path,FileAccess.WRITE).store_string("synthetic control only");var hash=FileAccess.get_sha256(path)
 # Exercise each I/O guard even with a manually set test-only active mode.
 m.reception_review_enabled=true
 check(not Review.path_allowed(path),"path rechecks forbidden ancestor")
 check(not m.save_reception(path) and FileAccess.get_sha256(path)==hash and not FileAccess.file_exists(path+".tmp"),"writer refuses before staging or target changes")
 check(not m.load_reception(path) and m.coins==777 and m.reception_review_enabled and FileAccess.get_sha256(path)==hash,"reader refuses before file/state changes")
 print("RECEPTION_SCOPE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
