extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Contract=preload("res://scripts/cafe_save_contract.gd")
class ReviewMain extends "res://scripts/main.gd":
 var allow_cleanup=false
 func _cleanup_ready(guest:Dictionary)->bool:return allow_cleanup and super._cleanup_ready(guest)
 func _load_startup():
  fresh_start=true;save_writes_suppressed=true;MinimalStart.apply(model)
  model.first_guest_pending=false;model.first_guest_start=Vector2.INF
var checks=0
var failures=[]
func _initialize():
 create_timer(100).timeout.connect(func():printerr("PRIVATE19_TIMEOUT");quit(2))
 run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func write(path,data):
 var file=FileAccess.open(path,FileAccess.WRITE);assert(file!=null);file.store_string(JSON.stringify(data));file.close()
func state(game):
 return Model.RuntimeCodec.new().encode([game.model.coins,game.model.items,game.model.owned_parcels,game.model.customers,game.model.reception_visits,game.model.departing_bodies,game.model.served,game.model.total_earned,game.model.service_snapshot,game._service_snapshot_ledger(),game.ground_mess_generation,game.navigation_review.serial,game.model.routing_reception_review_enabled])
func refuse(game,data,label):
 var path="user://private19-invalid.json";write(path,data)
 var before=state(game);var hash=FileAccess.get_sha256(path)
 check(not game.load_routing_reception_review(path),label+" refuses")
 check(state(game)==before and FileAccess.get_sha256(path)==hash and not FileAccess.file_exists(path+".tmp"),label+" preserves live state/bytes/generation")
func run():
 root.size=Vector2i(1360,880)
 var game=ReviewMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 var m=game.model;var path=Contract.ROUTING_RECEPTION_REVIEW_FILE
 check(m.routing_reception_review_enabled and m.guest_navigation_enabled and m.reception_review_enabled,"actual Main fiveflag native entry")
 geometry_cases(m)
 check(Contract.VERSION==15 and not Contract.accepts_version(19,true),"historical contract unchanged")
 check(m.place("plant",7,6),"real purchased layout before persistence: "+m.last_error)
 check(game.save_routing_reception_review(path),"empty actual Main19 save: "+m.last_error)
 if not FileAccess.file_exists(path):game.queue_free();quit(1);return
 var raw=JSON.parse_string(FileAccess.get_file_as_string(path))
 check(Contract.accepts_routing_reception_header(raw) and not Contract.accepts_header(raw,true),"exclusive19 header")
 check(game.load_routing_reception_review(path),"actual Main19 load: "+m.last_error)
 var layout=m.items.duplicate(true);var parcels=m.owned_parcels.duplicate();var wallet=m.coins
 for repeat in 3:check(game.load_routing_reception_review(path) and m.items==layout and m.owned_parcels==parcels and m.coins==wallet,"repeated restore keeps purchased layout/economy "+str(repeat))
 var original_hash=FileAccess.get_sha256(path)
 # Interrupt after validation: preparing a restore does not cancel/live-publish.
 var before=state(game);var prepared=m._prepare_routing_reception_review(path)
 check(prepared.ok and state(game)==before,"interrupted prepared restore preserves live state")
 check(FileAccess.get_sha256(path)==original_hash,"restores preserve source bytes")
 for version in [1,2,14,15,16,17,18,20]:
  var bad=raw.duplicate(true);bad.version=version;refuse(game,bad,"copied/wrong version "+str(version))
 var bad=raw.duplicate(true);bad.schema="wrong";refuse(game,bad,"wrong schema")
 for marker in ["routing_reception_review_format","reception_format"]:
  bad=raw.duplicate(true);bad[marker]="unknown";refuse(game,bad,"wrong marker "+marker)
 for marker in ["navigation_format","footprint_placement_format","reception_review_format","routing_reception_review_format","navigation_phase"]:
  bad=raw.duplicate(true);bad.runtime[marker]="foreign";refuse(game,bad,"nested marker "+marker)
 bad=raw.duplicate(true);bad.runtime.service.staff[0].navigation_phase="bad";refuse(game,bad,"unknown navigation phase")
 # Every restored field must be a supported serializer value before publication.
 for key in ["node","arbitrary_controller","art_heading","blocked_reason","blocked_target_id","blocked_guest_id","job_mess_id","job_dish_id"]:
  bad=raw.duplicate(true);bad.runtime.service.staff[0][key]={};refuse(game,bad,"unsupported/malformed staff field "+key)
 for name in m.ReceptionReview.PROTECTED+[Contract.RECEPTION_REVIEW_FILE.get_file()]:
  if name==path.get_file():continue
  var target="user://"+str(name)
  check(not m.ReceptionReview.path_allowed(target,false,true) and not m.ReceptionReview.path_allowed(target+".tmp",true,true),"protected target/tmp "+str(name))
  check(not game.save_routing_reception_review(target) and not game.load_routing_reception_review(target) and not FileAccess.file_exists(target) and not FileAccess.file_exists(target+".tmp"),"protected API refuses before I/O "+str(name))
 bad=raw.duplicate(true);bad.runtime.service={}
 refuse(game,bad,"standalone empty service cannot restore live Main")
 var ordinary=Model.new()
 check(ordinary.save("user://historical15-control.json"),"authentic ordinary15 writer retained")
 refuse(game,JSON.parse_string(FileAccess.get_file_as_string("user://historical15-control.json")),"authentic copied15 cannot promote")
 check(not ordinary.save(path) and not ordinary.load_save(path) and not ordinary.save(path+".tmp") and not ordinary.load_save(path+".tmp"),"reciprocal default19 target/temp refusal")
 check(not m.save_reception(path) and not m.load_reception(path),"18 gate remains disjoint")
 check(not m.ReceptionReview.path_allowed("user://escape/19.json",false,true),"native junction escape refused")
 check(not m.ReceptionReview.path_allowed("user://con.json",false,true) and not m.ReceptionReview.path_allowed("user://bad:stream.json",false,true),"device/stream refused")
 # Use an actual admission path and real service to obtain fractional diagonals.
 m.set_operating_open(true);check(m.Reception.add(m),"real admission retained")
 var guest_saved=false;var staff_saved=false;var paid_saved=false;var earned=0
 var chef_pass_saved=false;var second=false;var waiting_saved=false;var resumed=false;var old_id=-1;var new_id=-1;var token=-1
 for frame in 3600:
  m._arrival_elapsed=0;game._tick_live_service(.1);game._animate_staff(.1)
  if not guest_saved and m.reception_visits.any(func(v):return absf(v.heading.x)>.01 and absf(v.heading.y)>.01):
   check(game.save_routing_reception_review(path),"actual fractional guest diagonal saves: "+m.last_error)
   if FileAccess.file_exists(path):
    var saved=JSON.parse_string(JSON.stringify(Model.RuntimeCodec.new().encode(m.reception_visits)))
    var loaded=game.load_routing_reception_review(path)
    var after=JSON.parse_string(JSON.stringify(Model.RuntimeCodec.new().encode(m.reception_visits)))
    check(loaded and after==saved,"guest diagonal actual-body restore: "+m.last_error)
   await capture(game,"private19-guest-diagonal-restored")
   guest_saved=true
  for actor in game.navigation_review.actors.values():
   if staff_saved or actor.follower.is_empty():continue
   var staff=actor.staff
   var follower=actor.follower
   var next=int(follower.index)
   var direction=Vector2.ZERO if next>=follower.plan.route.size() else m.cell_center(follower.plan.route[next])-staff.pos
   if absf(direction.x)>.01 and absf(direction.y)>.01:
    check(game.save_routing_reception_review(path),"actual staff fractional diagonal saves: "+m.last_error)
    var serial=game.navigation_review.serial;var generation=game.ground_mess_generation
    check(game.load_routing_reception_review(path) and game.navigation_review.serial>serial and game.ground_mess_generation>generation,"fresh staff restore callbacks and ground generation: "+m.last_error)
    var staff_raw=JSON.parse_string(FileAccess.get_file_as_string(path))
    var decoded=Model.RuntimeCodec.new().decode(staff_raw.runtime)
    var selected=decoded.service.staff.filter(func(s):return s.has("navigation_phase") and s.path.size()>1)
    if not selected.is_empty():
     var selected_index=decoded.service.staff.find(selected[0])
     var malformed=staff_raw.duplicate(true)
     malformed.runtime.service.staff[selected_index].pos=Model.RuntimeCodec.new().encode(selected[0].pos+Vector2(.1,0))
     refuse(game,malformed,"staff actual body off active diagonal")
     malformed=staff_raw.duplicate(true);malformed.runtime.service.staff[selected_index].navigation_phase="replan"
     malformed.runtime.service.staff[selected_index].path=Model.RuntimeCodec.new().encode([selected[0].path[0],selected[0].path[0]+Vector2i(2,2)])
     refuse(game,malformed,"replan cannot skip a cell")
     malformed=staff_raw.duplicate(true);malformed.runtime.service.staff.append(malformed.runtime.service.staff[selected_index].duplicate(true))
     refuse(game,malformed,"duplicate service/endpoint owner")
    await capture(game,"private19-staff-diagonal-restored")
    staff_saved=true;break
  if not chef_pass_saved:
   for worker in game.staff_states:
    if worker.job_kind!="cook" or int(worker.job_step)!=3 or worker.destination==Vector2i(-100,-100):continue
    var pass_target=game._service_target(worker)
    if pass_target.is_empty() or str(pass_target.kind)!="counter":continue
    var pass_face=Vector2i(int(pass_target.x),int(pass_target.z))*2-m.workface_cell(pass_target)
    if worker.destination!=pass_face:continue # Stage transition has not replanned its current target yet.
    check(game.save_routing_reception_review(path),"actual chef pass destination saves independently of stove ID: "+m.last_error)
    check(game.load_routing_reception_review(path),"actual chef pass payload/step restores: "+m.last_error)
    chef_pass_saved=true;break
  if m.served==1 and not paid_saved and m.customers.any(func(g):return g.phase=="leaving" and g.paid and not g.dismounting and not g.seated and m.is_floor_owned(Vector2i(floori(g.x),floori(g.z)))):
   earned=m.total_earned
   check(game.save_routing_reception_review(path),"actual paid departure saves: "+m.last_error)
   check(game.load_routing_reception_review(path) and m.served==1 and m.total_earned==earned,"paid identity restore without payment replay: "+m.last_error)
   var paid=JSON.parse_string(FileAccess.get_file_as_string(path))
   # An actual paid route retains its old goal after a legal land purchase.
   var grown=m._prepare_routing_reception_review(path).model
   var old_goal:Vector2=grown.customers[0].route[-1]
   var old_body=Vector2(grown.customers[0].x,grown.customers[0].z)
   var additions=grown.expansion_parcels().filter(func(p):return p.unlocked and not p.owned and int(p.z)+int(p.h)>grown.depth)
   check(not additions.is_empty(),"retained-route fixture has an eligible depth-growing parcel")
   if not additions.is_empty():
    # Funds belong only to this disposable prepared model, never the live game.
    grown.coins=maxi(grown.coins,int(additions[0].cost))
    check(grown.buy_parcel(str(additions[0].id)) and old_goal.y!=grown._departure_exit_z(int(grown.customers[0].id)),"actual parcel purchase changes depth without rewriting old exit")
    check(grown.customers[0].route[-1]==old_goal and Vector2(grown.customers[0].x,grown.customers[0].z)==old_body and grown.served==1 and grown.total_earned==earned,"land growth retains actual body/goal/paid identity")
    var retained="user://private19-retained-paid-goal.json"
    check(grown.save_routing_reception_review(retained),"retained paid goal saves after depth growth")
    check(game.load_routing_reception_review(retained) and m.customers[0].route[-1]==old_goal and Vector2(m.customers[0].x,m.customers[0].z)==old_body and m.served==1 and m.total_earned==earned,"Main restores retained exterior goal without snapping body/payment")
    check(game.load_routing_reception_review(path),"original paid layout restores after isolated growth probe")
   # Both legitimate pending chair departure and completed exterior body load.
   var decoded=Model.RuntimeCodec.new().decode(paid.runtime)
   var pending=paid.duplicate(true);var pending_guest=decoded.customers[0].duplicate(true)
   var pending_chair=m.get_item(int(pending_guest.chair_id))
   pending_guest.x=float(pending_chair.x)+.5;pending_guest.z=float(pending_chair.z)+.5
   pending_guest.route=[];pending_guest.route_index=0;pending_guest.seated=true;pending_guest.dismounting=true
   pending_guest.egress_cell=Vector2i(-100,-100);pending_guest.dismount_progress=0.0
   pending_guest.departure_blocked=true;pending_guest.waiting=true;pending_guest.exterior_exit=false
   pending.runtime.customers[0]=Model.RuntimeCodec.new().encode(pending_guest)
   write("user://private19-blocked-paid.json",pending)
   check(m._prepare_routing_reception_review("user://private19-blocked-paid.json").ok,"existing blocked seated departure remains readable")
   var completed=paid.duplicate(true);var completed_guest=decoded.customers[0].duplicate(true)
   completed_guest.x=old_goal.x;completed_guest.z=old_goal.y;completed_guest.route=[old_goal];completed_guest.route_index=1;completed_guest.exterior_exit=true
   completed.runtime.customers[0]=Model.RuntimeCodec.new().encode(completed_guest)
   write("user://private19-completed-paid.json",completed)
   check(m._prepare_routing_reception_review("user://private19-completed-paid.json").ok,"completed exterior route remains readable at its actual endpoint")
   # Reproduce only the reported existing paid departure contradiction.
   var paid_guest=paid.runtime.customers[0]
   var paid_at=Vector2(float(paid_guest.x),float(paid_guest.z))
   for exhausted in [false,true]:
    var short=paid.duplicate(true)
    short.runtime.customers[0].route=Model.RuntimeCodec.new().encode([paid_at]) if exhausted else []
    short.runtime.customers[0].route_index=1 if exhausted else 0
    write("user://paid-endpoint-probe.json",short)
    var probe=m._prepare_routing_reception_review("user://paid-endpoint-probe.json")
    if probe.ok:
     var probe_guest=probe.model.customers[0]
     probe.model._advance_walk(probe_guest,.01)
     print("PAID_DEPARTURE_TAMPER_TRACE ",JSON.stringify({"exhausted":exhausted,"phase":probe_guest.phase,"indoor":probe.model.is_floor_owned(Vector2i(floori(probe_guest.x),floori(probe_guest.z)))}))
    refuse(game,short,"paid departure cannot finish indoors "+str(exhausted))
    check(game.load_routing_reception_review(path),"original paid departure restores after tamper probe")
   var false_blocked=paid.duplicate(true)
   false_blocked.runtime.customers[0].route=[];false_blocked.runtime.customers[0].route_index=0
   false_blocked.runtime.customers[0].departure_blocked=true;false_blocked.runtime.customers[0].waiting=true
   write("user://private19-blocked-register.json",false_blocked)
   check(m._prepare_routing_reception_review("user://private19-blocked-register.json").ok,"existing paid register departure retry remains readable")
   false_blocked.runtime.customers[0].settlement_mode="legacy";false_blocked.runtime.customers[0].checkout_ticket=0
   false_blocked.runtime.customers[0].checkout_register_id=-1;false_blocked.runtime.customers[0].checkout_token=-1
   false_blocked.runtime.customers[0].checkout_cell=Model.RuntimeCodec.new().encode(Vector2i(-100,-100))
   refuse(game,false_blocked,"unseated legacy body cannot claim blocked chair departure")
   var malformed=paid.duplicate(true)
   malformed.runtime.customers[0].mobility={"kind":"blocked","format":"little_leaf.footprint_placement.v1"}
   refuse(game,malformed,"blocked17 intent is disjoint while layout remains saved")
   paid_saved=true
  if paid_saved and not second and m.customers.any(func(g):return g.phase in ["dirty","cleaning"]):second=m.Reception.add(m)
  if second and not waiting_saved:
   for visitor in m.reception_visits:
    if visitor.phase!="waiting_cleaning" or not visitor.seated:continue
    old_id=int(visitor.cleanup_owner_id);new_id=int(visitor.id);token=int(game.service_guests[old_id].token)
    check(game.save_routing_reception_review(path),"dirty chair/new waiting owner save: "+m.last_error)
    check(game.load_routing_reception_review(path) and int(m.reception_visits[0].cleanup_owner_id)==old_id and int(game.service_guests[old_id].token)==token and not game.service_guests.has(new_id),"restore preserves waiting visitor and original cleanup token: "+m.last_error)
    await capture(game,"private19-dirty-chair-custody-restored")
    waiting_saved=true;game.allow_cleanup=true;break
  if waiting_saved and not game.service_guests.has(old_id) and game.service_guests.has(new_id):resumed=true;break
  if frame%100==0:await process_frame
 check(guest_saved and staff_saved and chef_pass_saved and paid_saved and waiting_saved and resumed,"all actual route/dirty-seat lifecycle savepoints reached")
 check(m.served==1 and m.total_earned==Model.MEAL_PAYMENT and m.total_cleaned==1,"restored meal/payment/original cleanup exactly once")
 game.queue_free();await process_frame;await process_frame
 print("ROUTING_RECEPTION_PERSISTENCE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)

func capture(game,label:String):
 var out=OS.get_environment("LL_RECEPTION_CAPTURE")
 if out.is_empty():return
 game._update_ui();game.illustration._process(.1);game.illustration.queue_redraw()
 for frame in 5:await process_frame
 await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png(out+"/"+label+".png")==OK,label+" actual viewport")

func geometry_cases(m):
 # The reader geometry policy is exercised on an isolated copy; this never
 # changes the actual Main purchase/service fixture or its live claims.
 var shadow=Model.FurnitureMotion.copy_model(m)
 shadow.items.clear();shadow.built_walls.clear();shadow.wall_attachments.clear()
 var actor={"path":[Vector2i(2,2),Vector2i(3,3)],"index":1,"pos":Vector2(2.8,2.8),"navigation_phase":"follow","job_kind":"","destination":Vector2i(3,3)}
 var snapshot={"customers":[],"service":{"staff":[actor]}}
 check(Model.RoutingReceptionReview.geometry_error(shadow,snapshot)=="","legal fractional unit diagonal reader geometry")
 shadow.items.append({"id":900,"kind":"plant","x":3,"z":2,"rot":0,"level":1})
 check(Model.RoutingReceptionReview.geometry_error(shadow,snapshot)!="","orthogonal furniture blocks diagonal corner")
 shadow.items.clear()
 shadow.built_walls.append({"id":901,"axis":"x","x":2,"z":3,"height":"full","material":"original","paid_cost":0})
 check(Model.RoutingReceptionReview.geometry_error(shadow,snapshot)!="","crossed wall edge blocks diagonal")
 shadow.wall_attachments.append({"id":903,"kind":"door","host_id":"wall:901","offset":.5,"width":.76,"paid_cost":40})
 check(Model.RoutingReceptionReview.geometry_error(shadow,snapshot)!="","door frame cannot authorize diagonal corner crossing")
 shadow.wall_attachments.clear()
 shadow.built_walls.clear();shadow.items.append({"id":902,"kind":"plant","x":2,"z":2,"rot":0,"level":1})
 check(Model.RoutingReceptionReview.geometry_error(shadow,snapshot)!="","actual restored body cannot occupy solid furniture")

 # An exhausted route cannot relocate its actor while retaining an owned goal.
 var chair=m.items.filter(func(i):return i.kind=="chair")[0]
 var seat=m.cell_center(Vector2i(chair.x,chair.z))
 var guest={"id":990,"chair_id":int(chair.id),"table_id":-1,"phase":"arriving","heading":Vector2.DOWN,"x":seat.x,"z":seat.y,"seated":false,"dismounting":false,"mobility":{},"route":[seat],"route_index":1}
 var guest_state={"customers":[guest],"service":{"staff":[]}}
 check(Model.RoutingReceptionReview.geometry_error(m,guest_state)=="","exhausted arrival route keeps actual seat endpoint")
 guest.x=7.5;guest.z=6.5
 check(Model.RoutingReceptionReview.geometry_error(m,guest_state)!="","exhausted arrival route cannot relocate its body")
 shadow.items.clear();shadow.built_walls.clear()
 var waiter={"path":[],"index":0,"pos":Vector2(2.5,2.5),"job_kind":"order","job_guest_id":991,"job_token":9,"destination":Vector2i(-100,-100)}
 var duplicate={"customers":[],"service":{"staff":[waiter,waiter.duplicate(true)]}}
 duplicate.service.staff[1].pos=Vector2(4.5,4.5)
 check(Model.RoutingReceptionReview.geometry_error(shadow,duplicate)!="","guest token remains exclusive even without a claimed waypoint")
