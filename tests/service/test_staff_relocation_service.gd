extends SceneTree
const AudioDrain = preload("res://tests/fixtures/audio_mixer_drain.gd")
const Codec=preload("res://scripts/persistence/cafe_runtime_codec.gd")
const Model=preload("res://scripts/core/cafe_model.gd")
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
 var paid_visits={};var abandoned_visits={};var duplicate_payments=[]
 cafe.model.meal_completed.connect(func(id,amount):
  if paid_visits.has(id):duplicate_payments.append(id)
  paid_visits[id]=amount)
 for player in cafe.audio_players.values():player.stop()
 check(not cafe.save_recovery_blocked and cafe.model.dining_sets.size()==4,"fully synthetic four-table fixture initializes")
 var actors=cafe.interaction._staff_positions()
 # Two admitted cohorts now walk from the fixed street ends at normal speed.
 for tick in 7200:
  cafe._tick_live_service(1.0/30.0);cafe._animate_staff(1.0/30.0);cafe.animation_time+=1.0/30.0
  for guest in cafe.model.customers:
   if guest.get("meal_abandoned",false):abandoned_visits[int(guest.id)]=true
  if cafe.model.customers.size()==4 and cafe.model.customers.all(func(g):return cafe.model._customer_admitted(g)):break
  if tick%120==0:await process_frame
 check(cafe.model.customers.size()==4,"four actual synthetic visits arrive")
 cafe.model.set_operating_open(false)
 check(cafe.model.customers.all(func(g):return not g.get("withdrawn",false)),"all visits are admitted before closing")
 var before_coins=cafe.model.coins;var before_wages=cafe.model.total_wages_paid;var before_earned=cafe.model.total_earned
 var refusal_seen=false;var done=false;var ticks=0;var payload_seen=""
 for tick in 18000:
  cafe._tick_live_service(1.0/30.0);cafe._animate_staff(1.0/30.0);cafe.animation_time+=1.0/30.0;ticks=tick+1
  for guest in cafe.model.customers:
   if guest.get("meal_abandoned",false):abandoned_visits[int(guest.id)]=true
  if not refusal_seen:
   for index in cafe.staff_states.size():
    var worker=cafe.staff_states[index];var payload=cafe._staff_payload(worker,index)
    if worker.job_kind=="" or payload=="none":continue
    var before=ledger(cafe)
    var cell=Vector2i(worker.pos.floor());actors=cafe.interaction._staff_positions()
    # A held payload remains owned by its actual worker. A new furnishing
    # cannot turn physical collision into a hypothetical relocation.
    if not cafe.model.is_floor_owned(cell) or cafe.model.items.any(func(item):return Vector2i(item.x,item.z)==cell):continue
    var field=cafe.interaction.edit_plan
    var receipt=field.prepare(cafe.model,"plant",-1,0,cell,actors)
    check(not receipt.ok and not receipt.physical_ok,"carrying body refuses overlapping placement")
    check(not field._plan_result.has("staff_positions"),"body refusal creates no relocation plan")
    var old_pos=worker.pos;var wallet=cafe.model.coins;var old_items=cafe.model.items.duplicate(true)
    cafe.editing=true
    check(not field.commit(cafe.model,receipt,actors),"overlap cannot publish a purchase or worker transition")
    check(worker.pos==old_pos and cafe._staff_payload(worker,index)==payload,"carried payload remains with the same unmoved worker")
    check(cafe.model.coins==wallet and cafe.model.items==old_items,"body refusal preserves wallet and furniture")
    check(cafe.model.layout_access_issues().is_empty(),"refusal preserves every service station")
    check(ledger(cafe)==before,"jobs, progress clocks and complete ownership ledger survive")
    cafe.editing=false;refusal_seen=true;payload_seen=payload
    cafe.model.service_snapshot=cafe._service_save_snapshot()
    var path="user://staff-body-refusal-roundtrip.json"
    check(cafe.model.save(path),"unchanged active runtime still saves: "+cafe.model.last_error)
    var loaded=Model.new()
    check(loaded.load_save(path),"unchanged carrying runtime restores: "+loaded.last_error)
    if not loaded.service_snapshot.is_empty():
     var points=loaded.service_snapshot.staff.map(func(staff):return staff.pos)
     check(loaded._furniture_body_error(loaded.items,points)=="","restored actual staff bodies remain clear")
    break
  if tick%120==0:await process_frame
  if cafe.model.customers.is_empty() and cafe.floor_tasks.messes.is_empty() and cafe.staff_states.all(func(s):return s.job_kind==""):done=true;break
 check(refusal_seen,"real carrying-worker collision refusal was exercised")
 check(done and cafe.model.served+abandoned_visits.size()==4 and cafe.model.total_cleaned==4,"all four visits settle or depart unpaid and release clean tables after rejected placement")
 check(duplicate_payments.is_empty() and paid_visits.size()==cafe.model.served and abandoned_visits.keys().all(func(id):return not paid_visits.has(id)) and cafe.model.total_earned==paid_visits.size()*cafe.Model.MEAL_PAYMENT,"exactly one payment per served diner and none for abandonment")
 check(cafe.model.coins==before_coins+cafe.model.total_earned-before_earned-(cafe.model.total_wages_paid-before_wages),"wallet changes only for real service and wages; refused furniture never charges")
 var report={"checks":checks,"failures":failures,"payload":payload_seen,"seconds":ticks/30.0,"served":cafe.model.served,"cleaned":cafe.model.total_cleaned}
 for tween in get_processed_tweens():tween.kill()
 cafe.queue_free();await process_frame
 var audio_drain = await AudioDrain.wait_for_mixer_cycles(self)
 check(audio_drain.ok, "audio teardown observes two mixer cycles within 1s")
 print("AUDIO_TEARDOWN_RESULT ", JSON.stringify(audio_drain))
 report.checks=checks;report.failures=failures
 print("STAFF_RELOCATION_SERVICE_RESULT ",JSON.stringify(report))
 quit(0 if failures.is_empty() else 1)
