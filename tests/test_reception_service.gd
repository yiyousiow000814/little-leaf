extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Reception=preload("res://scripts/cafe_reception.gd")
class GeneratedMain extends "res://scripts/main.gd":
 var allow_cleanup=false
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model);assert(model.enable_reception_review())
  model.first_guest_pending=false;model.first_guest_start=Vector2.INF
 func _cleanup_ready(guest:Dictionary)->bool:
  # Deterministically expose the dirty-table waiting state. Once released,
  # the existing real staff jobs, movement and payload transfers do all work.
  return allow_cleanup and super._cleanup_ready(guest)
var checks=0
var failures=[]
var roundtrips=0
var captures=[]
func _initialize():
 create_timer(110.0).timeout.connect(func():printerr("RECEPTION_SERVICE_TIMEOUT");quit(2))
 run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func same(a,b)->bool:
 if (a is int or a is float) and (b is int or b is float):return absf(float(a)-float(b))<1e-7
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
func encoded(value):return Model.RuntimeCodec.new().encode(value)
func roundtrip(game,label:String):
 game.model.service_snapshot=game._service_save_snapshot()
 var guests=encoded(game.model.customers);var visitors=encoded(game.model.reception_visits);var service=encoded(game.model.service_snapshot)
 var path="user://reception-service-"+label+".json";var ok=game.model.save_reception(path)
 check(ok,label+" complete service saves: "+game.model.last_error)
 if not ok:return
 var hash=FileAccess.get_sha256(path);ok=game.model.load_reception(path);check(ok,label+" complete service reloads: "+game.model.last_error)
 if not ok:return
 check(FileAccess.get_sha256(path)==hash and same(encoded(game.model.customers),guests) and same(encoded(game.model.reception_visits),visitors) and same(encoded(game.model.service_snapshot),service),label+" preserves old and new responsibilities exactly")
 if label=="old-cleanup-new-seated":
  var raw=JSON.parse_string(FileAccess.get_file_as_string(path));var v=raw.reception.visitors[0]
  v.x=[];v.phase="arriving";v.street_route_format="little_leaf.street_endpoints.v1"
  raw.runtime.service.floor_tasks.walks=[{"guest_id":v.id,"pos":{"$vector2":[-2.76,82]},"cell":{"$vector2i":[-3,82]},"inside_steps":0,"dropped":false}]
  var bad="user://reception-invalid-walk-provenance.json";FileAccess.open(bad,FileAccess.WRITE).store_string(JSON.stringify(raw))
  var before=FileAccess.get_sha256(bad);var victim=fresh();victim.coins=777
  check(not victim.load_reception(bad) and victim.coins==777 and FileAccess.get_sha256(bad)==before,"reception cannot borrow unchecked legacy street provenance or mutate a rejected profile")
 game._restore_service_runtime();roundtrips+=1
func run():
 check("saveguard" in OS.get_user_data_dir(),"generated profile only")
 root.size=Vector2i(1360,880)
 var game=GeneratedMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 # Fresh-profile onboarding intentionally starts closed. This fixture opens
 # the cafe through its normal operating-state API before requesting visitors.
 game.model.set_operating_open(true)
 await capture(game,"fresh-open")
 # Bound demand to one real endpoint request at a time so the second visitor's
 # pre-service patience is not consumed by the entire first meal.
 check(Reception.add(game.model),"ordinary public request constructor accepts the first walker")
 check(game.model.customers.is_empty() and game.model.reception_visits.size()==1,"normal road walker owns no meal or seat")
 var second_requested=false
 var saw_reception_walk=false
 var seen={};var waiting_id=-1;var cleanup_id=-1;var cleanup_token=-1;var saw_wiping=false;var saw_plate_transfer=false;var ordered=false
 for frame in range(3500):
  game.model._arrival_elapsed=0.0;game._tick_live_service(.1);game._animate_staff(.1)
  if not second_requested and game.model.customers.any(func(g):return g.phase in ["dirty","cleaning"]):
   second_requested=Reception.add(game.model)
   check(second_requested,"second ordinary endpoint walker arrives after the table becomes dirty")
  for visitor in game.model.reception_visits:
   if game.floor_tasks.walks.has(int(visitor.id)) and not saw_reception_walk:
    saw_reception_walk=true;check(not game.service_guests.has(int(visitor.id)),"indoor reception footsteps are tracked without a meal record");roundtrip(game,"indoor-footsteps")
   if not seen.has(visitor.phase):seen[visitor.phase]=true;roundtrip(game,"state-"+str(visitor.phase))
   if visitor.phase=="waiting_cleaning" and visitor.seated and waiting_id<0:
    waiting_id=int(visitor.id);cleanup_id=int(visitor.cleanup_owner_id);cleanup_token=int(game.service_guests[cleanup_id].token)
    check(not game.service_guests.has(waiting_id),"seated dirty-table waiter has no meal record")
    check(game.model.customers.any(func(g):return int(g.id)==cleanup_id and g.phase in ["dirty","cleaning"]),"physically departed diner remains only as cleanup carrier")
    roundtrip(game,"old-cleanup-new-seated");await capture(game,"dirty-seat-old-cleanup");game.allow_cleanup=true
  if waiting_id>=0:
   for staff in game.staff_states:
    if staff.job_kind=="cleanup" and int(staff.job_guest_id)==cleanup_id:
     check(int(staff.job_token)==cleanup_token,"staff cleanup keeps original service token")
     if staff.art_action=="wiping":saw_wiping=true
   if game.service_guests.has(cleanup_id):
    var old=game.service_guests[cleanup_id]
    if str(old.plate_owner) in ["staff","dish_queue","clean"]:saw_plate_transfer=true
    check(not game.service_guests.has(waiting_id),"new diner receives no service until old cleanup completes")
   else:
    var found=game.model.customers.filter(func(g):return int(g.id)==waiting_id)
    if not found.is_empty():
     check(found[0].phase=="ordering" and found[0].seated,"same waiting diner begins ordering after real cleanup")
     check(int(game.service_guests[waiting_id].token)!=cleanup_token,"new diner receives a fresh service token")
     roundtrip(game,"new-ordering");await capture(game,"same-guest-new-order");ordered=true;break
 check(waiting_id>=0 and ordered,"natural two-visitor lifecycle reaches occupied dirty-table cleanup and new order")
 check(saw_reception_walk,"ordinary reception walking retains floor traffic tracking")
 check(saw_wiping and saw_plate_transfer,"real staff collect old dish and wipe while replacement waits")
 check(game.model.served==1 and game.model.total_earned==Model.MEAL_PAYMENT,"only original paid meal earns money; waiting/admission never does")
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 game.queue_free();await process_frame;await process_frame
 if not captures.is_empty():FileAccess.open(OS.get_environment("LL_RECEPTION_CAPTURE")+"/frames.json",FileAccess.WRITE).store_string(JSON.stringify(captures,"  "))
 print("RECEPTION_SERVICE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"roundtrips":roundtrips,"seen":seen}))
 quit(0 if failures.is_empty() else 1)

func fresh():
 var m=Model.new();assert(m.enable_reception_review(),m.last_error);return m

func capture(game,label:String):
 var out=OS.get_environment("LL_RECEPTION_CAPTURE")
 if out.is_empty():return
 game._update_ui();game.illustration._process(.1);game.illustration.queue_redraw()
 for frame in 5:await process_frame
 await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png(out+"/"+label+".png")==OK,label+" actual viewport captured")
 captures.append({"label":label,"customers":encoded(game.model.customers),"visitors":encoded(game.model.reception_visits),"staff":encoded(game.staff_states),"served":game.model.served,"earned":game.model.total_earned})
