extends SceneTree
const WebSave=preload("res://scripts/cafe_web_save.gd")
const Model=preload("res://scripts/cafe_model.gd")
class FakeGame extends Node:
 const Model=preload("res://scripts/cafe_model.gd")
 var model=Model.new()
 var fresh_start=false
 var startup_save_source=""
 var startup_notice=""
 var paused=true
 var save_writes_suppressed=true
 var save_recovery_blocked=true
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _init():call_deferred("run")
func run():
 var game=FakeGame.new();root.add_child(game)
 var controller=WebSave.new(game)
 var payload=FileAccess.get_file_as_string("res://tests/fixtures/startup-retry-v15.json")
 var bad=JSON.parse_string(payload);bad.items[0].x=9999
 var old=game.model
 check(not controller._accept_boot({"ok":true,"source":"authority","profileId":"synthetic","revision":1,"payload":JSON.stringify(bad)}),"native validator rejects invalid layout")
 check(game.model==old and game.model.coins==1200,"failed candidate cannot replace placeholder model")
 check(not controller.ready and game.save_writes_suppressed and game.save_recovery_blocked,"failed candidate cannot enable writes")
 check(controller.startup_error!="","native rejection retains diagnostic")
 check(controller._accept_boot({"ok":true,"source":"authority","profileId":"synthetic","revision":1,"payload":payload}),"valid authority accepts only after native validation")
 check(game.model!=old and game.model.coins==42000,"validated candidate restores wallet and model")
 check(controller.ready and not game.save_writes_suppressed and not game.save_recovery_blocked,"valid authority restores guarded writes")
 check(controller.revision==1 and controller.profile_id=="synthetic","loaded identity and revision retained")
 check(controller.startup_error=="" and not game.paused,"successful retry clears startup failure")
 controller.startup_error="";controller.retry_startup()
 check(not controller.retrying,"startup retry cannot discard edits after a loaded save conflict")
 print("STARTUP_RETRY_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
