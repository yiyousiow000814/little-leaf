extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
class MealDrawProbe extends "res://scripts/illustrated_cafe.gd":
 var plates=0;var cups=0
 func _plate(_at:Vector2,_remaining=1.0,_dirty=false):plates+=1
 func _cup(_bottom:Vector2,_filled=true):cups+=1
class GeneratedMain extends "res://scripts/main.gd":
 var observed_saves=[]
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;paused=true;MinimalStart.apply(model)
 func _save():
  if not model.customers.is_empty():observed_saves.append({"guest":model.customers[0].duplicate(true),"service":_service_save_snapshot()})
  return true
var game
var checks=0
var failures=[]
var payments=0
func _initialize():
 create_timer(90.0).timeout.connect(func():printerr("FAIL patience policy fixture did not finish");quit(1))
 run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func record()->Dictionary:return game.service_guests.values()[0]
func worker(role:String)->Dictionary:
 for staff in game.staff_states:
  if staff.role==role:return staff
 return {}
func item(kind:String)->Dictionary:
 for entry in game.model.items:
  if entry.kind==kind:return entry
 return {}
func valid(snapshot:Dictionary)->Dictionary:
 var runtime={"customers":game.model.customers,"service":snapshot,"next_customer_id":game.model._next_customer_id,"arrival_elapsed":game.model._arrival_elapsed,"walking_customer_id":game.model._walking_customer_id,"next_checkout_ticket":game.model.next_checkout_ticket,"checkout_format":game.SaveContract.CHECKOUT_FORMAT,"layout_motion_format":game.SaveContract.LAYOUT_MOTION_FORMAT}
 return Codec.new().validate(Codec.new().encode(runtime),game.model.items,game.model.cooks,game.model.PHASES,game.model.SAVE_VERSION,game.model.staff_roster(),game.model.duty_counts)
func json_state(value):return JSON.parse_string(JSON.stringify(Codec.new().encode(value),"",true,true))
func save_payload(path:String)->Dictionary:
 game.model.service_snapshot=game._service_save_snapshot()
 var ok=game.model.save(path);check(ok,"generated policy save succeeds: "+game.model.last_error)
 return JSON.parse_string(FileAccess.get_file_as_string(path)) if ok else {}
func reset()->Dictionary:
 check(game.model.load_save("user://policy-seated.json"),"reset generated seated fixture")
 game._restore_service_runtime();game.paused=true;game.editing=false;game.speed=1.0;game.save_recovery_blocked=false;game.save_timer=0.0;game.observed_saves.clear()
 return record()
func roundtrip(label:String):
 var before=json_state(game._service_save_snapshot());var guests=json_state(game.model.customers)
 var wallet=[game.model.coins,game.model.served,game.model.total_earned,game.model.total_wages_paid,game.model.wages_due]
 var fixtures=json_state([game.model.items,game.model.dining_sets,game.model.shell_segment_products])
 var receipt=game.web_save.inbox_snapshot.duplicate(true)
 var payload=save_payload("user://policy-current.json")
 if payload.is_empty():return
 check(payload.runtime.service.version==5 and payload.version==15,label+" writes service5 under the unchanged save header")
 var checksum=FileAccess.get_sha256("user://policy-current.json")
 check(game.model.load_save("user://policy-current.json"),label+" reloads: "+game.model.last_error)
 game._restore_service_runtime()
 check(json_state(game._service_save_snapshot())==before,label+" retains jobs, reservations, payloads and clock exactly")
 check(json_state(game.model.customers)==guests,label+" retains physical route and departure state")
 check(wallet==[game.model.coins,game.model.served,game.model.total_earned,game.model.total_wages_paid,game.model.wages_due] and json_state([game.model.items,game.model.dining_sets,game.model.shell_segment_products])==fixtures,label+" retains wallet and purchase data")
 check(receipt==game.web_save.inbox_snapshot and FileAccess.get_sha256("user://policy-current.json")==checksum,label+" leaves receipt cache and source save unchanged")
func place_worker_at_target(staff:Dictionary,target:Dictionary):
 var cell=game._service_destination(staff,target,Vector2i(staff.pos.floor()))
 check(cell!=Vector2i(-1,-1),"fixture workface is reachable")
 staff.pos=game.model.cell_center(cell);staff.node.position=Vector3(staff.pos.x,0,staff.pos.y)
 staff.destination=cell;staff.path.clear();staff.index=0;staff.yield_time=0.0
func cooking(r:Dictionary,remaining:float):
 var guest=r.guest;guest.phase="cooking";guest.elapsed=0.0;guest.duration=game.model.PHASE_SECONDS.cooking;r.order_done=true
 var chef=worker("chef");game._assign_service_job(chef,game.staff_states.find(chef));chef.job_step=1
 chef.job_elapsed=Model.cooking_seconds(Model.stove_speed_multiplier(item("stove")))-remaining
 place_worker_at_target(chef,item("stove"))
 return chef
func held_ready(r:Dictionary)->Dictionary:
 var guest=r.guest;guest.phase="cooking";guest.elapsed=0.0;guest.duration=game.model.PHASE_SECONDS.cooking;r.order_done=true;r.meal_ready=true
 var waiter=worker("waiter");waiter.job_kind="deliver_meal";waiter.job_guest_id=int(guest.id);waiter.job_token=int(r.token);waiter.job_step=1;waiter.station_id=int(item("counter").id)
 r.meal_pass_id=int(item("counter").id);r.plate_owner="staff";r.plate_staff_index=game.staff_states.find(waiter);r.plate_target_id=-1
 place_worker_at_target(waiter,game.model.get_item(int(guest.table_id)))
 return waiter
func run():
 root.size=Vector2i(1360,880)
 game=GeneratedMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.web_save=game.WebSave.new(game)
 game.web_save.inbox_snapshot={"ok":true,"profileId":"synthetic-policy","revision":2,"paid":[{"id":"receipt","revision":1,"coins":1000}],"deferred":[]}
 check(game.save_writes_suppressed and OS.get_environment("XDG_DATA_HOME")!="","isolated generated profile only")
 game.model.meal_completed.connect(func(_id,_amount):payments+=1)
 game.model._spawn_customer();game.model.operating_open=false;game._sync_service_guests()
 var r=record();var guest=r.guest;var travel_ticks=0
 while guest.phase=="arriving" and travel_ticks<6000:
  game._tick_live_service(.05);travel_ticks+=1
  if travel_ticks%300==0:await process_frame
 check(guest.seated and guest.phase=="ordering" and r.meal_wait_seconds==0.0,"actual seating starts zero after uncharged street approach")
 save_payload("user://policy-seated.json")
 game._tick_live_service(60.0);game._tick_live_service(9.99)
 check(is_equal_approx(r.meal_wait_seconds,69.99) and game._guest_bubble_symbol(guest)=="…","69.99 seconds retains normal ordering")
 game._tick_live_service(.01)
 check(is_equal_approx(r.meal_wait_seconds,70.0) and game._guest_bubble_symbol(guest)=="angry","70 seconds starts anger exactly")
 check(guest.elapsed<=guest.duration and guest.elapsed<70.0,"wait clock is independent of clamped phase elapsed")
 game._advance_meal_wait(49.99);game._resolve_meal_deadlines()
 check(is_equal_approx(r.meal_wait_seconds,119.99) and not guest.meal_abandoned and game._guest_bubble_symbol(guest)=="angry","anger persists through 119.99 seconds without premature departure")
 roundtrip("waiting at119.99")
 r=record();guest=r.guest
 var waiter=worker("waiter");game._assign_service_job(waiter,game.staff_states.find(waiter));game._animate_staff(.01)
 game.dishwashing.dishes[1]={"id":1,"sink_id":int(item("sink").id),"elapsed":0.0};game.dishwashing.next_id=2
 var unrelated=json_state([game.floor_tasks.snapshot(),game.dishwashing.snapshot(),game._service_save_snapshot().staff.filter(func(s):return s.role!="waiter")])
 var token=int(r.token);var position=waiter.pos;var coins=game.model.coins;var receipt=game.web_save.inbox_snapshot.duplicate(true)
 game._advance_meal_wait(.01);game._resolve_meal_deadlines()
 check(guest.meal_abandoned and guest.phase=="leaving" and not guest.paid,"unfinished meal departs unpaid at120")
 check(int(r.token)>token and waiter.job_kind=="" and waiter.job_token==-1 and waiter.station_id==-1 and waiter.table_face_id==-1 and waiter.path.is_empty() and waiter.pos==position,"old-token order releases once without moving its worker")
 check(not r.pass_reserved and r.meal_station_id==-1 and r.meal_pass_id==-1 and r.drink_station_id==-1,"all meal station/pass claims released")
 check(guest.checkout_ticket==0 and guest.checkout_token==-1 and guest.checkout_register_id==-1 and guest.checkout_cell==Vector2i(-100,-100),"abandoned visit has no checkout authority")
 check(game.model.coins==coins and game.model.total_earned==0 and game.model.served==0 and payments==0 and game.web_save.inbox_snapshot==receipt,"deadline causes no payment or receipt mutation")
 check(json_state([game.floor_tasks.snapshot(),game.dishwashing.snapshot(),game._service_save_snapshot().staff.filter(func(s):return s.role!="waiter")])==unrelated,"cancellation preserves independent floor/dish work and every unrelated worker")
 check(game._guest_bubble_symbol(guest)=="angry","anger remains visible during physical departure")
 var after_token=r.token;game._resolve_meal_deadlines();check(r.token==after_token,"departure resolution is idempotent")
 roundtrip("chair dismount")
 r=record();guest=r.guest
 game._tick_live_service(.05);roundtrip("partial chair departure")
 for step in 1800:
  game._tick_live_service(.05);game._animate_staff(.05)
  if game.model.customers.is_empty():break
 check(game.model.customers.is_empty() and game.model.served==0 and game.model.total_earned==0 and payments==0,"unserved guest exits physically and releases dining pair without payment")
 # Same-frame actual cooking completion wins over120; unfinished cooking loses.
 r=reset();var chef=cooking(r,.01);r.meal_wait_seconds=119.99
 game.paused=false;game.save_timer=16.0;game._process(.01);game.paused=true
 check(not r.guest.meal_abandoned and chef.job_step==2 and game._meal_prepared(r),"cooking completion in the deadline frame wins")
 check(game._guest_bubble_symbol(r.guest)=="angry","finished cooking does not clear anger before handoff")
 check(not game.observed_saves.is_empty() and not game.observed_saves[-1].guest.meal_abandoned and game.observed_saves[-1].service.staff[game.staff_states.find(chef)].job_step==2,"autosave observes completed cooking before deadline resolution")
 roundtrip("finished cooking at deadline")
 r=record();game._advance_meal_wait(60.0);game._resolve_meal_deadlines()
 check(not r.guest.meal_abandoned and game._guest_bubble_symbol(r.guest)=="angry","prepared food keeps diner angrily waiting beyond180")
 r=reset();chef=cooking(r,.02);r.meal_wait_seconds=119.99
 var chef_token=chef.job_token;var stale_chef=chef.duplicate(true)
 r.pass_reserved=true;r.meal_pass_id=int(item("counter").id)
 game._tick_live_service(.01);game._animate_staff(.01)
 check(r.guest.meal_abandoned and chef.job_kind=="" and chef.job_token==-1 and int(r.token)>int(chef_token),"cooking still unfinished at deadline is canceled with its exact old token")
 check(not r.pass_reserved and r.meal_pass_id==-1 and r.meal_station_id==-1,"partial-cook cancellation releases its old pass and stove claims")
 var canceled=json_state(game._service_save_snapshot())
 game._service_contact(stale_chef,game.staff_states.find(chef),"plating",item("stove"),1.0)
 check(json_state(game._service_save_snapshot())==canceled,"stale pre-cancellation contact cannot recreate a tray under the old token")
 roundtrip("canceled partial cooking")
 r=reset();chef=cooking(r,25.0);var stove=item("stove");var face=game.model.workface_cell(stove)
 chef.pos=Vector2(2.5,7.5);chef.node.position=Vector3(2.5,0,7.5);chef.path=[];chef.index=0;chef.destination=Vector2i(-100,-100)
 game.model.items.append({"id":game.model._next_item_id,"kind":"plant","x":face.x,"z":face.y,"rot":0});game.model._next_item_id+=1;game.model.revision+=1
 r.meal_wait_seconds=119.9;var blocked_progress=chef.job_elapsed
 game._tick_live_service(.05);game._animate_staff(.05)
 check(not r.guest.meal_abandoned and chef.job_elapsed==blocked_progress,"physical stove obstruction preserves unfinished progress just before deadline")
 game._tick_live_service(.05);game._animate_staff(.05)
 check(r.guest.meal_abandoned and chef.job_kind=="" and not r.pass_reserved and r.meal_station_id==-1,"physical obstruction past deadline cancels unfinished meal and releases stove")
 roundtrip("canceled blocked stove")
 # Ready pass food and a matching waiter's carried meal both retain the diner.
 r=reset();r.guest.phase="cooking";r.guest.duration=game.model.PHASE_SECONDS.cooking;r.order_done=true;r.meal_ready=true;r.meal_wait_seconds=180.0
 r.plate_owner="counter";r.plate_target_id=int(item("counter").id);r.meal_pass_id=r.plate_target_id
 game._resolve_meal_deadlines()
 check(not r.guest.meal_abandoned and game._guest_bubble_symbol(r.guest)=="angry","real pass plate grants ready-food exception but keeps anger")
 roundtrip("food waiting on pass")
 r=reset();waiter=held_ready(r);r.meal_wait_seconds=119.99;waiter.job_elapsed=.8*.65-.01
 game._tick_live_service(.01);game._animate_staff(.01)
 check(r.plate_owner=="table" and not r.guest.meal_abandoned and game._guest_bubble_symbol(r.guest)=="","same-frame table handoff wins and clears anger immediately")
 var stopped=r.meal_wait_seconds;game._advance_meal_wait(4.0);check(r.meal_wait_seconds==stopped,"clock freezes at real handoff before job completion")
 roundtrip("physical food handoff")
 r=reset();waiter=held_ready(r);r.meal_wait_seconds=160.0;game._resolve_meal_deadlines()
 check(not r.guest.meal_abandoned and game._guest_bubble_symbol(r.guest)=="angry","matching carried plate grants exception until delivered")
 roundtrip("carried finished meal")
 # Readiness must not be borrowed from a foreign tray or wrong job token.
 r=reset();r.meal_ready=true;r.plate_owner="staff";r.plate_staff_index=game.staff_states.find(worker("waiter"))
 waiter=worker("waiter");waiter.job_kind="deliver_meal";waiter.job_guest_id=int(r.guest.id)+1;waiter.job_token=int(r.token)
 check(not game._meal_prepared(r),"another guest's tray cannot grant readiness")
 waiter.job_guest_id=int(r.guest.id);waiter.job_token=int(r.token)+1
 check(not game._meal_prepared(r),"wrong service token cannot grant readiness")
 # A delivered cup survives abandonment and completes real sink cleanup.
 r=reset();r.drink_owner="table";r.drink_target_id=int(r.guest.table_id);r.drink_done=true;r.drink_ready=true;r.meal_wait_seconds=120.0
 game._resolve_meal_deadlines()
 check(r.drink_owner=="table" and r.plate_owner=="clean" and not r.dishes_collected and not r.cleanup_done,"delivered cup stays at table without an invented meal plate")
 var meal_draw=MealDrawProbe.new();meal_draw.game=game;meal_draw._meal(int(r.guest.table_id))
 check(meal_draw.plates==0 and meal_draw.cups==1,"actual table renderer draws only the delivered cup before collection")
 roundtrip("unpaid exit with delivered cup")
 var saw_cup_transport=false;var cup_saved=false
 for step in 2400:
  game._tick_live_service(.05);game._animate_staff(.05)
  if not game.service_guests.is_empty():
   r=record()
   if r.plate_owner=="staff" and worker("waiter").job_kind=="cleanup":
    saw_cup_transport=true
    if not cup_saved:
     meal_draw.plates=0;meal_draw.cups=0;meal_draw._meal(int(r.guest.table_id))
     check(meal_draw.plates==0 and meal_draw.cups==0,"actual collection removes the cup without drawing any table plate")
     roundtrip("cup-only cleanup transport");cup_saved=true
  if game.model.customers.is_empty() and game.dishwashing.dishes.is_empty():break
  if step%300==0:await process_frame
 check(saw_cup_transport and cup_saved and game.model.customers.is_empty() and game.dishwashing.completed==1 and game.model.total_earned==0,"delivered cup is collected, queued and washed exactly once after unpaid exit")
 meal_draw.free()
 # Relocation finishes its current physical seating route before departure.
 r=reset();var old_pos=Vector2(r.guest.x,r.guest.z)
 var table=game.model.get_item(int(r.guest.table_id))
 check(game.model.move(int(table.id),5,5,0),"fixture moves occupied dining set")
 check(not r.guest.mobility.is_empty() and not r.guest.seated,"diner has a real in-flight relocation")
 r.meal_wait_seconds=120.0;game._resolve_meal_deadlines()
 check(r.guest.meal_abandoned and not r.guest.mobility.is_empty() and Vector2(r.guest.x,r.guest.z)==old_pos and game._guest_bubble_symbol(r.guest)=="angry","deadline retains relocation position and visible anger")
 roundtrip("abandoned guest finishing relocation")
 for step in 800:
  game._tick_live_service(.05)
  if record().guest.phase=="leaving":break
 check(record().guest.phase=="leaving" and record().guest.mobility.is_empty(),"relocated diner begins real chair exit after reaching the seat")
 roundtrip("departure after relocation")
 # A temporarily blocked departure retries; edits re-route from current position.
 r=reset();r.meal_wait_seconds=120.0;game._resolve_meal_deadlines();guest=r.guest
 var route=guest.route.duplicate();var landing=guest.egress_cell
 guest.route=[];guest.route_index=0;guest.departure_blocked=true;guest.egress_cell=Vector2i(-100,-100);guest.duration=0.0
 roundtrip("blocked departure snapshot")
 r=record();guest=r.guest;var at=Vector2(guest.x,guest.z)
 game._tick_live_service(.01)
 check(not guest.departure_blocked and not guest.route.is_empty() and Vector2(guest.x,guest.z).distance_to(at)<.1,"blocked exit retries without teleportation")
 for step in 40:game._tick_live_service(.05)
 at=Vector2(guest.x,guest.z)
 check(game.model.reroute_guest(guest) and Vector2(guest.x,guest.z)==at,"mid-route unpaid exit replans without resetting position")
 roundtrip("rerouted unpaid departure")
 # Pause/Decorate freeze both mood clock and departure;2x uses game time.
 r=reset();r.meal_wait_seconds=119.0;game.paused=true;game._process(2.0)
 check(r.meal_wait_seconds==119.0 and not r.guest.meal_abandoned,"pause cannot trigger deadline")
 game.paused=false;game.editing=true;game._process(2.0)
 check(r.meal_wait_seconds==119.0 and not r.guest.meal_abandoned,"Decorate cannot trigger deadline")
 game.editing=false;game.speed=2.0;game._process(.5);game.paused=true
 check(r.guest.meal_abandoned and is_equal_approx(r.meal_wait_seconds,120.0),"2x speed reaches120 after half a wall second")
 # Service3/4 migration: retain known clocks; never infer missing history.
 r=reset();r.meal_wait_seconds=95.0
 var current=save_payload("user://policy-legacy-source.json")
 for version in [3,4]:
  for missing in [false,true]:
   var legacy=current.duplicate(true);legacy.runtime.service.version=version;legacy.runtime.customers[0].erase("meal_abandoned")
   if version==3:legacy.runtime.service.erase("dishwashing")
   if missing:legacy.runtime.service.records[0].erase("meal_wait_seconds")
   var file=FileAccess.open("user://policy-legacy.json",FileAccess.WRITE);file.store_string(JSON.stringify(legacy));file.close()
   check(game.model.load_save("user://policy-legacy.json"),"old service"+str(version)+" loads without new departure state")
   game._restore_service_runtime();r=record()
   check(not r.guest.meal_abandoned and r.meal_wait_seconds==(0.0 if missing else 95.0) and game.model.service_snapshot.version==5,"legacy migration preserves known clock or grants fresh grace period")
 r=reset();r.meal_wait_seconds=120.0;game._resolve_meal_deadlines()
 var good=game._service_save_snapshot();check(valid(good).ok,"new departure snapshot validates")
 check(not valid({}).ok,"abandoned guest cannot load through the standalone empty-service shortcut")
 var old=good.duplicate(true);old.version=4;check(not valid(old).ok,"old service format cannot disguise unpaid deadline departure")
 for value in [-1.0,1000000001.0,"120",true,null,INF,NAN]:
  var bad=good.duplicate(true);bad.records[0].meal_wait_seconds=value;check(not valid(bad).ok,"invalid wait clock rejects: "+str(value))
 var prepared=good.duplicate(true);prepared.records[0].meal_ready=true;check(not valid(prepared).ok,"abandoned snapshot cannot retain prepared-food authority")
 var claimed=good.duplicate(true);claimed.records[0].pass_reserved=true;check(not valid(claimed).ok,"abandoned snapshot cannot retain pass reservation")
 check(game._service_save_snapshot()==good,"failed validation cannot alter live deadline state")
 print("SINGLE_GUEST_PATIENCE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"travel_seconds":travel_ticks*.05,"policy":"70 angry /120 unfinished departure"}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
