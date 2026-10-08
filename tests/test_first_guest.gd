extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Minimal=preload("res://scripts/minimal_start.gd")
const FirstGuest=preload("res://scripts/cafe_first_guest.gd")
const Main=preload("res://scripts/main.gd")
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(value:bool,label:String):
 checks+=1
 if not value:failures.append(label);printerr("FAIL ",label)
func same(a,b)->bool:
 if (a is int or a is float) and (b is int or b is float):return absf(float(a)-float(b))<1e-10
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not same(a[key],b[key]):return false
  return true
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for index in range(a.size()):
   if not same(a[index],b[index]):return false
  return true
 return a==b
func fresh():
 var model=Model.new();Minimal.apply(model);return model
func reload_model(model,path:String):
 check(model.save(path),"save generated "+path+": "+model.last_error)
 var loaded=Model.new();check(loaded.load_save(path),"reload generated "+path+": "+loaded.last_error);return loaded
func run():
 check(OS.get_environment("XDG_DATA_HOME")!="" and OS.get_user_data_dir().begins_with(OS.get_environment("XDG_DATA_HOME")),"isolated generated profile")
 var model=fresh()
 check(model.first_guest_pending,"genuine fresh profile eligible")
 model.first_guest_start=Vector2(-2.76,13.8)
 model.tick(3.99);check(model.customers.is_empty(),"normal four-second cadence retained")
 model.tick(.01)
 check(model.customers.size()==1 and absf(model.customers[0].z-13.8)<.001,"first eligible natural admission uses confirmed offscreen lane point")
 check(not model.customers[0].has("street_route_format"),"short route never invents endpoint history")
 check(not model.first_guest_pending and not model.first_guest_start.is_finite(),"first request consumes eligibility and transient hint")
 check(model.coins==1200 and model.served==0 and model.total_earned==0,"no invented reward or admission payment")
 var before=model.customers.duplicate(true)
 model=reload_model(model,"user://first-nearby-midwalk.json")
 if not same(model.customers,before):print("FIRST_GUEST_RELOAD_DIFF ",JSON.stringify({"before":before,"after":model.customers}))
 check(same(model.customers,before) and not model.first_guest_pending,"midwalk reload preserves exact visitor and cannot repeat shortcut")
 model.tick(4.0)
 check(not model.outside_queue.is_empty() and model.outside_queue[0].origin_z==-82.0,"subsequent ordinary arrival still begins at original endpoint")
 # Even a funded parking-enabled fresh fixture must consume eligibility
 # through the ordinary four-second dispatcher, not a direct reserve helper.
 var parked=fresh();parked.coins+=parked.parking_price();parked.begin_decoration_session()
 check(parked.buy_parking(),"generated parking-enabled first-visit fixture buys upgrade")
 parked.finish_decoration_session();parked.first_guest_start=Vector2(-2.76,13.8)
 parked.tick(3.99)
 check(parked.first_guest_pending and parked.customers.is_empty() and parked.parking_visits.is_empty(),"parking keeps the normal first-admission cadence")
 parked.tick(.01)
 check(parked.customers.size()==1 and parked.parking_visits.size()==1 and not parked.first_guest_pending,"normal dispatcher consumes first-visit eligibility with walking and car requests")
 var parking_before=parked.parking_visits.duplicate(true)
 parked=reload_model(parked,"user://first-parking-dispatch.json")
 check(same(parked.parking_visits,parking_before) and not parked.first_guest_pending,"parking dispatch snapshot reloads without repeating first-visit eligibility")
 var closed=fresh();closed.set_operating_open(false);closed=reload_model(closed,"user://first-closed.json")
 check(closed.first_guest_pending and not closed.operating_open and not closed.first_guest_start.is_finite(),"reload before Open retains eligibility but never stale viewport hint")
 closed.tick(6.0);check(closed.customers.is_empty() and is_zero_approx(closed._arrival_elapsed),"closed tutorial state never creates a customer")
 closed.set_operating_open(true);closed.first_guest_start=Vector2(-2.76,13.8);closed.tick(4.0)
 check(closed.customers.size()==1 and not closed.first_guest_pending,"reopening uses the one natural first visit")
 closed.set_operating_open(false);var returned=closed.customers.duplicate(true)
 closed=reload_model(closed,"user://first-withdrawn.json")
 if not same(closed.customers,returned):print("FIRST_GUEST_RETURN_DIFF ",JSON.stringify({"before":returned,"after":closed.customers}))
 check(same(closed.customers,returned) and not closed.first_guest_pending,"closing/reloading preserves real withdrawal, does not reset eligibility")
 var old=Model.new();Minimal.apply(old);old.first_guest_pending=false
 old=reload_model(old,"user://preexisting-profile.json");old.first_guest_start=Vector2(-2.76,13.8);old.tick(4.0)
 check(old.customers[0].z==82.0,"existing profile without explicit eligibility keeps endpoint approach")
 for invalid in [Vector2.INF,Vector2(-2.5,13.8),Vector2(-2.76,10.0),Vector2(-2.76,26.1)]:
  var invalid_model=fresh();invalid_model.first_guest_start=invalid;invalid_model.tick(4.0)
  check(invalid_model.customers[0].z==82.0,"unsafe or unavailable hint falls back to established endpoint")
 # Strict saved eligibility validation, not an inferred new-player heuristic.
 var payload=JSON.parse_string(FileAccess.get_file_as_string("user://preexisting-profile.json"))
 payload.first_guest_pending="true"
 FileAccess.open("user://malformed-first.json",FileAccess.WRITE).store_string(JSON.stringify(payload))
 check(not Model.new().load_save("user://malformed-first.json"),"malformed first-visit bit rejected")
 payload.first_guest_pending=true;payload.served=1;payload.total_earned=200
 FileAccess.open("user://repeated-first.json",FileAccess.WRITE).store_string(JSON.stringify(payload))
 check(not Model.new().load_save("user://repeated-first.json"),"first-visit bit cannot accompany earned progress")
 # Projection matrix is a geometry test; the separate observer proves real-time play.
 var game=Main.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.cafe_intro.finish()
 for size in [Vector2i(1360,880),Vector2i(390,844),Vector2i(430,932),Vector2i(820,1180),Vector2i(960,540)]:
  root.size=size
  await process_frame;await process_frame
  game._sync_window_scale();game._update_ui();game.illustration.update_projection()
  for zoom in [game.illustration.camera_zoom_limits().x,1.0,game.illustration.camera_zoom_limits().y]:
   game.illustration.zoom=zoom;game.illustration.update_projection()
   var old_pan=game.illustration.pan_offset;var old_zoom=game.illustration.zoom
   var start=FirstGuest.offscreen_start(game)
   check(game.illustration.pan_offset==old_pan and game.illustration.zoom==old_zoom,"offscreen query does not change player camera")
   if start.is_finite():
    check(start.y>=FirstGuest.MIN_Z and start.y<=FirstGuest.MAX_Z,"nearby start remains in supported short-route bounds")
    check(not FirstGuest.character_bounds(game.illustration,start).intersects(game.illustration.get_viewport_rect()),"entire conservative first guest bounds are outside actual viewport")
   else:check(true,"wide view safely falls back rather than popping a nearby guest into view")
 root.size=Vector2i(1360,880);await process_frame;await process_frame
 game.illustration.zoom=1.15;game.illustration.update_projection()
 for offset in [Vector2(-400,-150),Vector2(400,150),Vector2.ZERO]:
  game.illustration.pan_offset=offset;game.illustration.update_projection()
  var start=FirstGuest.offscreen_start(game)
  check(not start.is_finite() or not FirstGuest.character_bounds(game.illustration,start).intersects(game.illustration.get_viewport_rect()),"panned camera never permits visible near-street pop-in")
 game.queue_free();await process_frame;await process_frame
 print("FIRST_GUEST_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"geometry_and_generated_save_tests":true,"real_time_evidence":"separate observe_fresh_arrivals run","player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
