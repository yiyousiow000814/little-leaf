extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Queue=preload("res://scripts/cafe_outside_queue.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
class TestMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;model.reset_new();model.ensure_basic_bin();model.ensure_basic_register()
var checks=0
var failures=[]
var roundtrips=0
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func encoded(value):return Codec.new().encode(value)
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
func full_room():
 var model=Model.new();model.tick(4.0)
 check(model.customers.size()==2 and model.outside_queue.is_empty(),"first arrival retains direct reachable-seat admission")
 model.tick(12.0)
 check(model.customers.size()==2 and model.outside_queue.size()==Queue.CAPACITY,"full restaurant produces six real prospective visitors on normal four-second cadence")
 return model
func queue_step(model,seconds:float):
 for frame in range(ceili(seconds/.1)):Queue.advance(model,.1)
func roundtrip(model,label:String):
 var path="user://outside-"+label+".json"
 check(model.save(path),label+" saves: "+model.last_error)
 if not FileAccess.file_exists(path):return null
 var bytes=FileAccess.get_sha256(path);var copy=Model.new()
 var ok=copy.load_save(path);check(ok,label+" loads: "+copy.last_error)
 if not ok:return null
 check(same(copy.outside_queue,model.outside_queue) and same(copy.customers,model.customers) and copy._next_customer_id==model._next_customer_id,label+" preserves exact identities, positions, routes and clocks")
 check(FileAccess.get_sha256(path)==bytes,label+" load does not rewrite source bytes")
 roundtrips+=1;return copy
func reject(model,raw:Dictionary,label:String):
 var path="user://outside-invalid-"+label+".json"
 var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(raw));file.close()
 var bytes=FileAccess.get_sha256(path)
 var before=encoded({"customers":model.customers,"queue":model.outside_queue,"coins":model.coins,"next_id":model._next_customer_id,"open":model.operating_open,"items":model.items,"service":model.service_snapshot})
 check(not model.load_save(path),label+" malformed queue rejected")
 check(FileAccess.get_sha256(path)==bytes,label+" rejected source bytes preserved")
 check(same(before,encoded({"customers":model.customers,"queue":model.outside_queue,"coins":model.coins,"next_id":model._next_customer_id,"open":model.operating_open,"items":model.items,"service":model.service_snapshot})),label+" rejected load leaves live state unchanged")
func adversarial(model):
 var base=JSON.parse_string(FileAccess.get_file_as_string("user://outside-full.json"))
 for kind in ["format","over-capacity","duplicate-id","customer-id","future-id","duplicate-slot","interior-position","off-route","diagonal-route","route-index","table-owner","seated","negative-clock","closed-request"]:
  var raw=base.duplicate(true);var data=Codec.new().decode(raw.outside_queue);var visitor=data.visitors[0]
  match kind:
   "format":data.format="unknown"
   "over-capacity":data.visitors.append(data.visitors[0].duplicate(true))
   "duplicate-id":data.visitors[1].id=visitor.id
   "customer-id":visitor.id=model.customers[0].id
   "future-id":visitor.id=model._next_customer_id
   "duplicate-slot":data.visitors[1].slot=visitor.slot
   "interior-position":visitor.x=2.5
   "off-route":visitor.x=Queue.LANE_X
   "diagonal-route":visitor.route[0].x+=.1
   "route-index":visitor.route_index=3
   "table-owner":visitor.table_id=model.customers[0].table_id
   "seated":visitor.seated=true
   "negative-clock":visitor.wait_seconds=-.1
   "closed-request":raw.operating_open=false
  raw.outside_queue=encoded(data);reject(model,raw,kind)
 var invalid=encoded({"format":Queue.FORMAT,"visitors":model.outside_queue})
 invalid.visitors[0].x=INF
 check(not Queue.validate(invalid,model.customers,model._next_customer_id).ok,"nonfinite queue coordinate rejected before publication")
func run():
 check(OS.get_environment("XDG_DATA_HOME")!="" and OS.get_user_data_dir().begins_with(OS.get_environment("XDG_DATA_HOME")),"all saves use disposable synthetic profile")
 var model=full_room();var wallet=model.coins;var earned=model.total_earned;var served=model.served
 var ids=model.outside_queue.map(func(v):return v.id)
 var before_count=model._next_customer_id
 model._spawn_customer();model._spawn_customer()
 check(model.outside_queue.size()==6 and model._next_customer_id==before_count,"bounded queue refuses further attempts without allocating IDs")
 check(model.outside_queue.all(func(v):return v.table_id==-1 and v.chair_id==-1 and not v.seated),"prospective visitors own no table or chair")
 check(model.outside_queue[0].origin_z==82.0 and model.outside_queue[1].origin_z==-82.0,"real queued arrivals start at both original street ends")
 check(model.outside_queue[0].wait_seconds==0.0,"street approach is separate from outside waiting")
 var initial=Vector2(model.outside_queue[0].x,model.outside_queue[0].z)
 Queue.advance(model,.1)
 check(is_equal_approx(initial.distance_to(Vector2(model.outside_queue[0].x,model.outside_queue[0].z)),Model.WALK_SPEED*.1),"queued visitor physically walks at established speed")
 roundtrip(model,"full");adversarial(model)
 queue_step(model,65.0)
 check(model.outside_queue.size()==6 and model.outside_queue.all(func(v):return Queue.settled(v)),"both street-end approaches reach distinct readable outside positions")
 var slots={}
 for visitor in model.outside_queue:
  check(Vector2(visitor.x,visitor.z).distance_to(Queue.target(visitor.slot))<.00001,"settled visitor stands at its real slot")
  slots[visitor.slot]=true
 check(slots.size()==6,"outside slots remain distinct")
 check(model.coins==wallet and model.total_earned==earned and model.served==served,"outside approach/wait creates no reward")
 roundtrip(model,"settled")
 var head=model.outside_queue[0];var at=Vector2(head.x,head.z);var id=int(head.id)
 var finished=model.customers[0];var freed_table=int(finished.table_id)
 finished.phase="cleaning";finished.elapsed=0.0;finished.duration=.05
 var cleaned=model.total_cleaned
 model.tick(.1)
 var promoted=model.customers.filter(func(g):return int(g.id)==id)
 check(model.total_cleaned==cleaned+1 and not model.customers.has(finished),"actual cleanup completion releases the former dining reservation")
 check(promoted.size()==1 and not model.outside_queue.any(func(v):return v.id==id),"released reachable table admits FIFO head exactly once with same identity")
 if not promoted.is_empty():
  var guest=promoted[0]
  check(int(guest.table_id)==freed_table,"FIFO admission uses the table that cleanup actually released")
  check(Vector2(guest.x,guest.z)==at and guest.phase=="arriving" and not guest.seated and guest.elapsed==0.0,"promotion preserves physical position and starts a real entrance walk")
  var prior=at;var safe=true
  for point in guest.route:
   safe=safe and not model.segment_blocked(prior,point) and (absf(point.x-prior.x)<.00001 or absf(point.y-prior.y)<.00001);prior=point
  check(safe,"promoted route uses cardinal unobstructed entrance segments")
 roundtrip(model,"promoted")
 # Reachability is assessed afresh; an unowned chair cannot create admission.
 var blocked=full_room();queue_step(blocked,65.0);blocked.customers.clear()
 for item in blocked.items:
  if item.kind in ["chair","bench"]:item.x=17;item.z=17
 blocked.revision+=1;var blocked_ids=blocked.outside_queue.map(func(v):return v.id)
 Queue.advance(blocked,.1)
 check(blocked.customers.is_empty() and blocked.outside_queue.map(func(v):return v.id)==blocked_ids,"free unreachable seats retain FIFO queue without reservation")
 var closing=full_room();var close_ids=closing.outside_queue.map(func(v):return v.id)
 closing.set_operating_open(false)
 check(closing.outside_queue.all(func(v):return v.phase=="outside_return"),"closing cancels every pending outside request")
 var closed_copy=roundtrip(closing,"closed-returning")
 closing.set_operating_open(true);var next=closing._next_customer_id;closing._spawn_customer()
 check(closing.outside_queue.size()==6 and closing._next_customer_id==next,"returning actors count toward bound after reopening")
 closing.set_operating_open(false);queue_step(closing,120.0)
 check(closing.outside_queue.is_empty() and closing.served==0 and closing.total_earned==0,"cancellation completes real return routes and retires visitors without reward")
 roundtrip(closing,"retired")
 var timeout=full_room();queue_step(timeout,65.0)
 for visitor in timeout.outside_queue:visitor.wait_seconds=Queue.WAIT_SECONDS-.05
 Queue.advance(timeout,.1)
 check(timeout.outside_queue.all(func(v):return v.phase=="outside_return"),"documented outside wait limit starts real return routes")
 roundtrip(timeout,"timeout-returning")
 queue_step(timeout,120.0)
 check(timeout.outside_queue.is_empty() and timeout.served==0 and timeout.total_earned==0,"timed-out requests retire without service cleanup or income")
 var legacy=Model.new();check(legacy.save("user://outside-legacy-source.json"),"legacy missing-field fixture created")
 var raw=JSON.parse_string(FileAccess.get_file_as_string("user://outside-legacy-source.json"));raw.erase("outside_queue")
 var file=FileAccess.open("user://outside-legacy.json",FileAccess.WRITE);file.store_string(JSON.stringify(raw));file.close()
 var old_bytes=FileAccess.get_sha256("user://outside-legacy.json")
 check(model.load_save("user://outside-legacy.json") and model.outside_queue.is_empty(),"older save without optional queue field loads empty queue")
 check(FileAccess.get_sha256("user://outside-legacy.json")==old_bytes,"older source bytes remain unchanged")
 # Full Main integration verifies queue isolation from the meal deadline ledger.
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 game.model.tick(16.0);game._sync_service_guests();game.floor_tasks.observe_walks()
 check(game.model.outside_queue.size()==6 and game.service_guests.size()==game.model.customers.size(),"queued actors do not create service records")
 check(game.model.outside_queue.all(func(v):return not game.service_guests.has(int(v.id))),"queue IDs have no meal/service authority")
 game._advance_meal_wait(120.0)
 check(game.service_guests.values().all(func(r):return r.meal_wait_seconds==0.0),"street/outside approach does not consume seated 70/120-second patience")
 var queue_before=encoded(game.model.outside_queue);game.paused=true;game._process(2.0)
 check(same(queue_before,encoded(game.model.outside_queue)),"pause freezes outside motion and wait")
 game.paused=false;game.editing=true;game._process(2.0)
 check(same(queue_before,encoded(game.model.outside_queue)),"Decorate freezes outside motion and wait")
 check(game.floor_tasks.messes.is_empty() and game.floor_tasks.walks.size()==game.model.customers.size(),"exterior queue creates no indoor litter or cleaning task")
 game.editing=false;game.paused=false;game.speed=2.0
 if game.cafe_intro!=null:game.cafe_intro.active=false
 game.compact_ui.viewport_too_small=false
 var moving=game.model.outside_queue[0];var start=Vector2(moving.x,moving.z)
 game._process(.1)
 check(is_equal_approx(Vector2(moving.x,moving.z).distance_to(start),Model.WALK_SPEED*.2),"2x speed advances outside motion by simulation time")
 game.paused=true;queue_step(game.model,65.0)
 var promoted_id=int(game.model.outside_queue[0].id)
 game.model.customers.clear();Queue.advance(game.model,.1);game._sync_service_guests()
 check(game.service_guests.has(promoted_id) and game.service_guests[promoted_id].meal_wait_seconds==0.0,"promotion creates fresh service clock after real outside waiting")
 if game.service_guests.has(promoted_id):
  var record=game.service_guests[promoted_id];var guest=record.guest
  game._advance_meal_wait(70.0)
  check(record.meal_wait_seconds==0.0 and not guest.meal_abandoned,"promotion entrance walk still consumes no seated patience")
  for frame in range(1000):
   game.model._arrival_elapsed=0.0;game.model.tick(.05)
   if guest.seated:break
  check(guest.seated and guest.phase=="ordering","promoted visitor physically reaches assigned chair")
  game._advance_meal_wait(60.0);game._advance_meal_wait(10.0)
  check(is_equal_approx(record.meal_wait_seconds,70.0) and game._guest_bubble_symbol(guest)=="angry" and not guest.meal_abandoned,"unchanged seated anger begins at 70 simulation seconds")
  game._advance_meal_wait(50.0);game._resolve_meal_deadlines()
  check(guest.meal_abandoned and guest.phase=="leaving" and not guest.paid,"unchanged unfinished seated meal departs at 120 without outside wait subtraction")
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame
 print("OUTSIDE_QUEUE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"roundtrips":roundtrips,"capacity":Queue.CAPACITY,"outside_wait_seconds":Queue.WAIT_SECONDS,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
