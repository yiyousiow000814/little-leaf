extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
class GeneratedMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var game=GeneratedMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 check(game.model.count_kind("counter")==0,"fresh public start contains no pass counter")
 check(not game.model.can_place("counter",6,2),"new counter purchase unavailable")
 check(game.model.catalog.filter(func(i):return i.kind=="counter")[0].hidden,"legacy counter hidden from shop")
 game.model._spawn_customer()
 var output_seen=false;var pickup_seen=false;var table_seen=false;var blocked_checked=false
 var record={};var blocker_id=-1
 for tick in 4000:
  game.model._arrival_elapsed=0.0;game._tick_live_service(.1);game._animate_staff(.1);game.animation_time+=.1
  if not game.service_guests.is_empty():record=game.service_guests.values()[0]
  if not record.is_empty() and record.plate_owner=="station" and not output_seen:
   output_seen=true
   var id=int(record.plate_target_id)
   check(id==int(record.meal_station_id) and game.model.get_item(id).kind=="stove","finished plate belongs to its cooking stove")
   check(record.meal_pass_id==-1 and not record.pass_reserved,"new meal never reserves a counter")
   check(game._item_service_locked(id),"occupied output cannot move or be sold")
   check(game._service_station("stove",Vector2i(3,2),-1).is_empty(),"one occupied stove cannot accept another meal")
   game.model.service_snapshot=game._service_save_snapshot()
   check(game.model.save("user://direct-output.json"),"ready output saves: "+game.model.last_error)
   var restored=Model.new()
   check(restored.load_save("user://direct-output.json"),"ready output reloads: "+restored.last_error)
   if not restored.service_snapshot.is_empty():
    var saved=restored.service_snapshot.records[0]
    check(saved.plate_owner=="station" and saved.plate_target_id==id,"reload preserves exact ready output owner")
   check(game.model.load_save("user://direct-output.json"),"live generated model reloads ready output")
   game._restore_service_runtime();record=game.service_guests.values()[0]
   check(record.plate_owner=="station" and record.plate_target_id==id,"live restore preserves output before service resumes")
   var face=game.model.workface_cell(game.model.get_item(id))
   blocker_id=game.model._next_item_id;game.model._next_item_id+=1
   game.model.items.append({"id":blocker_id,"kind":"plant","x":face.x,"z":face.y,"rot":0});game.model._notify()
   var owner=[record.plate_owner,record.plate_target_id,record.token]
   for blocked_tick in 30:game._animate_staff(.1)
   check(owner==[record.plate_owner,record.plate_target_id,record.token],"blocked pickup retains one physical dish and order identity")
   blocked_checked=true
   game.model.items=game.model.items.filter(func(i):return int(i.id)!=blocker_id);game.model._notify()
  if not record.is_empty() and record.plate_owner=="staff" and record.meal_ready:pickup_seen=true
  if not record.is_empty() and record.plate_owner=="table":table_seen=true
  if game.model.served==1:break
 check(output_seen and pickup_seen and table_seen,"visible ownership sequence stove to waiter to table")
 check(blocked_checked and game.model.served==1,"service recovers after route reopened")
 var legacy=Model.new();legacy.reset_new()
 var counter=legacy.items.filter(func(i):return i.kind=="counter")[0]
 var before=legacy.coins
 check(legacy.can_place("counter",6,2,int(counter.id)),"owned legacy counter remains movable")
 check(legacy.coins==before and legacy.count_kind("counter")==2,"legacy purchased assets and coins preserved")
 var old_record={"meal_station_id":1,"meal_pass_id":int(counter.id),"pass_reserved":true,"plate_owner":"staff"}
 check(game.ChefPickup.output_id(old_record)==int(counter.id),"in-flight legacy reservation finishes at its original counter")
 game.ChefPickup.deposit(old_record,counter)
 check(old_record.plate_owner=="counter","legacy counter ownership remains readable")
 print("DIRECT_CHEF_PICKUP_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame
 quit(0 if failures.is_empty() else 1)
