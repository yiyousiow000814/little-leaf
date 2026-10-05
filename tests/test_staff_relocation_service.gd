extends SceneTree
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
const Model=preload("res://scripts/cafe_model.gd")
class LoadedMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true
  fresh_start=true;MinimalStart.apply(model);model.coins=100000
  for spec in [[5,6,0],[9,6,0],[2,7,0]]:
   assert(model.place("table_set",spec[0],spec[1],spec[2]),model.last_error)
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func ledger(cafe):
 var snapshot=cafe._service_save_snapshot()
 for worker in snapshot.staff:
  for key in ["pos","destination","path","index","blocked_time","stalled_time"]:worker.erase(key)
 return Codec.new().encode(snapshot)
func run():
 var cafe=LoadedMain.new();root.add_child(cafe);cafe.set_process(false);cafe.illustration.set_process(false)
 for player in cafe.audio_players.values():player.stop()
 check(not cafe.save_recovery_blocked and cafe.model.dining_sets.size()==4,"fully synthetic four-table fixture initializes")
 var actors=cafe.interaction._staff_positions()
 for tick in 3600:
  cafe._tick_live_service(1.0/30.0);cafe._animate_staff(1.0/30.0);cafe.animation_time+=1.0/30.0
  if cafe.model.customers.size()==4 and cafe.model.customers.all(func(g):return cafe.model._customer_admitted(g)):break
  if tick%120==0:await process_frame
 check(cafe.model.customers.size()==4,"four actual synthetic visits arrive")
 cafe.model.set_operating_open(false)
 check(cafe.model.customers.all(func(g):return not g.get("withdrawn",false)),"all visits are admitted before closing")
 var before_coins=cafe.model.coins;var before_wages=cafe.model.total_wages_paid
 var relocated=false;var done=false;var ticks=0;var payload_seen=""
 for tick in 18000:
  cafe._tick_live_service(1.0/30.0);cafe._animate_staff(1.0/30.0);cafe.animation_time+=1.0/30.0;ticks=tick+1
  if not relocated:
   for index in cafe.staff_states.size():
    var worker=cafe.staff_states[index];var payload=cafe._staff_payload(worker,index)
    if worker.job_kind=="" or payload=="none":continue
    var before=ledger(cafe)
    var cell=Vector2i(worker.pos.floor());actors=cafe.interaction._staff_positions()
    # This fixture exercises repathing while service continues. Legacy stove
    # blockage and recovery have their own pause-service test.
    if not cafe.model.placement_access_issues("plant",cell.x,cell.y).is_empty():continue
    var field=cafe.interaction.edit_plan
    var receipt=field.prepare(cafe.model,"plant",-1,0,cell,actors)
    if not receipt.ok or not field._plan_result.has("staff_positions") or field._plan_result.staff_positions[index]==worker.pos:continue
    var old_pos=worker.pos
    cafe.editing=true
    var success=field.commit(cafe.model,receipt,actors,cafe._apply_edit_staff_positions)
    check(success,"placement and carrying worker relocate atomically")
    if not success:printerr("COMMIT_ERROR ",cafe.model.last_error)
    check(worker.pos!=old_pos and cafe._staff_payload(worker,index)==payload,"carried payload remains with same worker")
    check(cafe.model.layout_access_issues().is_empty(),"relocation fixture keeps every service station usable")
    check(ledger(cafe)==before,"jobs, progress clocks and complete ownership ledger survive")
    cafe._rebuild_furniture();cafe.editing=false;relocated=true;payload_seen=payload
    cafe.model.service_snapshot=cafe._service_save_snapshot()
    var path="user://staff-relocation-roundtrip.json"
    check(cafe.model.save(path),"joint edit produces a valid runtime save")
    var loaded=Model.new()
    check(loaded.load_save(path),"saved relocated staff and furniture restore")
    if not loaded.service_snapshot.is_empty():
     for staff in loaded.service_snapshot.staff:check(field.StaffRelocation.point_clear(loaded,staff.pos,loaded.items),"restored staff has no furniture overlap")
    break
  if tick%120==0:await process_frame
  if cafe.model.customers.is_empty() and cafe.floor_tasks.messes.is_empty() and cafe.staff_states.all(func(s):return s.job_kind==""):done=true;break
 check(relocated,"real carrying-worker relocation was exercised")
 check(done and cafe.model.served==4 and cafe.model.total_cleaned==4,"all four generated visits finish and clean exactly once after repath")
 check(cafe.model.total_earned==1000,"no duplicate payments")
 check(cafe.model.coins==before_coins+1000-(cafe.model.total_wages_paid-before_wages)-cafe.model.price_of("plant"),"wallet changes only for real service, wages and one plant")
 print("STAFF_RELOCATION_SERVICE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"payload":payload_seen,"seconds":ticks/30.0,"served":cafe.model.served,"cleaned":cafe.model.total_cleaned}))
 for tween in get_processed_tweens():tween.kill()
 cafe.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
