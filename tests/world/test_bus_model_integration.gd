extends SceneTree
const Model=preload("res://scripts/core/cafe_model.gd")
const Traffic=preload("res://scripts/world/cafe_road_traffic.gd")
class TestGame extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
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
func _initialize():run.call_deferred()
func run():
 var game=TestGame.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 game.tutorial.skip();game.cafe_intro.finish();game.paused=true
 var m=game.model;var art=game.illustration
 check(art.bus_stop_pedestrians==m.road_bus and m.road_bus.bus_snapshot().state=="away","initial paused first-frame renderer binds actual holder at ready")
 var clock=m.road_bus.elapsed;var road=m.road_traffic_state.duplicate(true)
 game._process(.1);art._process(.1)
 check(m.road_bus.elapsed==clock and m.road_traffic_state==road,"actual paused Main gate holds both authorities")
 game.paused=false;m.tick(.1)
 check(m.road_bus.elapsed>clock and m.road_traffic_state.elapsed>road.elapsed,"actual model tick alone advances accepted bus and traffic")
 clock=m.road_bus.elapsed;road=m.road_traffic_state.duplicate(true);art._process(.1)
 check(m.road_bus.elapsed==clock and m.road_traffic_state==road,"renderer observation cannot advance either clock")
 game._toggle_edit();clock=m.road_bus.elapsed;road=m.road_traffic_state.duplicate(true)
 game._process(.1);art._process(.1)
 check(m.road_bus.elapsed==clock and m.road_traffic_state==road,"actual Decorate Main gate holds both authorities")
 game._toggle_edit();game.paused=true
 m.first_guest_pending=false;m.first_guest_start=Vector2.INF
 m.coins=m.parking_price()+8000;m.begin_decoration_session()
 var bought=m.buy_parking();m.finish_decoration_session()
 check(bought and m.Parking.reserve(m,2),"actual model owns synthetic original two-member party")
 for car in m.road_traffic_state.cars:car.position.y=-84+fposmod(car.position.y+23+84,168)
 m.road_traffic_state.elapsed=123.5
 check(Traffic.validate(m.road_traffic_state),"actual nondefault saved pool is valid")
 var path="user://bus-model-synthetic.json";var saved_ok=m.save(path);check(saved_ok,"save actual pool and party without bus envelope: "+m.last_error)
 if not saved_ok:game.queue_free();await process_frame;quit(1);return
 var saved_road=m.road_traffic_state.duplicate(true);var saved_party=m.parking_visits.duplicate(true);var old_bus=m.road_bus
 var raw=JSON.parse_string(FileAccess.get_file_as_string(path))
 check(not raw.parking.has("bus") and not raw.parking.has("road_bus"),"saved parking/runtime schema excludes transient holder")
 raw.parking.traffic.cars[1].id=raw.parking.traffic.cars[0].id
 var bad=FileAccess.open("user://bus-model-rejected.json",FileAccess.WRITE);bad.store_string(JSON.stringify(raw));bad.close()
 check(not m.load_save("user://bus-model-rejected.json") and m.road_bus==old_bus and m.road_traffic_state==saved_road and m.parking_visits==saved_party,"rejected actual load leaves holder/pool/party atomic")
 check(m.load_save(path),"successful actual load validates before commit: "+m.last_error)
 check(m.road_bus!=old_bus and m.road_bus.bus_snapshot().state=="away" and same(m.road_traffic_state,saved_road) and same(m.parking_visits,saved_party),"successful load restarts only transient bus, exact road/member custody retained")
 clock=m.road_bus.elapsed;art._sync_bus_controller()
 check(art.bus_stop_pedestrians==m.road_bus and m.road_bus.elapsed==clock,"paused post-load first-frame sync binds new holder without advancing")
 old_bus=m.road_bus;m.reset_new();clock=m.road_bus.elapsed;art._sync_bus_controller()
 check(m.road_bus!=old_bus and m.road_bus.bus_snapshot().state=="away" and art.bus_stop_pedestrians==m.road_bus and m.road_bus.elapsed==clock,"full reset replaces holder and paused first-frame sync is read-only")
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await create_timer(.25).timeout
 print("BUS_MODEL_INTEGRATION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
