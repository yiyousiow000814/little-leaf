extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Parking=preload("res://scripts/cafe_parking.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
class TestMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
var checks=0
var failures=[]
var roundtrips=0
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func same(a,b)->bool:
 if (a is int or a is float) and (b is int or b is float):return absf(float(a)-float(b))<1e-8
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not same(a[key],b[key]):return false
  return true
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for i in range(a.size()):
   if not same(a[i],b[i]):return false
  return true
 return a==b
func make_game():
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 # This funded service fixture reserves a car directly, bypassing the normal
 # arrival dispatcher. It represents existing progress, not a first visit.
 game.model.first_guest_pending=false;game.model.first_guest_start=Vector2.INF
 game.model.coins=10000;game.model.begin_decoration_session();check(game.model.buy_parking(),"Main purchases parking");game.model.finish_decoration_session();check(Parking.reserve(game.model),"Main reserves car guest")
 return game
func save_roundtrip(game,label:String):
 game.model.service_snapshot=game._service_save_snapshot()
 var expected=game.model.service_snapshot.duplicate(true);var guests=game.model.customers.duplicate(true);var visits=game.model.parking_visits.duplicate(true);var queue=game.model.outside_queue.duplicate(true)
 var path="user://parking-service-"+label+".json"
 var saved=game.model.save(path);check(saved,label+" full Main snapshot saves: "+game.model.last_error)
 if not saved:return
 var bytes=FileAccess.get_sha256(path);var restored=Model.new();var loaded=restored.load_save(path);check(loaded,label+" reload accepts: "+restored.last_error)
 if not loaded:return
 check(bytes==FileAccess.get_sha256(path),label+" source unchanged")
 check(same(restored.service_snapshot,expected) and same(restored.customers,guests) and same(restored.parking_visits,visits) and same(restored.outside_queue,queue),label+" all runtime clocks/owners/positions preserved")
 game.model=restored;game._restore_service_runtime();roundtrips+=1
func tick(game,staff=true):
 game.model._arrival_elapsed=0.0;game._tick_live_service(.1)
 if staff:game._animate_staff(.1)
func finish(game):
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 game.queue_free()
func run():
 root.size=Vector2i(1360,880)
 check(OS.get_environment("XDG_DATA_HOME")!="" and OS.get_user_data_dir().begins_with(OS.get_environment("XDG_DATA_HOME")),"synthetic profile only")
 var game=make_game()
 var before=Codec.new().encode(game.model.parking_visits);game.paused=true;game._process(2)
 check(same(before,Codec.new().encode(game.model.parking_visits)),"pause freezes car trip")
 game.paused=false;game.editing=true;game._process(2)
 check(same(before,Codec.new().encode(game.model.parking_visits)),"Decorate freezes car trip")
 game.editing=false;game.browser_suspended=true;game._process(2)
 check(same(before,Codec.new().encode(game.model.parking_visits)),"background suspension freezes car trip")
 game.browser_suspended=false;game._resume_frame=-1;game.speed=2.0;game._process(.1)
 check(is_equal_approx(game.model.parking_visits[0].car_position.distance_to(Parking.CAR_START),Parking.CAR_SPEED*.2),"2x advances authoritative car by simulation time: "+str(game.model.parking_visits[0].car_position)+" paused="+str(game.paused)+" intro="+str(game.cafe_intro.active)+" blocked="+str(game.save_recovery_blocked)+" small="+str(game.compact_ui.viewport_too_small))
 game.speed=1.0;save_roundtrip(game,"driving")
 check(game.service_guests.is_empty() and game.floor_tasks.walks.is_empty(),"inbound car creates no indoor service/litter record")
 var visited={}
 for frame in range(4500):
  tick(game)
  if not game.model.parking_visits.is_empty():
   var phase=str(game.model.parking_visits[0].phase)
   if not visited.has(phase):
    visited[phase]=true;save_roundtrip(game,"paid-"+phase)
   var ids={};var unique=true
   for guest in game.model.visual_customers():
    if ids.has(int(guest.id)):unique=false
    ids[int(guest.id)]=true
   check(unique,"one physical driver identity per tick")
  if game.model.parking_visits.is_empty() and game.model.customers.is_empty():break
 check(game.model.parking_visits.is_empty() and game.model.customers.is_empty(),"cashier meal, cleanup, return and car exit finish")
 check(game.model.served==1 and game.model.total_earned==Model.MEAL_PAYMENT,"cashier meal settles exactly once: served="+str(game.model.served)+" earned="+str(game.model.total_earned))
 check(visited.has("walking_return") and visited.has("car_departing"),"cashier departure uses parking return chain")
 save_roundtrip(game,"paid-finished")
 finish(game);await process_frame;await process_frame
 # Real seated patience abort, saved midway through every return ownership.
 game=make_game()
 for frame in range(1500):
  tick(game,false)
  if not game.model.customers.is_empty() and game.model.customers[0].seated:break
 check(game.model.customers.size()==1 and game.model.customers[0].seated,"real parking customer reaches table")
 var record=game.service_guests[int(game.model.customers[0].id)]
 check(record.meal_wait_seconds==0.0,"car/queue/entry travel does not consume seated patience")
 game._advance_meal_wait(60);game._advance_meal_wait(60);game._resolve_meal_deadlines()
 check(record.guest.meal_abandoned and not record.guest.paid,"unfinished car guest abandons at normal120s")
 save_roundtrip(game,"aborted-dismount")
 visited={}
 for frame in range(2500):
  tick(game)
  if not game.model.parking_visits.is_empty():
   var phase=str(game.model.parking_visits[0].phase)
   if not visited.has(phase):visited[phase]=true;save_roundtrip(game,"aborted-"+phase)
  if game.model.parking_visits.is_empty() and game.model.customers.is_empty():break
 check(game.model.parking_visits.is_empty() and game.model.customers.is_empty(),"aborted service cleanup and parking release finish")
 check(game.model.served==0 and game.model.total_earned==0,"aborted Main service awards no payment")
 save_roundtrip(game,"aborted-finished")
 finish(game)
 for tween in get_processed_tweens():tween.kill()
 await process_frame;await process_frame
 print("PARKING_SERVICE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"full_main_roundtrips":roundtrips,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
