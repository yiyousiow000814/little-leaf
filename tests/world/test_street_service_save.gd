extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
const Tasks=preload("res://scripts/cafe_floor_tasks.gd")
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
func same(a,b)->bool:
 if (a is int or a is float) and (b is int or b is float):return absf(float(a)-float(b))<1e-9
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
func roundtrip(game,label:String)->bool:
 game.model.service_snapshot=game._service_save_snapshot()
 var expected=game.model.service_snapshot.duplicate(true);var guests=game.model.customers.duplicate(true)
 var path="user://street-service-"+label+".json"
 var saved=game.model.save(path)
 check(saved,label+" actual Main/service snapshot saves: "+game.model.last_error)
 if not saved:return false
 var before=FileAccess.get_sha256(path);var restored=Model.new()
 var loaded=restored.load_save(path);check(loaded,label+" real loader accepts: "+restored.last_error)
 if not loaded:return false
 check(FileAccess.get_sha256(path)==before,label+" load leaves save bytes unchanged")
 check(same(restored.service_snapshot,expected) and same(restored.customers,guests),label+" exact full service/customer roundtrip")
 game.model=restored;game._restore_service_runtime()
 check(same(game.floor_tasks.snapshot(),expected.floor_tasks),label+" Main restores provenance and litter history")
 roundtrips+=1
 return true
func reject_snapshot(game,raw:Dictionary,label:String):
 var path="user://street-invalid-"+label+".json"
 var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(raw));file.close()
 var bytes=FileAccess.get_sha256(path)
 var before=Codec.new().encode({"customers":game.model.customers,"service":game._service_save_snapshot(),"coins":game.model.coins})
 check(not game.model.load_save(path),label+" rejects malformed save")
 check(FileAccess.get_sha256(path)==bytes,label+" rejected save bytes unchanged")
 check(same(before,Codec.new().encode({"customers":game.model.customers,"service":game._service_save_snapshot(),"coins":game.model.coins})),label+" rejection leaves active model/service untouched")
func adversarial(game):
 var base=JSON.parse_string(FileAccess.get_file_as_string("user://street-service-road-ends.json"))
 for kind in ["unmarked","wrong-lane","wrong-cell","stale-position","other-end","past-end","staff-outside"]:
  var raw=base.duplicate(true);var codec=Codec.new();var runtime=codec.decode(raw.runtime)
  var walk=runtime.service.floor_tasks.walks[0]
  match kind:
   "unmarked":
    var guest=runtime.customers[0];guest.erase("street_route_format");guest.erase("street_origin_z");guest.z=10.8
   "wrong-lane":walk.pos.x=-2.75
   "wrong-cell":walk.cell.x+=1
   "stale-position":walk.pos.y-=.5;walk.cell=Vector2i(walk.pos.floor())
   "other-end":walk.pos.y=-82.0;walk.cell=Vector2i(walk.pos.floor())
   "past-end":walk.pos.y=82.1;walk.cell=Vector2i(walk.pos.floor())
   "staff-outside":runtime.service.staff[0].pos=Vector2(-2.76,82)
  raw.runtime=codec.encode(runtime);reject_snapshot(game,raw,kind)
 var data=game.floor_tasks.snapshot();var guests={}
 for guest in game.model.customers:guests[int(guest.id)]=guest
 var codec=Codec.new();var invalid=data.duplicate(true);invalid.walks[0].pos=Vector2(-2.76,INF)
 check(not Tasks.validate_snapshot(invalid,game.staff_states,{},guests,codec).ok,"nonfinite provenance rejects")
 check(not codec._point(Vector2(-2.76,82)) and not codec._cell(Vector2i(-3,82)),"general staff/litter coordinate bounds stay unchanged")
 # Legacy in-bounds provenance keeps the existing validation contract.
 var legacy=data.duplicate(true)
 for walk in legacy.walks:walk.pos=Vector2(2.5,6.5);walk.cell=Vector2i(2,6)
 check(Tasks.validate_snapshot(legacy,[],{},guests,codec).ok,"old in-bounds provenance remains valid")
func finish_game(game):
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 game.queue_free()
func run():
 check(OS.get_environment("XDG_DATA_HOME")!="" and OS.get_user_data_dir().begins_with(OS.get_environment("XDG_DATA_HOME")),"synthetic profile is isolated")
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 game.model._spawn_customer();game.floor_tasks.observe_walks()
 check(game.model.customers.size()==2 and game.floor_tasks.walks.size()==2,"Main records both actual endpoint arrivals")
 check(game.floor_tasks.walks[1].pos==Vector2(-2.76,82) and game.floor_tasks.walks[2].pos==Vector2(-2.76,-82),"both endpoint provenance coordinates are exact")
 var road_saved=roundtrip(game,"road-ends")
 if road_saved:adversarial(game)
 for step in range(100):game.model._arrival_elapsed=0.0;game._tick_live_service(.05)
 check(game.floor_tasks.walks[1].inside_steps==0 and game.floor_tasks.walks[2].inside_steps==0 and game.floor_tasks.messes.is_empty(),"exterior journey earns no indoor litter steps or drops")
 roundtrip(game,"mid-approach")
 for guest in game.model.customers:check(game.model.reroute_guest(guest),"real layout reroute retains approach")
 var seated=false
 for step in range(1800):
  game.model._arrival_elapsed=0.0;game._tick_live_service(.05)
  if game.model.customers.all(func(g):return g.seated):seated=true;break
 check(seated and game.model.customers.size()==2,"both original-end visitors reach seating through Main")
 if seated:
  roundtrip(game,"both-seated")
  # Seed an already-earned persisted one-drop history, then exercise the full
  # Main/service save and restore path. This is not an extra gameplay drop.
  var track=game.floor_tasks.walks[1];track.inside_steps=7;track.dropped=true
  var litter=-1
  for z in range(game.model.depth):
   for x in range(game.model.width):
    if litter<0:litter=game.floor_tasks.spawn(Vector2i(x,z),"crumbs",1,7)
  check(litter>0,"bounded indoor saved-litter fixture created on an eligible free tile")
  var history=game.floor_tasks.snapshot()
  roundtrip(game,"litter-history")
  check(same(game.floor_tasks.snapshot(),history),"saved inside_steps/dropped/mess geometry preserved exactly")
  game.floor_tasks.observe_walks()
  check(game.floor_tasks.walks[1].inside_steps==7 and game.floor_tasks.walks[1].dropped and game.floor_tasks.messes.size()==history.messes.size(),"stationary restore neither resets nor duplicates the saved litter history")
  var bad=game.model.service_snapshot.duplicate(true);bad.floor_tasks.messes[0].floor_cell=Vector2i(-3,82)
  game.model.service_snapshot=bad
  check(not game.model.save("user://street-invalid-litter.json"),"litter cells cannot borrow outer provenance bounds")
 finish_game(game);await process_frame;await process_frame
 var closing=TestMain.new();root.add_child(closing);closing.set_process(false);closing.illustration.set_process(false)
 closing.model._spawn_customer()
 for step in range(100):closing.model._arrival_elapsed=0.0;closing._tick_live_service(.05)
 closing.model.set_operating_open(false)
 check(closing.model.customers.all(func(g):return g.phase=="leaving" and g.withdrawn),"closing withdraws both exterior guests")
 roundtrip(closing,"both-withdrawn")
 for step in range(25):closing._tick_live_service(.05)
 roundtrip(closing,"withdrawal-midwalk")
 for step in range(150):closing._tick_live_service(.05)
 check(closing.model.customers.is_empty() and closing.floor_tasks.walks.is_empty() and closing.floor_tasks.messes.is_empty(),"completed withdrawal removes only finished tracking")
 check(closing.model.served==0 and closing.model.total_earned==0,"withdrawal never awards revenue")
 roundtrip(closing,"withdrawal-complete")
 finish_game(closing)
 for tween in get_processed_tweens():tween.kill()
 await process_frame;await process_frame
 print("STREET_SERVICE_SAVE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"full_main_service_roundtrips":roundtrips,"both_ends":true}))
 quit(0 if failures.is_empty() else 1)
