extends SceneTree
class GeneratedMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
  model.coins=10000
  assert(model.place("table_set",3,6,0),model.last_error)
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var game=GeneratedMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 game.model._spawn_customer();game.model._spawn_customer()
 var concurrent=false
 for tick in range(4000):
  game.model._arrival_elapsed=0.0;game._tick_live_service(.05);game._animate_staff(.05)
  var cook={};var waiter={}
  for staff in game.staff_states:
   if staff.job_kind=="cook":cook=staff
   if staff.job_kind=="deliver_meal" and staff.job_step==1:waiter=staff
  if not cook.is_empty() and not waiter.is_empty() and cook.job_guest_id!=waiter.job_guest_id:
   var carried=game.service_guests[int(waiter.job_guest_id)]
   if carried.plate_owner=="staff" and waiter.art_action=="carrying_plate":
    check(cook.station_id==waiter.station_id,"next cook reuses the same stove during delivery")
    check(game.service_guests[int(cook.job_guest_id)].plate_owner=="kitchen","new cooking owns a separate unprepared meal")
    concurrent=true;break
 check(concurrent,"real second chef job starts while waiter walks first plate to table")
 print("STOVE_OUTPUT_REUSE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame
 quit(0 if failures.is_empty() else 1)
