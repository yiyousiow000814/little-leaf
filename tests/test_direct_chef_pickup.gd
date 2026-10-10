extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
const Paint=preload("res://scripts/cafe_paint_plan.gd")
class GeneratedMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
class LegacyMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=false;MinimalStart.apply(model);model.first_guest_pending=false
  # Explicit historic ownership on a reachable layout. reset_new's old
  # demo counter occupies the stove's workface and cannot qualify handoffs.
  model.items.append({"id":model._next_item_id,"kind":"counter","x":8,"z":5,"rot":0});model._next_item_id+=1;model._notify()
  assert(model.place("table_set",3,6),model.last_error)
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func valid(g,snapshot:Dictionary)->Dictionary:
 var runtime={"customers":g.model.customers,"service":snapshot,"next_customer_id":g.model._next_customer_id,"arrival_elapsed":g.model._arrival_elapsed,"walking_customer_id":g.model._walking_customer_id,"next_checkout_ticket":g.model.next_checkout_ticket,"checkout_format":g.SaveContract.CHECKOUT_FORMAT,"layout_motion_format":g.SaveContract.LAYOUT_MOTION_FORMAT}
 return Codec.new().validate(Codec.new().encode(runtime),g.model.items,g.model.cooks,g.model.PHASES,g.model.SAVE_VERSION,g.model.staff_roster(),g.model.duty_counts)
func dispose(g):
 for player in g.audio_players.values():player.stop();player.stream=null
 g.settings_controls.sfx_player.stop();g.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 g.queue_free();await process_frame;await process_frame
func edit_ready_output(g,id:int):
 g._toggle_edit()
 var before=g._service_save_snapshot();var items=g.model.items.duplicate(true);var wallet=g.model.coins
 g.selected_id=id;g._sell()
 check(g.interaction._service_locked(id) and g.model.items==items and g.model.coins==wallet,"editor cannot sell an occupied stove or legacy pass")
 var plan=Paint.new();var actors=g.build_tools.actor_positions()
 var receipt=plan.prepare(g.model,"floor","cream_tile",[Vector2i(7,7),Vector2i(8,7)],actors)
 check(receipt.ok and g._service_save_snapshot()==before,"paint preview leaves live output and service ownership unchanged")
 check(plan.commit(g.model,receipt,actors),"valid paint receipt can publish while the service is paused for editing")
 check(g._service_save_snapshot()==before and g._item_service_locked(id),"paint publication preserves exact output ownership and job locks")
 g._toggle_edit()
func legacy_pipeline():
 var g=LegacyMain.new();root.add_child(g);g.set_process(false);g.illustration.set_process(false)
 var counter=g.model.items.filter(func(i):return i.kind=="counter")[0]
 var counter_id=int(counter.id);var refund=g.model.logical_refund(counter_id)
 g.model._spawn_customer();g.model._spawn_customer();g._sync_service_guests()
 check(g.model.customers.size()==2,"two real synthetic legacy visits provide distinct codec records")
 var guest_id=int(g.model.customers[0].id)
 var reserved=false;var output=false;var transferred=false
 var last_record={}
 for tick in 4000:
  g.model._arrival_elapsed=0.0;g._tick_live_service(.05);g._animate_staff(.05)
  if not g.service_guests.has(guest_id):break
  var record=g.service_guests[guest_id]
  last_record=record.duplicate(true)
  if not reserved:
   for worker in g.staff_states:
    if worker.job_kind!="cook" or int(worker.job_guest_id)!=guest_id or int(worker.job_step)!=3:continue
    record.meal_pass_id=counter_id;record.pass_reserved=true
    check(g._service_target(worker).id==counter_id,"in-flight chef target remains the reserved legacy counter")
    check(g._item_service_locked(counter_id),"reserved legacy counter is locked before deposit")
    g.model.service_snapshot=g._service_save_snapshot()
    check(g.model.save("user://legacy-reserved-counter.json"),"real reserved handoff saves: "+g.model.last_error)
    check(g.model.load_save("user://legacy-reserved-counter.json"),"real reserved handoff reloads: "+g.model.last_error)
    g._restore_service_runtime();record=g.service_guests[guest_id]
    check(record.pass_reserved and record.meal_pass_id==counter_id,"reload retains exact legacy reservation")
    reserved=true;break
  if reserved and not output and record.plate_owner=="counter":
   output=true
   check(record.plate_target_id==counter_id and g._meal_prepared(record),"actual legacy deposit retains counter ownership and meal readiness")
   check(g._item_service_locked(counter_id),"legacy counter holding a plate remains locked")
   edit_ready_output(g,counter_id)
   var good=g._service_save_snapshot()
   check(valid(g,good).ok,"real legacy ready snapshot validates")
   var bad=good.duplicate(true)
   var stove=int(record.meal_station_id)
   for saved in bad.records:
    saved.plate_owner="station";saved.plate_staff_index=-1;saved.plate_target_id=stove;saved.meal_station_id=stove
    saved.pass_reserved=false;saved.meal_pass_id=-1
   var rejected=valid(g,bad)
   check(not rejected.ok and rejected.error=="Invalid or duplicated stove output plate","two distinct guest plates cannot claim one stove output slot")
   bad=good.duplicate(true)
   bad.records[0].plate_owner="station";bad.records[0].plate_staff_index=-1;bad.records[0].plate_target_id=stove;bad.records[0].meal_station_id=-1
   rejected=valid(g,bad)
   check(not rejected.ok and rejected.error=="Invalid or duplicated stove output plate","output station must match the meal's cooking stove")
   check(g._service_save_snapshot()==good,"failed codec validation cannot mutate live ownership")
   g.model.service_snapshot=good
   check(g.model.save("user://legacy-ready-counter.json"),"real legacy ready plate saves")
   check(g.model.load_save("user://legacy-ready-counter.json"),"real legacy ready plate reloads")
   g._restore_service_runtime();record=g.service_guests[guest_id]
   check(record.plate_owner=="counter" and record.plate_target_id==counter_id,"ready counter plate and its physical target survive reload")
  if output and record.plate_owner=="table":transferred=true
  if transferred and bool(record.guest.paid):break
 if not reserved or not output or not transferred:print("LEGACY_HANDOFF_OBSERVATION ",JSON.stringify({"reserved":reserved,"output":output,"transferred":transferred,"record":last_record,"staff":g._service_save_snapshot().staff}))
 check(reserved and output and transferred,"restored legacy chef-to-counter-to-waiter-to-table pipeline completes")
 check(bool(last_record.get("guest",{}).get("paid",false)),"the same legacy guest reaches actual checkout settlement")
 check(g.model.get_item(counter_id).kind=="counter" and g.model.logical_refund(counter_id)==refund,"legacy counter asset and existing refund basis survive service")
 await dispose(g)
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
   edit_ready_output(game,id)
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
 await dispose(game)
 await legacy_pipeline()
 print("DIRECT_CHEF_PICKUP_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
