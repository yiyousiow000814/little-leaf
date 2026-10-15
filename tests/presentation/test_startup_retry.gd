extends SceneTree
const WebSave=preload("res://scripts/persistence/cafe_web_save.gd")
const Model=preload("res://scripts/core/cafe_model.gd")
class FakeGame extends Node:
 const Model=preload("res://scripts/core/cafe_model.gd")
 var model=Model.new()
 var fresh_start=false
 var startup_save_source=""
 var startup_notice=""
 var paused=true
 var save_writes_suppressed=true
 var save_recovery_blocked=true
class RecoveryMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true
  assert(model.load_save("res://tests/fixtures/startup-retry-v15.json"),model.last_error)
 func _setup_music():pass
 func _music_tick(_delta):pass
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _init():call_deferred("run")
func homes(cafe):
 return cafe.staff_states.map(func(worker):return {"id":worker.idle_home_id,"cell":worker.idle_home_cell})
func check_idle_home_recovery():
 var cafe=RecoveryMain.new();cafe.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(cafe)
 cafe._refresh_idle_homes()
 var expected=homes(cafe)
 var saved=cafe._service_save_snapshot()
 var revision=cafe.model.revision;var count=cafe.staff_states.size()
 check(expected.map(func(home):return home.id)==[1,4,3,15],"synthetic fixture assigns all four role homes before recovery")
 check(cafe.idle_home_revision==revision and cafe.idle_home_count==count,"idle-home cache is warm before equal-revision replacement")
 for attempt in 2:
  var replacement=Model.new()
  check(replacement.load_save("res://tests/fixtures/startup-retry-v15.json"),"repeated recovery candidate validates")
  check(replacement.revision==revision and replacement.service_snapshot.staff.size()==count,"replacement matches cached revision and roster count")
  var old_node=cafe.staff_states[0].node
  var old_model=cafe.model
  cafe.model=replacement;cafe._resume_loaded_cafe()
  var dirty_generation=cafe.platform_dirty_generation
  old_model.changed.emit()
  check(cafe.platform_dirty_generation==dirty_generation,"obsolete model cannot dirty the recovered cafe")
  check(not old_model.meal_completed.is_connected(cafe._on_meal_completed),"obsolete model releases the earnings callback")
  cafe._connect_model_events();cafe._connect_model_events()
  cafe.model.changed.emit()
  check(cafe.platform_dirty_generation==dirty_generation+1,"repeated setup marks one dirty generation per live model change")
  check(cafe.model.meal_completed.get_connections().filter(func(connection):return connection.callable==cafe._on_meal_completed).size()==1,"repeated setup retains exactly one live earnings callback")
  check(cafe.staff_states[0].node!=old_node,"startup retry recreates staff identities")
  cafe._staff_idle_cell(0,[])
  check(homes(cafe)==expected,"first idle placement consumer rebuilds every role home after recovery")
  var restored=cafe._service_save_snapshot()
  check(restored.staff==saved.staff,"recovery preserves saved staff positions, routes, jobs and clocks")
  check(restored.staff.all(func(worker):return not worker.has("idle_home_id") and not worker.has("idle_home_cell")),"derived homes remain outside the saved staff format")
 # Snapshot restore also replaces the roster without replacing the model.
 cafe._restore_service_runtime();cafe._staff_idle_cell(0,[])
 check(homes(cafe)==expected,"same-model snapshot restore rebuilds equal-count roster homes")
 # Empty-snapshot recovery can consume homes during fresh placement itself.
 cafe.model.service_snapshot={};cafe.fresh_start=true;cafe._resume_loaded_cafe()
 var dirty_generation=cafe.platform_dirty_generation
 cafe.model.changed.emit()
 check(cafe.platform_dirty_generation==dirty_generation+1,"same-model recovery retains exactly one dirty callback")
 check(homes(cafe)==expected,"empty-snapshot recovery invalidates before fresh staff placement")
 check(cafe.staff_states.all(func(worker):return worker.pos==cafe.model.cell_center(worker.idle_home_cell)),"fresh placement uses rebuilt homes before its first frame")
 check(cafe.save_writes_suppressed,"recovery regression suppresses ordinary saves")
 for tween in get_processed_tweens():tween.kill()
 cafe.queue_free();await process_frame;await process_frame
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
 await check_idle_home_recovery()
 print("STARTUP_RETRY_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
