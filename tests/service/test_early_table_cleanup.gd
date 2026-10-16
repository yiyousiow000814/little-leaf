extends SceneTree
const Main=preload("res://scripts/main.gd")
const Checkout=preload("res://scripts/gameplay/cafe_checkout.gd")
const Codec=preload("res://scripts/persistence/cafe_runtime_codec.gd")
var checks=0
var failures=[]
var evidence=[]
var snapshots={}
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func worker(g,role:String)->Dictionary:
 for staff in g.staff_states:
  if staff.role==role:return staff
 return {}
func fixture():
 var g=Main.new();g.save_writes_suppressed=true;g.MinimalStart.apply(g.model)
 g.model.first_guest_pending=false;g.model._spawn_customer();g.model.operating_open=false
 check(g.model.customers.size()==1,"generated public layout admits one visit")
 g._update_people()
 var guest=g.model.customers[0];var chair=g.model.get_item(int(guest.chair_id))
 guest.phase="eating";guest.x=chair.x+.5;guest.z=chair.z+.5;guest.seated=true;guest.admitted=true
 guest.elapsed=25.0;guest.duration=25.0;guest.route=[];guest.route_index=0;guest.waiting=false;guest.exterior_exit=false
 g._sync_service_guests()
 # Generated reachable layout gives the waiter a nearby sink while the
 # cashier must walk from the far corner. No worker or payment clock is frozen.
 worker(g,"waiter").pos=Vector2(4.5,3.5)
 worker(g,"cashier").pos=Vector2(11.5,8.5)
 for item in g.model.items:
  if item.kind=="sink":item.x=4;item.z=2
 g.model.revision+=1;g.model.first_guest_pending=false
 return g
func release(g):
 g.people.free();g.ui.free();g.free()
func advance(g,seconds:float):
 for tick in range(roundi(seconds/.05)):
  g._tick_live_service(.05);g._animate_staff(.05);g.animation_time+=.05
func runtime(g)->Dictionary:
 return {"customers":g.model.customers.duplicate(true),"service":g._service_save_snapshot(),"next_customer_id":g.model._next_customer_id,"arrival_elapsed":g.model._arrival_elapsed,"walking_customer_id":g.model._walking_customer_id,"next_checkout_ticket":g.model.next_checkout_ticket,"checkout_format":g.SaveContract.CHECKOUT_FORMAT,"layout_motion_format":g.SaveContract.LAYOUT_MOTION_FORMAT}
func valid(g,state:Dictionary,extra_waiters:int=0)->Dictionary:
 var staffing=g.model.staff_roster();var duty=g.model.duty_counts.duplicate()
 staffing.waiter+=extra_waiters;duty.waiter+=extra_waiters
 return Codec.new().validate(Codec.new().encode(state),g.model.items,g.model.cooks,g.model.PHASES,g.model.SAVE_VERSION,staffing,duty)
func save_reload(g,label:String)->bool:
 var path="user://early-"+label+".json"
 var before=g._service_save_snapshot();var guest_before=g.model.customers[0].duplicate(true)
 var financial=[g.model.coins,g.model.served,g.model.total_earned,g.model.next_checkout_ticket]
 g.model.service_snapshot=before
 var ok=g.model.save(path)
 check(ok,label+" save accepted: "+g.model.last_error)
 if not ok:return false
 var digest=FileAccess.get_sha256(path)
 ok=g.model.load_save(path);check(ok,label+" reload accepted: "+g.model.last_error)
 if not ok:return false
 g._restore_service_runtime()
 var after=g._service_save_snapshot();var guest=g.model.customers[0]
 check(financial==[g.model.coins,g.model.served,g.model.total_earned,g.model.next_checkout_ticket],label+" preserves money, debt and ticket sequence")
 check(guest.id==guest_before.id and guest.table_id==guest_before.table_id and guest.chair_id==guest_before.chair_id and guest.checkout_ticket==guest_before.checkout_ticket and guest.checkout_token==guest_before.checkout_token and guest.paid==guest_before.paid,label+" preserves guest, booking, payment and token")
 var same_jobs=before.records[0].token==after.records[0].token and before.staff.size()==after.staff.size()
 for i in before.staff.size():
  var a=before.staff[i];var b=after.staff[i]
  same_jobs=same_jobs and a.job_kind==b.job_kind and int(a.job_guest_id)==int(b.job_guest_id) and int(a.job_token)==int(b.job_token) and int(a.job_step)==int(b.job_step) and is_equal_approx(a.job_elapsed,b.job_elapsed) and a.pos.distance_to(b.pos)<.00001
 check(same_jobs,label+" preserves jobs, custody identities, progress and positions")
 snapshots[label]=runtime(g)
 check(FileAccess.get_sha256(path)==digest,label+" readback leaves source save unchanged")
 return true
func _initialize():run.call_deferred()
func run():
 var g=fixture();var guest=g.model.customers[0];var waiter=worker(g,"waiter")
 Checkout.finish_meal(g.model,guest)
 g._assign_service_job(waiter,g.staff_states.find(waiter))
 check(waiter.job_kind=="","seated checkout overflow does not clear table")
 var departed=false
 for tick in range(300):
  g._tick_live_service(.05)
  if not guest.seated and not guest.dismounting:
   departed=true;break
 check(departed and guest.phase in ["checkout_walk","checkout_wait"] and not guest.paid,"actual chair dismount precedes unpaid checkout")
 var token=g.service_guests[int(guest.id)].token
 var old_state=runtime(g);old_state.service.version=5
 check(valid(g,old_state).ok,"unchanged service5 unpaid checkout remains readable")
 guest.mobility={"kind":"to_assigned_seat"}
 g._assign_service_job(waiter,g.staff_states.find(waiter))
 check(waiter.job_kind=="","seat-relocation motion does not begin early cleanup")
 guest.mobility={}
 check(not g._cleanup_ready(guest),"checkout eligibility does not broaden cleaner floor jobs")
 g._assign_service_job(waiter,g.staff_states.find(waiter))
 check(waiter.job_kind=="cleanup" and waiter.job_guest_id==guest.id,"waiter immediately accepts departed diner's table before payment")
 evidence.append({"phase":guest.phase,"seated":guest.seated,"paid":guest.paid,"waiter_job":waiter.job_kind,"position":str(Vector2(guest.x,guest.z))})
 if waiter.job_kind!="cleanup":
  release(g);print("EARLY_TABLE_CLEANUP_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence}));quit(1);return
 check(save_reload(g,"before-pickup"),"unpaid assigned cleanup roundtrip")
 var seen={};var simultaneous=false;var concurrent_contact=false
 for tick in range(1200):
  g._tick_live_service(.05);g._animate_staff(.05);g.animation_time+=.05
  guest=g.model.customers[0];waiter=worker(g,"waiter");var record=g.service_guests[int(guest.id)]
  var stage=""
  if waiter.job_kind=="cleanup" and worker(g,"cashier").job_kind=="take_payment":
   simultaneous=true
   if waiter.job_elapsed>.1 and worker(g,"cashier").job_elapsed>.1:concurrent_contact=true
  if record.plate_owner=="staff":stage="carried"
  elif record.plate_owner=="dish_queue" and not record.table_wiped:stage="queued"
  if waiter.art_action=="wiping" and waiter.job_elapsed>.1:stage="wiping"
  if record.cleanup_done:stage="completed"
  if stage!="" and not seen.has(stage):
   seen[stage]=true;save_reload(g,stage)
  if stage=="completed":break
 guest=g.model.customers[0];var record=g.service_guests[int(guest.id)]
 check(simultaneous,"cashier payment and waiter table cleanup coexist without a guest-wide lock")
 check(concurrent_contact,"both cashier and waiter perform contact work concurrently")
 check(seen.has("carried") and seen.has("queued") and seen.has("wiping") and seen.has("completed"),"unpaid table reaches each actual custody/contact stage")
 check(record.cleanup_done and not guest.paid and guest.phase in ["checkout_wait","checkout_walk","paying"] and g.model.served==0 and g.model.total_earned==0,"completed cleanup preserves unpaid diner and debt while cashier approaches")
 check(record.token==token and g.model._item_in_use(int(guest.table_id)) and g.model._item_in_use(int(guest.chair_id)),"early cleanup does not release legitimate dining booking")
 var guest_count=g.model.customers.size();g.model.operating_open=true;g.model._spawn_customer();g.model.operating_open=false
 check(g.model.customers.size()==guest_count,"unpaid cleared table is not double booked")
 # Validate only newly enabled checkout states; retain existing old inputs.
 for stage in ["before-pickup","carried","queued","wiping","completed"]:
  if not snapshots.has(stage):continue
  var state=snapshots[stage].duplicate(true);state.service.version=5
  check(not valid(g,state).ok,stage+" cannot masquerade as service5")
 var invalid=snapshots["before-pickup"].duplicate(true)
 var waiting=invalid.service.staff.filter(func(s):return s.role=="waiter")[0]
 waiting.job_step=2;waiting.job_elapsed=.2
 check(not valid(g,invalid).ok,"uncollected checkout dishes cannot skip to wiping")
 invalid=snapshots["before-pickup"].duplicate(true)
 var extra=invalid.service.staff.filter(func(s):return s.role=="waiter")[0].duplicate(true)
 invalid.service.staff.append(extra)
 extra.job_kind="";extra.job_guest_id=-1;extra.job_token=-1;extra.job_step=0;extra.job_elapsed=0.0
 check(valid(g,invalid,1).ok,"additional idle waiter matches the expanded roster and duty control")
 var assigned=invalid.service.staff.filter(func(s):return s.job_kind=="cleanup")[0]
 extra.job_kind="cleanup";extra.job_guest_id=assigned.job_guest_id;extra.job_token=assigned.job_token
 var duplicate=valid(g,invalid,1)
 check(not duplicate.ok and duplicate.error=="Duplicate table cleanup job","two waiters cannot own one checkout table job")
 invalid=snapshots["queued"].duplicate(true)
 waiting=invalid.service.staff.filter(func(s):return s.role=="waiter")[0]
 waiting.job_step=0;waiting.job_elapsed=.2
 check(not valid(g,invalid).ok,"queued dishes cannot retain an active collection gesture")
 invalid=snapshots["completed"].duplicate(true);invalid.customers[0].paid=true
 check(not valid(g,invalid).ok,"cleanup cannot forge paid checkout")
 invalid=snapshots["completed"].duplicate(true);invalid.service.records[0].meal_done=false
 check(not valid(g,invalid).ok,"unfinished meal cannot enter early cleanup")
 invalid=snapshots["carried"].duplicate(true);invalid.service.records[0].dish_sink_id=999999
 check(not valid(g,invalid).ok,"carried dishes reject a nonexistent sink reservation")
 invalid=snapshots["carried"].duplicate(true)
 var ci=-1
 for i in invalid.service.staff.size():
  if invalid.service.staff[i].role=="cashier":ci=i
 invalid.service.records[0].plate_staff_index=ci
 check(not valid(g,invalid).ok,"cashier cannot own the waiter's dirty dishes")
 # Persist exact new state for the actual baseline reader refusal check.
 var artifact=OS.get_environment("LL_EARLY_CLEANUP_SAVE")
 if artifact!="":
  g.model.service_snapshot=g._service_save_snapshot()
  check(g.model.save(artifact),"generated old-reader fixture saves")
 # The on-duty cashier continues its unchanged physical route.
 for tick in range(600):
  g._tick_live_service(.05);g._animate_staff(.05)
  if g.model.served==1:break
 check(g.model.served==1 and g.model.total_earned==g.model.MEAL_PAYMENT,"later cashier settles exactly once after early cleanup")
 var earned=g.model.total_earned;advance(g,3.0)
 check(g.model.served==1 and g.model.total_earned==earned,"repeated ticks never double-pay cleared table")
 release(g)
 print("EARLY_TABLE_CLEANUP_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"stages":seen.keys()}))
 quit(0 if failures.is_empty() else 1)
