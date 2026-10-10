extends SceneTree
const Traffic=preload("res://scripts/cafe_road_traffic.gd")
const Stop=preload("res://scripts/bus_stop_pedestrians.gd")
var failures=[]
var checks=0
class RestoreModel extends RefCounted:
 var road_traffic_state={}
 var road_bus
 var parking_visits=[{"id":17,"members":[{"id":19,"guest_id":23,"appearance_sequence":29}]}]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var results=[]
 var turning={"phase":"car_arriving","car_position":Vector2(-4.65,5),"car_heading":Vector2(-.7,.7)}
 check(Traffic._occupied(Rect2(-6.2,3.5,.45,3),[],[turning]),"turning parking body uses normalized actual heading and full oriented extents")
 var parking_pool=Traffic.initial();var parking_bus=Stop.new();parking_bus.reset_traffic_entry()
 var parked_blocker={"phase":"car_arriving","car_position":parking_pool.cars[0].position+Vector2(0,4.5)}
 var old_parking_z=parking_pool.cars[0].position.y
 for frame in range(180):Traffic.advance(parking_pool,[parked_blocker],1.0/30.0,parking_bus)
 check(Traffic.validate(parking_pool) and parking_pool.cars[0].position.y==old_parking_z,"parking-induced headway change retains valid road pool")
 var restored=RestoreModel.new();var restore_saved=Traffic.initial();restore_saved.elapsed=123.5
 for car in restore_saved.cars:car.position.y=-84+fposmod(car.position.y+17+84,168)
 var party=restored.parking_visits.duplicate(true)
 load("res://scripts/cafe_parking.gd").restore_traffic(restored,{"traffic":restore_saved})
 check(restored.road_traffic_state==restore_saved and restored.parking_visits==party,"nondefault saved positions/elapsed/order and party identity remain exact after existing restore")
 restore_saved.cars[0].position.y+=1
 check(restored.road_traffic_state!=restore_saved,"restore owns deep copy without saved-record rewrite")
 for ahead in [true,false]:
  var pool=Traffic.initial();var flow=Stop.new();flow.elapsed=flow.bus_snapshot().dwell+15.0/2.8
  var z=flow.bus_snapshot().position.y;var target=z+(-5.301 if ahead else 5.301);var shift=target-pool.cars[5].position.y
  for car in pool.cars:car.position.y=-84+fposmod(car.position.y+shift+84,168)
  var old_clock=flow.elapsed;var old_z=pool.cars[5].position.y
  Traffic.advance(pool,[],1.0/30.0,flow)
  check((flow.elapsed==old_clock and pool.cars[5].position.y<old_z) if ahead else (flow.elapsed>old_clock and absf(pool.cars[5].position.y-old_z)<.002),"common old snapshot preserves existing ahead priority / behind follower yields %s"%ahead)
 var paused_pool=Traffic.initial();var paused_flow=Stop.new();paused_flow.reset_traffic_entry()
 var old_pool=paused_pool.duplicate(true);var paused_clock=paused_flow.elapsed;Traffic.advance(paused_pool,[],0,paused_flow)
 check(paused_pool==old_pool and paused_flow.elapsed==paused_clock,"zero model step leaves both authorities inert")
 for phase in [0.0,23.0]:
  var road=Traffic.initial()
  for car in road.cars:car.position.y=-84+fposmod(car.position.y+phase+84,168)
  var saved=road.duplicate(true);var bus=Stop.new();bus.reset_traffic_entry()
  check(Traffic.validate(road) and road==saved,"valid nondefault pool retained on transient bus entry %s"%phase)
  var clear=true;var valid=true;var stops=0;var transitions=[];var previous="away";var waits=0
  for frame in range(15000):
   var clock=bus.elapsed;Traffic.advance(road,[],1.0/30.0,bus)
   if bus.elapsed==clock:waits+=1
   var snapshot=bus.bus_snapshot()
   if snapshot.state!=previous:
    transitions.append([frame/30.0,snapshot.state])
    if snapshot.state=="stopped":stops+=1
   previous=snapshot.state
   if snapshot.visible:clear=clear and not Traffic._occupied(Traffic.bus_bounds(snapshot),road.cars,[])
   if frame%60==0:valid=valid and Traffic.validate(road)
   if stops>=3 and snapshot.state=="away":break
  check(clear,"body/turn clearance across later trips phase %s"%phase)
  check(valid,"pool IDs/order/gap/wrap stay valid phase %s"%phase)
  check(stops>=3,"subsequent complete trips make bounded progress phase %s"%phase)
  results.append({"phase":phase,"stops":stops,"wait_frames":waits,"transitions":transitions})
 var road=Traffic.initial();var shift=3.6-road.cars[5].position.y
 for car in road.cars:car.position.y=-84+fposmod(car.position.y+shift+84,168)
 var bus=Stop.new();bus.elapsed=bus.bus_snapshot().dwell-.001
 for actor in bus.actors:bus._set_actor(actor)
 var old=bus.elapsed;Traffic.advance(road,[],1.0/30.0,bus)
 check(bus.elapsed==old and not bus.merge_reserved,"occupied rejoin gives existing car priority without departing bus")
 var clear=true
 for frame in range(900):
  Traffic.advance(road,[],1.0/30.0,bus)
  var snapshot=bus.bus_snapshot()
  if snapshot.visible:clear=clear and not Traffic._occupied(Traffic.bus_bounds(snapshot),road.cars,[])
 check(clear and bus.bus_snapshot().state=="departing" and bus.elapsed>old,"merge conflict clears without overlap or deadlock")
 print("BUS_SHARED_PROTOTYPE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"results":results}));quit(0 if failures.is_empty() else 1)
