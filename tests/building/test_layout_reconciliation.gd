extends SceneTree
const Model=preload("res://scripts/core/cafe_model.gd")
const Plan=preload("res://scripts/gameplay/cafe_edit_plan.gd")
const Reconcile=preload("res://scripts/gameplay/cafe_layout_reconcile.gd")
const Hold=preload("res://scripts/persistence/cafe_layout_hold.gd")
class Fixture extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
var checks=0
var failures=[]
var fixtures={}
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func checkpoint(game,name:String):
 if fixtures.has(name):return
 game.model.service_snapshot=game._service_save_snapshot()
 var data=game.model.save_data()
 check(not data.is_empty(),name+" natural fixture encodes: "+game.model.last_error)
 if not data.is_empty():
  if name=="washing":
   var queue=data.runtime.service.dishwashing
   queue.dishes.append({"id":queue.next_id,"sink_id":queue.dishes[0].sink_id,"elapsed":0.0});queue.next_id+=1
  fixtures[name]=data
func load_fixture(name:String):
 var path="user://fixture-"+name+".json"
 FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(fixtures[name]))
 var model=Model.new();check(model.load_save(path),name+" generated fixture loads: "+model.last_error);return model
func frozen(model)->String:return JSON.stringify([model.customers,model.service_snapshot])
func sell(model,id:int)->bool:
 var planner=Plan.new();var quote=planner.prepare_sell(model,id,Plan.Context.DECORATE)
 return quote.ok and planner.commit(model,quote)
func publish_for_test(model,plan:Dictionary):
 model.customers.assign(plan.customers);model.service_snapshot=plan.service;model.finish_decoration_session()
func check_clock_identity(before:Dictionary,after:Dictionary,label:String):
 check(before.customers.size()==after.customers.size(),label+" preserves visit count")
 for index in before.customers.size():
  var a=before.customers[index];var b=after.customers[index]
  for key in ["id","phase","elapsed","duration","paid","checkout_ticket","checkout_token"]:check(a[key]==b[key],label+" guest "+key)
 for index in before.service.staff.size():
  for key in ["role","job_kind","job_guest_id","job_token","job_step","job_elapsed"]:check(before.service.staff[index][key]==after.service.staff[index][key],label+" staff "+str(index)+" "+key)
 for index in before.service.records.size():
  for key in ["guest_id","token","meal_wait_seconds","plate_owner","drink_owner","trash_owner","plate_staff_index","drink_staff_index","trash_staff_index","meal_done","drink_done"]:check(before.service.records[index][key]==after.service.records[index][key],label+" record "+key)
func run_case(name:String,kind:String):
 var m=load_fixture(name);var prior=m.items.duplicate(true);var before={"customers":m.customers.duplicate(true),"service":m.service_snapshot.duplicate(true)}
 var baseline=frozen(m);var wallet=m.coins;m.begin_decoration_session()
 var target=m.items.filter(func(item):return item.kind==kind)[0];var refund=m.logical_refund(int(target.id))
 check(sell(m,int(target.id)),name+" sells active "+kind)
 check(frozen(m)==baseline,name+" draft retains exact service")
 var draft=JSON.stringify([m.items,m.coins,m._decoration_baseline]);var plan=Reconcile.plan(m,prior,m.service_snapshot)
 check(plan.ok,name+" constructs validated plan: "+str(plan.get("error","")))
 check(JSON.stringify([m.items,m.coins,m._decoration_baseline])==draft and frozen(m)==baseline,name+" planning is read-only")
 if not plan.ok:return
 check(plan.data.version==16 and plan.service.has("layout_hold"),name+" uses rejecting-old-client format")
 check(not plan.service.layout_hold.hosts.is_empty(),name+" records detached host explicitly")
 check_clock_identity(before,{"customers":plan.customers,"service":plan.service},name)
 if name=="cooking":rejects_corruption(m,plan)
 check(m.save("user://draft-"+name+".json"),name+" draft autosave keeps baseline")
 var interrupted=Model.new();check(interrupted.load_save("user://draft-"+name+".json") and interrupted.coins==wallet and not interrupted.get_item(int(target.id)).is_empty(),name+" interrupted draft restores host and wallet")
 publish_for_test(m,plan)
 check(m.coins==wallet+refund and m.get_item(int(target.id)).is_empty(),name+" Apply preserves one refund and no ghost furniture")
 check(m.save("user://held-"+name+".json"),name+" held state saves: "+m.last_error)
 var loaded=Model.new();check(loaded.load_save("user://held-"+name+".json"),name+" held state reloads: "+loaded.last_error)
 check(JSON.parse_string(frozen(loaded))==JSON.parse_string(frozen(m)),name+" saved detached state preserves all values")
 # Restore compatible equipment through the existing purchase quote; the old
 # sold ID is never recreated, and held progress must bind to the new product.
 var held_items=loaded.items.duplicate(true);loaded.coins+=10000;loaded.begin_decoration_session()
 var planner=Plan.new();var product="table_set" if kind=="table" else kind
 var quote=planner.prepare(loaded,product,-1,int(target.rot),Vector2i(target.x,target.z),[],Plan.Context.DECORATE)
 check(quote.ok and planner.commit(loaded,quote),name+" buys compatible replacement")
 var resumed=Reconcile.plan(loaded,held_items,loaded.service_snapshot)
 check(resumed.ok,name+" replacement reconciliation: "+str(resumed.get("error","")))
 if resumed.ok:
  check(not resumed.service.has("layout_hold") and resumed.data.version==15,name+" replacement releases holds and validates the ordinary client contract")
  check_clock_identity(before,{"customers":resumed.customers,"service":resumed.service},name+" resumed")
  publish_for_test(loaded,resumed);check(loaded.save("user://resumed-"+name+".json"),name+" rebound state persists")
func rejects_corruption(m,plan:Dictionary):
 var codec=preload("res://scripts/persistence/cafe_runtime_codec.gd").new()
 var original=plan.data.runtime
 var mutations=[]
 var raw=original.duplicate(true);raw.service.layout_hold.guests[0].token+=1;mutations.append(raw)
 raw=original.duplicate(true);raw.service.layout_hold.hosts.append(raw.service.layout_hold.hosts[0].duplicate(true));mutations.append(raw)
 raw=original.duplicate(true);raw.service.layout_hold.guests[0].id=999;mutations.append(raw)
 raw=original.duplicate(true);raw.service.layout_hold.hosts[0].kind="plant";mutations.append(raw)
 raw=original.duplicate(true);raw.service.layout_hold.staff[0].index={};mutations.append(raw)
 raw=original.duplicate(true);raw.service.staff[0].job_guest_id={};mutations.append(raw)
 raw=original.duplicate(true);raw.customers[0].id={};mutations.append(raw)
 raw=original.duplicate(true);raw.erase("layout_hold_format");mutations.append(raw)
 for index in mutations.size():
  check(not codec.validate(mutations[index],m.items,m.cooks,m.PHASES,16,m.staff_roster(),m.duty_counts).ok,"corrupt held identity/format rejected "+str(index))
 check(not codec.validate(original,m.items,m.cooks,m.PHASES,15,m.staff_roster(),m.duty_counts).ok,"legacy version cannot disguise suspended work")
func unusable_layout():
 var m=load_fixture("cooking");m.coins=100000;var items=m.items.duplicate(true);var original={"customers":m.customers.duplicate(true),"service":m.service_snapshot.duplicate(true)}
 m.begin_decoration_session()
 var count=0
 for z in m.depth:
  for x in m.width:
   if not m.is_floor_owned(Vector2i(x,z)) or not m.item_at(x,z).is_empty():continue
   var planner=Plan.new();var q=planner.prepare(m,"plant",-1,0,Vector2i(x,z),[],Plan.Context.DECORATE)
   if q.ok and planner.commit(m,q):count+=1
 var plan=Reconcile.plan(m,items,m.service_snapshot)
 check(count>20 and plan.ok,"geometrically valid unusable floor constructs hold plan: "+str(plan.get("error","")))
 if plan.ok:
  check(plan.service.layout_hold.staff.size()==m.service_snapshot.staff.size(),"no usable floor holds every worker")
  check(plan.service.layout_hold.guests.size()==m.customers.size(),"no usable floor holds every visit")
  publish_for_test(m,plan)
  check(m.save("user://no-floor.json"),"unusable layout saves without ghost inventory")
  check(m.load_save("user://no-floor.json"),"unusable layout reloads: "+m.last_error)
  var blocked=m.items.duplicate(true);m.begin_decoration_session()
  var baseline_ids=items.map(func(item):return int(item.id))
  for item in m.items.duplicate():
   if int(item.id) not in baseline_ids:check(sell(m,int(item.id)),"clear one blocking furnishing")
  var restored=Reconcile.plan(m,blocked,m.service_snapshot)
  check(restored.ok and not restored.service.has("layout_hold") and restored.data.version==15,"compatible floor releases all original service and validates the ordinary client contract")
  if restored.ok:check_clock_identity(original,{"customers":restored.customers,"service":restored.service},"restored floor")
func cancel_and_failure(game):
 game.editing=false;check(game.model.load_save("user://fixture-cooking.json"),"failure fixture loads");game._restore_service_runtime()
 var baseline=game._service_save_snapshot();var items=game.model.items.duplicate(true);var wallet=game.model.coins
 game._toggle_edit();game.selected_id=int(items.filter(func(i):return i.kind=="stove")[0].id);game._sell()
 game.model.coins+=37;game.model.record_decoration_credit(37)
 check(not game.model.save("user://missing-parent/save.json") and game.editing and game.model.decoration_session_active,"failed draft persistence retains draft and Cancel")
 game.model.duty_counts.chef+=1
 game._toggle_edit()
 check(game.editing and game.model.decoration_session_active and game.model.get_item(int(items[0].id)).is_empty(),"failed reconciliation leaves sold draft and Cancel intact")
 game._cancel_edit()
 check(game.model.coins==wallet+37 and game.model.items==items and game._service_save_snapshot()==baseline,"Cancel restores baseline and confirmed credit exactly once")
 game._cancel_edit();check(game.model.coins==wallet+37,"repeated Cancel cannot duplicate external credit")
 for repeat in 3:
  game._toggle_edit();game._toggle_edit()
  check(not game.editing and game.model.coins==wallet+37,"repeated unchanged Apply preserves wallet")
  game._toggle_edit();game._cancel_edit()
  check(game.model.coins==wallet+37,"repeated Cancel preserves wallet")
 game.model.coins=10000;game._toggle_edit();var old_waiters=game.model.waiters
 game._hire_staff("waiter");game._toggle_edit()
 check(not game.editing and game.model.waiters==old_waiters+1,"Apply preserves an authorized draft staff purchase")
 game.model.service_snapshot=game._service_save_snapshot()
 check(game.model.save("user://hired-after-decorate.json"),"new roster and retained work save together: "+game.model.last_error)

func crossed_worker():
 var m=load_fixture("cooking");var worker=m.service_snapshot.staff[1]
 worker.pos=Vector2(5.0,6.5);worker.path=[];worker.index=0;worker.destination=Vector2i(-100,-100)
 worker.table_face_id=-1;worker.table_face_cell=Vector2i(-1,-1)
 check(not m.save_data().is_empty(),"mid-edge worker fixture is initially valid")
 var prior=m.items.duplicate(true);var before={"customers":m.customers.duplicate(true),"service":m.service_snapshot.duplicate(true)}
 m.begin_decoration_session();var planner=Plan.new()
 var quote=planner.prepare_build(m,Plan.Action.WALL_PLACE,{"axis":"z","x":5,"z":6,"height":"full","material":"sage_panels"})
 check(quote.ok and planner.commit(m,quote),"place a physical wall through paused worker position")
 var plan=Reconcile.plan(m,prior,m.service_snapshot)
 check(plan.ok,"Apply repositions crossing worker instead of rejecting geometry: "+str(plan.get("error","")))
 if plan.ok:
  check(plan.service.staff[1].pos!=worker.pos,"only invalid worker position is rebuilt")
  check_clock_identity(before,{"customers":plan.customers,"service":plan.service},"crossed worker")

func pending_service_capacity(game):
 game.editing=false;check(game.model.load_save("user://fixture-cooking.json"),"capacity fixture loads");game._restore_service_runtime()
 game.model.coins=10000
 check(game.model.place("table_set",3,6),"capacity fixture adds a distinct free dining set")
 game.model.operating_open=true;game.model._spawn_walkers(1);game.model.operating_open=false;game._sync_service_guests()
 check(game.model.customers.size()==2,"capacity fixture has an assigned cook and a new visit")
 if game.model.customers.size()!=2:return
 var first=game.model.customers[0];var second=game.model.customers[1]
 var stove=int(game.service_guests[int(first.id)].meal_station_id);var second_table=int(second.table_id)
 game._toggle_edit()
 for pair in game.model.dining_sets.duplicate(true):
  if int(pair.table_id)!=second_table:
   game.selected_id=int(pair.table_id);game._sell()
 game._toggle_edit()
 check(not game.editing,"Apply allows absent seating without stealing another visit's seat")
 check(int(second.table_id)==second_table and int(first.table_id)==-1,"surviving dining binding wins before replacement")
 check(int(game.service_guests[int(first.id)].meal_station_id)==stove,"held visit retains its surviving cooking binding")
 check(game.model.layout_held("guests",int(first.id)) and game.model.layout_held("guests",int(second.id)),"unassigned visit waits when the only stove belongs to held work")
 var before=held_values(game)
 for tick in 80:game._tick_live_service(.1);game._animate_staff(.1)
 check(held_values(game)==before,"unassigned work does not accrue patience or fabricate departure")
 game.model.service_snapshot=game._service_save_snapshot()
 check(game.model.save("user://held-capacity.json"),"mixed assigned and unassigned hold persists")

func held_values(game)->Array:
 var hold=Hold.registry(game.model.service_snapshot);var values=[]
 var snapshot=game._service_save_snapshot()
 for row in hold.guests:
  var guest=game.model.customers.filter(func(g):return int(g.id)==int(row.id))[0]
  values.append(guest.duplicate(true));values.append(game.service_guests[int(row.id)].duplicate(true))
 for row in hold.staff:
  var worker=snapshot.staff[int(row.index)].duplicate(true)
  worker.erase("blocked_reason");values.append(worker)
 for row in hold.dishes:values.append(game.dishwashing.dishes[int(row.id)].duplicate(true))
 return values
func run_live_case(game,name:String,kind:String):
 game.editing=false
 check(game.model.load_save("user://fixture-"+name+".json"),name+" live fixture loads")
 game._restore_service_runtime()
 var before=game._service_save_snapshot();var guests=game.model.customers.duplicate(true)
 game._toggle_edit()
 var target=game.model.items.filter(func(item):return item.kind==kind)[0]
 game.selected_id=int(target.id);game._update_ui()
 check(not game.compact_ui.remove_button.disabled,name+" UI Sell shares allowed quote")
 game._sell()
 check(game.model.get_item(int(target.id)).is_empty(),name+" actual Sell executes")
 check(game._service_save_snapshot()==before and game.model.customers==guests,name+" actual draft leaves service exact")
 game._toggle_edit()
 check(not game.editing and not game.model.decoration_session_active,name+" actual Apply commits: "+game.model.last_error)
 var held=held_values(game)
 var revision=game.model.revision
 for attempt in 200:game._retry_layout_holds()
 check(game.model.revision==revision,name+" unchanged hold retries do no reconciliation or publish")
 for tick in 30:game._tick_live_service(.1);game._animate_staff(.1)
 check(held_values(game)==held,name+" held progress and custody freeze through live ticks")
 game.model.service_snapshot=game._service_save_snapshot()
 check(game.model.save("user://live-held-"+name+".json"),name+" live held state saves: "+game.model.last_error)
 check(game.model.load_save("user://live-held-"+name+".json"),name+" live held state reloads: "+game.model.last_error)
 game._restore_service_runtime()
 var restored=held_values(game)
 for tick in 20:game._tick_live_service(.1);game._animate_staff(.1)
 check(held_values(game)==restored,name+" reloaded held work remains frozen")

func ordinary_layout_contract():
 var cafe=Fixture.new();root.add_child(cafe);cafe.set_process(false);cafe.illustration.set_process(false)
 var model=cafe.model;model.coins=10000;model.service_snapshot=cafe._service_save_snapshot()
 var prior=model.items.duplicate(true);model.begin_decoration_session()
 var action=Plan.new();var quote=action.prepare_build(model,Plan.Action.WALL_REPLACE,{"key":"x:2:0","height":"half","material":"sage_panels"})
 check(quote.ok and action.commit(model,quote),"ordinary compatibility fixture confirms a one-tile wall replacement")
 var proposal=Reconcile.plan(model,prior,model.service_snapshot)
 check(proposal.ok and proposal.data.version==15 and not proposal.service.has("layout_hold"),"ordinary wall Apply retains the original complete client contract")
 if not proposal.ok:return
 publish_for_test(model,proposal)
 # An empty hold envelope is still necessary when geometry alone requires
 # the explicit new contract: open service may retain an unplaced register.
 model.operating_open=true;prior=model.items.duplicate(true);model.begin_decoration_session()
 var register=model.items.filter(func(item):return item.kind=="register")[0]
 check(sell(model,int(register.id)),"geometry-only fixture sells its register with no active visit")
 check(model.save_data().is_empty(),"original save contract still rejects the open unplaced-register layout")
 proposal=Reconcile.plan(model,prior,model.service_snapshot)
 check(proposal.ok and proposal.data.version==16 and proposal.service.layout_hold.guests.is_empty(),"required geometry allowance retains the explicit new envelope even without held actors")
 if not proposal.ok:return
 publish_for_test(model,proposal)
 check(model.save("user://geometry-held-no-guests.json"),"geometry allowance remains persistable")
 var loaded=Model.new();check(loaded.load_save("user://geometry-held-no-guests.json") and loaded.register_unplaced and loaded.operating_open,"explicit geometry allowance reloads without silently closing service")
 for player in cafe.audio_players.values():player.stop();player.stream=null
 cafe.settings_controls.sfx_player.stop();cafe.settings_controls.sfx_player.stream=null
 cafe.queue_free();await process_frame;await process_frame

func run():
 if not "saveguard" in OS.get_user_data_dir():quit(2);return
 var game=Fixture.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 game.model.first_guest_pending=false;game.model._spawn_walkers(1)
 for tick in 6000:
  game.model._arrival_elapsed=0.0
  if game.model.customers.any(func(g):return g.phase=="ordering"):game.model.operating_open=false
  game._tick_live_service(.1);game._animate_staff(.1)
  for worker in game.staff_states:
   if worker.job_kind=="cook" and int(worker.job_step)==1 and float(worker.job_elapsed)>.5:checkpoint(game,"cooking")
   if worker.job_kind=="take_payment" and float(worker.job_elapsed)>.3:checkpoint(game,"payment")
   if worker.job_kind=="wash" and float(worker.job_elapsed)>1.0:checkpoint(game,"washing")
  for record in game.service_guests.values():
   if record.plate_owner=="counter":checkpoint(game,"counter")
   if record.guest.phase=="eating":checkpoint(game,"table")
  if fixtures.size()==5:break
  if tick%250==0:await process_frame
 check(fixtures.size()==5,"natural service supplies five actual work phases")
 for spec in [["cooking","stove"],["counter","counter"],["table","table"],["washing","sink"],["payment","register"]]:
  if fixtures.has(spec[0]):
   run_case(spec[0],spec[1]);run_live_case(game,spec[0],spec[1])
 unusable_layout();crossed_worker();cancel_and_failure(game);pending_service_capacity(game);await ordinary_layout_contract()
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 game.queue_free();await process_frame;await process_frame
 print("LAYOUT_RECONCILIATION_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"fixtures":fixtures.keys(),"original_player_save_used":false,"live_Apply_connected":true}))
 quit(0 if failures.is_empty() else 1)
