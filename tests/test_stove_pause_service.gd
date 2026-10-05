extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
class GeneratedMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
  model.coins=100000
  for at in [Vector2i(6,5),Vector2i(9,5),Vector2i(3,6)]:assert(model.place("table_set",at.x,at.y,0),model.last_error)
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var game=GeneratedMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 check(not game.save_recovery_blocked and game.model.dining_sets.size()==4,"fresh public default plus explicit four-table fixture starts")
 check(game.model.place("stove",5,1),"second accessible stove places")
 game.model.cooks=2;game.model.duty_targets.chef=2;game.model.duty_counts.chef=2;game._update_people();game._sync_staff_duty()
 game.model._arrival_elapsed=-1000000
 var blocked_worker={};var held=[];var blocker_id=-1;var blocked_ticks=0;var restored=false;var done=false
 var other_completed=false;var stationary=0;var last=Vector2.INF
 for tick in 15000:
  if game.model._next_customer_id<=4:game.model._spawn_customer()
  if game.model._next_customer_id==5 and game.model.customers.all(func(g):return bool(g.admitted)):game.model.set_operating_open(false)
  game._tick_live_service(1.0/30.0);game._animate_staff(1.0/30.0);game.animation_time+=1.0/30.0
  if blocked_worker.is_empty():
   for staff in game.staff_states:
    if staff.job_kind!="cook" or int(staff.job_step)!=1 or float(staff.job_elapsed)<.5:continue
    var station=game.model.get_item(int(staff.station_id));var face=game.model.workface_cell(station)
    # The independent staff-placement candidate owns transactional relocation.
    # This service-only fixture moves the worker onto safe floor before editing.
    check(game._staff_walkable(Vector2i(2,7)) and not game.model.path_between(Vector2i(staff.pos.floor()),Vector2i(2,7)).is_empty(),"synthetic step-aside tile is clear and reachable")
    staff.pos=Vector2(2.5,7.5);staff.path=[];staff.index=0;staff.destination=Vector2i(-100,-100)
    check(game.model.place("plant",face.x,face.y),"blocking an in-progress stove is allowed")
    blocker_id=int(game.model.items[-1].id);blocked_worker=staff
    held=[staff.job_kind,staff.job_guest_id,staff.job_token,staff.job_step,staff.job_elapsed,staff.station_id]
    game._rebuild_furniture();game.idle_home_revision=-1
    print("HELD ",held);break
  elif not restored:
   blocked_ticks+=1
   if blocked_ticks==300:
    game.model.service_snapshot=game._service_save_snapshot()
    check(game.model.save("user://paused-stove.json"),"in-progress blocked meal saves")
    var restored_model=Model.new()
    check(restored_model.load_save("user://paused-stove.json"),"in-progress blocked meal reloads")
    var saved_worker={}
    for worker in restored_model.service_snapshot.staff:
     if int(worker.job_guest_id)==int(held[1]) and str(worker.job_kind)=="cook":saved_worker=worker;break
    check(not saved_worker.is_empty() and saved_worker.job_elapsed==held[4] and saved_worker.station_id==held[5],"save roundtrip preserves chef meal progress and station")
   if blocked_ticks%300==0:
    check(held==[blocked_worker.job_kind,blocked_worker.job_guest_id,blocked_worker.job_token,blocked_worker.job_step,blocked_worker.job_elapsed,blocked_worker.station_id],"blocked meal progress/identity preserved "+str(blocked_ticks))
    check(blocked_worker.art_action!="blocked" and game.workface_guidance.blocked_station(game).get("kind","")!="stove","play has no stove warning bubble/locate button")
   if blocked_ticks>120:
    if blocked_worker.pos.distance_to(last)<.0001:stationary+=1
    last=blocked_worker.pos
   for id in game.service_guests:
    var record=game.service_guests[id]
    if id!=int(held[1]) and (record.meal_ready or record.meal_done):other_completed=true
   if blocked_ticks>=2700:
    check(other_completed,"other chef/stove continues meals during blockage")
    check(stationary>2400,"blocked worker settles without repeated walking loop")
    var repaired=game.model.remove(blocker_id)
    check(repaired,"clear stove without cancelling meal: "+game.model.last_error)
    if not repaired:break
    game._rebuild_furniture();restored=true
  elif game.model._next_customer_id==5 and game.model.customers.is_empty() and game.floor_tasks.messes.is_empty() and game.staff_states.all(func(s):return s.job_kind==""):
   done=true;break
  if tick%180==0:await process_frame
 var state=[]
 for w in game.staff_states:state.append({"role":w.role,"job":w.job_kind,"step":w.job_step,"elapsed":w.job_elapsed,"pos":str(w.pos),"station":w.station_id,"reason":w.blocked_reason,"guest":w.job_guest_id})
 print("FINAL_WORKERS ",JSON.stringify(state))
 print("FINAL_GUESTS ",JSON.stringify(game.model.customers))
 check(not blocked_worker.is_empty() and restored,"active blocking and recovery exercised")
 check(done and game.model.served==4 and game.model.total_cleaned==4,"all four visits resume, pay and clean exactly once")
 check(game.model.total_earned==1000,"all expected payments occur exactly once")
 print("STOVE_PAUSE_SERVICE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"blocked_seconds":blocked_ticks/30.0,"other_meals_continued":other_completed,"served":game.model.served,"cleaned":game.model.total_cleaned}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
