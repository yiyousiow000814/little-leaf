extends SceneTree
const Fixture=preload("res://tests/role_fixture.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
var game
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func duty(role:String,on:bool):
 game.worker(role).on_duty=on
func advance(seconds:float):
 for tick in range(roundi(seconds/.05)):game.advance(.05)
func sink()->Dictionary:
 for item in game.model.items:
  if item.kind=="sink":return item
 return {}
func fill(count:int,sink_id:int):
 for n in count:
  var id=game.dishwashing.next_id;game.dishwashing.next_id+=1
  game.dishwashing.dishes[id]={"id":id,"sink_id":sink_id,"elapsed":0.0}
func record()->Dictionary:return game.service_guests.values()[0]
func valid(snapshot:Dictionary)->Dictionary:
 var runtime={"customers":game.model.customers,"service":snapshot,"next_customer_id":game.model._next_customer_id,"arrival_elapsed":game.model._arrival_elapsed,"walking_customer_id":game.model._walking_customer_id,"next_checkout_ticket":game.model.next_checkout_ticket,"checkout_format":game.SaveContract.CHECKOUT_FORMAT,"layout_motion_format":game.SaveContract.LAYOUT_MOTION_FORMAT}
 return Codec.new().validate(Codec.new().encode(runtime),game.model.items,game.model.cooks,game.model.PHASES,game.model.SAVE_VERSION,game.model.staff_roster(),game.model.duty_counts)
func roundtrip(label:String):
 var cleaner_on=game.worker("cleaner").on_duty
 var before=game._service_save_snapshot();var money=game.model.coins
 var walls=game.model.shell_segment_products.duplicate(true);var openings=game.model.wall_attachments.duplicate(true)
 game.model.service_snapshot=before
 var saved=game.model.save("user://dishwashing-fixture.json")
 check(saved,label+" saves: "+game.model.last_error)
 if not saved:return
 var saved_bytes=FileAccess.get_sha256("user://dishwashing-fixture.json")
 var payload=JSON.parse_string(FileAccess.get_file_as_string("user://dishwashing-fixture.json"))
 check(payload.wall_format==2 and payload.runtime.service.version==game.SaveContract.SERVICE_VERSION,label+" saves both new wall and dish service formats together")
 check(game.model.load_save("user://dishwashing-fixture.json"),label+" loads: "+game.model.last_error)
 game._restore_service_runtime()
 check(FileAccess.get_sha256("user://dishwashing-fixture.json")==saved_bytes,label+" load leaves original synthetic bytes unchanged")
 check(game.model.shell_segment_products==walls and game.model.wall_attachments==openings,label+" mixed wall ledger and openings survive active dish reload")
 check(game.dishwashing.dishes.size()==before.dishwashing.dishes.size() and game.dishwashing.next_id==int(before.dishwashing.next_id),label+" queue identity unchanged")
 for dish in before.dishwashing.dishes:
  check(game.dishwashing.dishes.has(int(dish.id)) and is_equal_approx(float(game.dishwashing.dishes[int(dish.id)].elapsed),float(dish.elapsed)),label+" wash progress unchanged")
 game.worker("cleaner").on_duty=cleaner_on
 check(game.model.coins==money,label+" does not change wallet")
 for i in before.staff.size():
  check(game.staff_states[i].pos==before.staff[i].pos,label+" staff position retained "+str(i))
func run():
 root.size=Vector2i(1360,880)
 game=Fixture.new();root.add_child(game);await process_frame
 game.set_process(false);game.illustration.set_process(false)
 check(game.save_writes_suppressed and OS.get_environment("XDG_DATA_HOME")!="","isolated generated saves only")
 # One paid segment stays mixed throughout queue, transport and wash reloads.
 check(game.model.replace_wall("shell:back#2","half","leaf_print"),"combined fixture purchases one wall segment")
 check(game.model.shell_segment_products["shell:back#2"].paid_cost==35,"combined fixture retains actual paid wall credit")
 # Physical waiter route ends in a queued plate, never a washed plate.
 var r=game.setup_dirty(false);duty("cleaner",false)
 var stages=[]
 for tick in 1200:
  game.advance()
  var action=game.worker("waiter").art_action
  if not stages.has(action):stages.append(action)
  if r.cleanup_done:break
 check(r.cleanup_done and r.table_wiped and r.plate_owner=="dish_queue","waiter drops and wipes without washing")
 check(stages.has("collecting") and stages.has("carrying_dishes") and stages.has("dropping_dishes") and not stages.has("washing"),"waiter follows collect/carry/drop roles")
 check(game.dishwashing.count_at(int(sink().id))==1 and game.dishwashing.completed==0,"one visible unwashed queued dish")
 roundtrip("queued")
 r=record()
 # Duplicate contact/reload cannot add a second dish.
 var waiter=game.worker("waiter")
 game.dishwashing.deposit(r,waiter,game.staff_states.find(waiter),sink())
 check(game.dishwashing.dishes.size()==1,"drop ownership transition is idempotent")
 duty("cleaner",true)
 var cleaner=game.worker("cleaner")
 for tick in 800:
  game.advance()
  if cleaner.job_kind=="wash" and cleaner.job_elapsed>=5.0:break
 check(cleaner.job_kind=="wash" and cleaner.art_action=="washing","cleaner reaches sink and washes")
 check(game.dishwashing.count_at(int(sink().id))==1 and game.dishwashing.completed==0,"active washing still consumes one capacity slot")
 roundtrip("washing")
 cleaner=game.worker("cleaner")
 var remaining=20.0-float(cleaner.job_elapsed)
 advance(remaining-.05)
 check(game.dishwashing.dishes.size()==1 and game.dishwashing.completed==0,"dish not clean before twenty simulation seconds")
 advance(.05)
 check(game.dishwashing.dishes.is_empty() and game.dishwashing.completed==1 and record().plate_owner=="clean","dish cleans exactly once at twenty seconds")
 advance(5)
 check(game.dishwashing.completed==1,"no duplicate wash after completion")
 # Table lifecycle can finish while queued dish is still waiting independently.
 r=game.setup_dirty(false);duty("cleaner",false)
 r.guest.phase="cleaning";r.guest.duration=1.0;r.guest.elapsed=0.0
 for tick in 1200:
  game._tick_live_service(.05);game.advance()
  if game.model.customers.is_empty():break
 check(game.model.customers.is_empty() and game.dishwashing.dishes.size()==1,"dirty dish survives table release and guest deletion")
 roundtrip("after table release")
 # A full sink never causes pickup, disappearance or fake cleaning.
 r=game.setup_dirty(false);duty("cleaner",false)
 fill(6,int(sink().id));advance(20)
 check(r.plate_owner=="table" and not r.dishes_collected and not r.cleanup_done,"full sink leaves dish dirty at table")
 check(game.dishwashing.load_at(int(sink().id))==6,"full sink capacity includes queue")
 check(game._item_service_locked(int(sink().id)),"sink removal locked while dirty dishes remain")
 game.selected_id=int(sink().id);game._sell()
 check(not game.model.get_item(int(sink().id)).is_empty(),"sell cannot remove occupied sink")
 duty("cleaner",true)
 for tick in 2500:
  game.advance()
  check(game.dishwashing.load_at(int(sink().id))<=6,"capacity remains bounded during retry "+str(tick))
  if r.plate_owner=="dish_queue":break
 check(r.plate_owner=="dish_queue","waiting dish retries after cleaner frees capacity")
 # Reserve before pickup, and keep transport identity through a real save/load.
 r=game.setup_dirty(false);duty("cleaner",false)
 fill(5,int(sink().id))
 for tick in 600:
  game.advance()
  if game.worker("waiter").art_action=="carrying_dishes":break
 check(r.plate_owner=="staff" and int(r.dish_sink_id)==int(sink().id),"carried dish owns its sink reservation")
 check(game.dishwashing.load_at(int(sink().id))==6 and game.dishwashing.count_at(int(sink().id))==5,"reservation counted but not visually stacked")
 roundtrip("transport")
 advance(15)
 check(record().plate_owner=="dish_queue" and game.dishwashing.count_at(int(sink().id))==6,"transport resumes once into sixth queue slot")
 # Two waiters compete for the final slot; their reservation is atomic.
 r=game.setup_dirty(false);duty("cleaner",false)
 game.model.waiters=2;game.model.duty_targets.waiter=2;game._update_people()
 game.model.operating_open=true;game.model._spawn_customer();game.model.operating_open=false
 var second_guest=game.model.customers[-1]
 for key in ["phase","paid","seated","admitted","waiting","settlement_mode","checkout_ticket","checkout_register_id","checkout_token","checkout_cell","route","route_index","x","z","exterior_exit","dismounting","egress_cell","dismount_progress"]:
  second_guest[key]=r.guest[key]
 game.model._walking_customer_id=-1;game._sync_service_guests();fill(5,int(sink().id))
 for worker in game.staff_states:
  if worker.role=="waiter":game._assign_service_job(worker,game.staff_states.find(worker))
 var reservations=0
 for live in game.service_guests.values():
  if int(live.dish_sink_id)==int(sink().id):reservations+=1
 check(reservations==1 and game.dishwashing.load_at(int(sink().id))==6,"two waiters cannot reserve the same sixth slot")
 var owner={}
 for worker in game.staff_states:
  if worker.role=="waiter" and int(game.service_guests[int(worker.job_guest_id)].dish_sink_id)>=0:owner=worker;break
 game._clear_service_job(owner)
 check(game.dishwashing.load_at(int(sink().id))==5,"canceling unstarted collection releases reservation")
 # Remove the synthetic extra waiter before the next baseline fixture.
 var extra=game.staff_states[-1];extra.node.queue_free();game.staff_states.pop_back();game.model.waiters=1;game.model.duty_targets.waiter=1
 # Additional sinks are selected automatically; unreachable ones are ignored.
 r=game.setup_dirty(false);duty("cleaner",false)
 var original=sink();fill(6,int(original.id))
 check(game.model.place("sink",7,1,0),"fixture adds second reachable sink")
 var second={}
 for item in game.model.items:
  if item.kind=="sink" and int(item.id)!=int(original.id):second=item
 for tick in 1200:
  game.advance()
  if r.plate_owner=="dish_queue":break
 check(game.dishwashing.count_at(int(second.id))==1 and game.dishwashing.count_at(int(original.id))==6,"waiter chooses non-full second sink")
 # Paused and normal-speed clocks use the same application process gate.
 r=game.setup_dirty(false);duty("cleaner",true);duty("waiter",false)
 fill(1,int(original.id));cleaner=game.worker("cleaner");cleaner.pos=game.model.cell_center(game.model.workface_cell(original));cleaner.node.position=Vector3(cleaner.pos.x,0,cleaner.pos.y)
 game._assign_service_job(cleaner,game.staff_states.find(cleaner));game.paused=true
 var elapsed=cleaner.job_elapsed;game._process(2.0)
 check(cleaner.job_elapsed==elapsed,"pause does not advance dishwashing")
 game.paused=false;game.compact_ui.viewport_too_small=false;game._process(2.0)
 check(is_equal_approx(cleaner.job_elapsed,2.0),"normal speed advances two simulation seconds in two wall seconds")
 game.paused=true
 # Blocking the sink pauses the physical work clock without deleting progress.
 var old_elapsed=cleaner.job_elapsed;var block={"id":game.model._next_item_id,"kind":"plant","x":int(original.x),"z":int(original.z)+1,"rot":0}
 game.model._next_item_id+=1;game.model.items.append(block);game.model.revision+=1
 advance(2.0)
 check(cleaner.job_elapsed==old_elapsed and game.dishwashing.dishes.size()==1,"blocked workface preserves dish and wash progress")
 game.model.items.erase(block);game.model.revision+=1
 advance(8)
 check(cleaner.job_elapsed>old_elapsed or game.dishwashing.completed==1,"unblocking resumes actual washing")
 # Moving a loaded sink retains item identity, queue and partial progress.
 var saved_elapsed=cleaner.job_elapsed;var saved_queue=game.dishwashing.snapshot()
 check(game.model.move(int(original.id),10,0,0),"fixture moves an occupied sink while paused")
 check(game.dishwashing.snapshot()==saved_queue and cleaner.job_elapsed==saved_elapsed,"sink move preserves all dishes and washing progress")
 var before_cancel=game.dishwashing.snapshot();game._cancel_selection()
 check(game.dishwashing.snapshot()==before_cancel,"canceling Decorate selection does not cancel or duplicate dishes")
 roundtrip("moved sink")
 cleaner=game.worker("cleaner");advance(2.0)
 check(cleaner.job_elapsed>=saved_elapsed or game.dishwashing.completed==1,"cleaner replans to moved sink")
 # Strict validation refuses duplicated entries, seventh dish, lost owner,
 # wrong-role washing and elapsed mismatch, before replacing live state.
 r=game.setup_dirty(false);duty("waiter",true);fill(1,int(original.id));game._sync_staff_duty()
 var good=game._service_save_snapshot();check(valid(good).ok,"synthetic independent queued ledger validates")
 var bad=good.duplicate(true);bad.dishwashing.dishes.append(bad.dishwashing.dishes[0].duplicate(true));check(not valid(bad).ok,"duplicate dish rejected")
 bad=good.duplicate(true);bad.dishwashing.next_id+=6
 for i in range(6):bad.dishwashing.dishes.append({"id":int(bad.dishwashing.next_id)-i-1,"sink_id":int(original.id),"elapsed":0.0})
 check(not valid(bad).ok,"seventh dish rejected")
 bad=good.duplicate(true);bad.dishwashing.dishes[0].sink_id=999999;check(not valid(bad).ok,"missing sink rejected")
 bad=good.duplicate(true);bad.records[0].plate_owner="dish_queue";bad.records[0].dish_id=9999;bad.records[0].plate_target_id=-1;check(not valid(bad).ok,"unbacked queue ownership rejected")
 game._assign_service_job(game.worker("cleaner"),game.staff_states.find(game.worker("cleaner")));good=game._service_save_snapshot()
 bad=good.duplicate(true)
 for worker in bad.staff:
  if worker.job_kind=="wash":worker.job_elapsed=3.0
 check(not valid(bad).ok,"wash elapsed mismatch rejected")
 # A second cleaner uses another sink instead of double-washing one plate.
 r=game.setup_dirty(false);fill(2,int(original.id));fill(2,int(second.id))
 game.model.cleaners=2;game.model.duty_targets.cleaner=2;game._update_people();game._sync_staff_duty()
 var workers=[]
 for worker in game.staff_states:
  if worker.role=="cleaner":
   game._assign_service_job(worker,game.staff_states.find(worker));workers.append(worker)
 check(workers.size()==2 and workers[0].job_kind=="wash" and workers[1].job_kind=="wash" and workers[0].station_id!=workers[1].station_id,"multiple cleaners split across different sinks")
 for worker in workers:
  worker.pos=game.model.cell_center(game.model.workface_cell(game.model.get_item(int(worker.station_id))))
  worker.node.position=Vector3(worker.pos.x,0,worker.pos.y)
 duty("waiter",false);advance(4.0)
 check(is_equal_approx(workers[0].job_elapsed,4.0) and is_equal_approx(workers[1].job_elapsed,4.0),"separate sinks wash concurrently")
 roundtrip("parallel washing")
 good=game._service_save_snapshot()
 bad=good.duplicate(true);bad.staff[0]="broken";check(not valid(bad).ok,"malformed staff is rejected without a runtime error")
 bad=good.duplicate(true)
 for worker in bad.staff:
  if worker.job_kind=="wash":worker.job_dish_id={}
 check(not valid(bad).ok,"malformed dish identity is rejected without a runtime error")
 bad=good.duplicate(true);bad.erase("dishwashing");check(not valid(bad).ok,"format four requires queue ledger")
 bad=good.duplicate(true);bad.version=3;check(not valid(bad).ok,"legacy format cannot conceal newer dish queues")
 bad=good.duplicate(true)
 var first_job=-1;var last_job=-1
 for i in bad.staff.size():
  if bad.staff[i].job_kind=="wash":
   if first_job<0:first_job=i
   else:last_job=i
 bad.staff[last_job].job_dish_id=bad.staff[first_job].job_dish_id;bad.staff[last_job].station_id=bad.staff[first_job].station_id;bad.staff[last_job].job_token=bad.staff[first_job].job_token
 check(not valid(bad).ok,"two cleaners cannot own the same queued dish")
 await concurrent_dropoff_cases()
 var report={"checks":checks,"failures":failures,"stages":stages,"queue_capacity":6,"wash_seconds":20,"normal_saves_suppressed":game.save_writes_suppressed}
 print("DISHWASHING_QUEUE_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)

func side_drop_case()->Dictionary:
 game.model.reset_new();game.model.ensure_basic_bin();game.model.ensure_basic_register();game._rebuild_furniture();game._update_people()
 var r=game.setup_dirty(false)
 var basin=sink();basin.x=6;basin.z=4;basin.rot=0
 var register=game.model.checkout_register();register.x=2;register.z=6;register.rot=0
 var interaction_cells=[Vector2i(5,4),Vector2i(7,4),Vector2i(6,5),Vector2i(8,4),Vector2i(10,4),Vector2i(9,5)]
 # Relocate the complete fixture dining pair; keep its save ledger valid.
 for group in game.model.dining_sets:
  var table=game.model.get_item(int(group.table_id));var seat=game.model.get_item(int(group.seat_id))
  if Vector2i(int(table.x),int(table.z)) in interaction_cells or Vector2i(int(seat.x),int(seat.z)) in interaction_cells:
   table.x-=2;seat.x-=2
 game.model.rebuild_dining_sets()
 game.model.items=game.model.items.filter(func(item):return item.kind=="sink" or Vector2i(int(item.x),int(item.z)) not in interaction_cells)
 var alternate=basin.duplicate(true);alternate.id=game.model._next_item_id;game.model._next_item_id+=1;alternate.x=9
 game.model.items.append(alternate);game.model.revision+=1;game._rebuild_furniture()
 for i in game.staff_states.size():
  var worker=game.staff_states[i];worker.on_duty=false;worker.pos=Vector2(1.5,3.5+i)
 var cleaner=game.worker("cleaner");var waiter=game.worker("waiter")
 cleaner.on_duty=true;waiter.on_duty=true
 fill(1,int(basin.id));game.dishwashing.dishes[game.dishwashing.dishes.keys()[0]].elapsed=5.0
 cleaner.pos=Vector2(6.5,5.5)
 check(game.dishwashing.assign(cleaner,game.staff_states.find(cleaner)),"concurrent fixture assigns one janitor")
 cleaner.destination=Vector2i(6,5);cleaner.job_elapsed=5.0
 waiter.pos=Vector2(5.5,3.5);waiter.job_kind="cleanup";waiter.job_step=1;waiter.job_elapsed=0.0
 waiter.job_guest_id=int(r.guest.id);waiter.job_token=int(r.token);waiter.station_id=int(basin.id)
 r.plate_owner="staff";r.plate_staff_index=game.staff_states.find(waiter);r.dish_sink_id=int(basin.id)
 r.dishes_collected=true;r.table_wiped=false;r.drink_owner="cleared"
 return {"record":r,"basin":basin,"alternate":alternate,"cleaner":cleaner,"waiter":waiter}
func block_drop_cells(cells:Array)->Array:
 var blockers=[]
 for cell in cells:
  var blocker={"id":game.model._next_item_id,"kind":"stove","x":cell.x,"z":cell.y,"rot":0}
  game.model._next_item_id+=1;game.model.items.append(blocker);blockers.append(blocker)
 game.model.revision+=1
 return blockers
func finish_drop(r:Dictionary)->bool:
 for tick in 240:
  game.advance(.05)
  if r.plate_owner=="dish_queue":return true
 return false
func concurrent_dropoff_cases():
 var art=preload("res://scripts/cafe_sink_wash_art.gd")
 for rotation in 4:
  var before=art.drop_geometry(rotation,.65-.00001,Vector2(-20,-18),0)
  var after=art.drop_geometry(rotation,.65+.00001,Vector2(-20,-18),0)
  check(before.center.distance_to(after.center)<.001,"drop path is continuous at ownership beat rotation "+str(rotation))
  var low=art.drop_geometry(rotation,1,Vector2.ZERO,0)
  var high=art.drop_geometry(rotation,1,Vector2.ZERO,1)
  check(is_equal_approx(low.center.distance_to(high.center),2.2),"different queued dishes have distinct stack slots rotation "+str(rotation))
 # The preceding legacy cases deliberately hire a second cleaner. Start this
 # focused group with a fresh synthetic roster so save cardinality stays exact.
 for player in game.audio_players.values():player.stop();player.stream=null
 game.queue_free();await process_frame
 game=Fixture.new();root.add_child(game);await process_frame
 game.set_process(false);game.illustration.set_process(false)
 var c=side_drop_case();var r=c.record
 check(game._service_destination(c.waiter,c.basin,Vector2i(5,3))==Vector2i(5,4),"washing leaves another physical drop side available")
 var together=false;var reached=false
 for tick in 80:
  var wash=float(c.cleaner.job_elapsed);var drop=float(c.waiter.job_elapsed)
  game.advance(.05)
  if c.waiter.art_action=="dropping_dishes" and r.plate_owner=="staff" and c.waiter.job_elapsed>=.2:
   together=c.cleaner.job_elapsed>wash and c.waiter.job_elapsed>drop;reached=true;break
 check(reached and together,"washing and side-drop advance simultaneously before contact")
 var wash_elapsed=c.cleaner.job_elapsed;var drop_elapsed=c.waiter.job_elapsed
 game.paused=true;game._process(.5)
 check(c.cleaner.job_elapsed==wash_elapsed and c.waiter.job_elapsed==drop_elapsed,"pause freezes both concurrent gestures")
 roundtrip("concurrent side drop before contact")
 r=record();var cleaner=game.worker("cleaner")
 check(finish_drop(r) and game.dishwashing.count_at(int(c.basin.id))==2,"reloaded side drop deposits exactly once without stopping wash")
 check(cleaner.job_kind=="wash" and cleaner.job_elapsed>5.0 and cleaner.job_elapsed<20.0,"side drop preserves janitor job/progress")
 check(game.dishwashing.snapshot().dishes.size()==2 and game.dishwashing.deposit(r,game.worker("waiter"),game.staff_states.find(game.worker("waiter")),c.basin),"concurrent handoff remains replay-safe")
 # The already-carried payload must change sinks when capacity is exhausted.
 c=side_drop_case();r=c.record;r.dish_sink_id=-1;fill(5,int(c.basin.id))
 game._prepare_cleanup_step(c.waiter,game.staff_states.find(c.waiter))
 check(int(r.dish_sink_id)==int(c.alternate.id) and game.dishwashing.load_at(int(c.basin.id))==6 and game.dishwashing.load_at(int(c.alternate.id))==1,"full sink redirects carried dish and reserves one alternate slot")
 check(finish_drop(r) and game.dishwashing.count_at(int(c.alternate.id))==1 and game.dishwashing.count_at(int(c.basin.id))==6,"full-sink fallback physically deposits at alternate only")
 # An active wash plus blocked lateral approaches must not monopolize all sinks.
 c=side_drop_case();r=c.record
 block_drop_cells([Vector2i(5,4),Vector2i(7,4)])
 c.waiter.job_elapsed=.2
 game._prepare_cleanup_step(c.waiter,game.staff_states.find(c.waiter))
 check(int(r.dish_sink_id)==int(c.alternate.id) and c.waiter.job_elapsed==0.0,"unusable approach redirects to another sink and restarts its physical drop gesture")
 check(game.dishwashing.load_at(int(c.basin.id))==1 and game.dishwashing.load_at(int(c.alternate.id))==1,"alternate selection transfers reservation without duplicate ownership")
 check(finish_drop(r) and game.dishwashing.count_at(int(c.alternate.id))==1,"blocked-side alternate sink completes without deadlock")
 # With no immediate drop side, keep the held dish and reserved capacity.
 c=side_drop_case();r=c.record
 var blockers=block_drop_cells([Vector2i(5,4),Vector2i(7,4),Vector2i(8,4),Vector2i(10,4),Vector2i(9,5)])
 advance(1.0)
 check(r.plate_owner=="staff" and int(r.dish_sink_id)==int(c.basin.id) and game.dishwashing.count_at(int(c.basin.id))==1,"all blocked approaches preserve carried dish and original reservation")
 check(c.cleaner.job_elapsed>5.0,"waiting drop does not stop janitor washing")
 game.model.items.erase(blockers[1]);game.model.revision+=1
 check(finish_drop(r) and game.dishwashing.count_at(int(c.basin.id))==2,"unblocked side retries and completes without deadlock")
 check(game.dishwashing.load_at(int(c.basin.id))<=6 and game.dishwashing.count_at(int(c.alternate.id))==0,"retry keeps capacity bounded and avoids phantom alternate deposits")
