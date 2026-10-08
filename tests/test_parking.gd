extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Parking=preload("res://scripts/cafe_parking.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
var failures=[]
var checks=0
var phases={}
func _initialize():call_deferred("run")
func check(value:bool,label:String):
 checks+=1
 if not value:failures.append(label);push_error(label)
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
func owned():
 var m=Model.new();m.coins=10000;m.begin_decoration_session();check(m.buy_parking(),"buy fixed parking");m.finish_decoration_session();return m
func step(m,seconds:float):
 for frame in range(ceili(seconds/.1)):
  m._arrival_elapsed=0.0;m._tick_step(.1)
  for visit in m.parking_visits:phases[visit.phase]=true
func parking_step(m,seconds:float):
 for frame in range(ceili(seconds/.1)):
  Parking.advance(m,.1);m.OutsideQueue.advance(m,.1)
  for visit in m.parking_visits:phases[visit.phase]=true
func snapshot(m):
 var state={}
 for key in ["parking_visits","parking_owned","parking_paid_cost","customers","outside_queue","coins","items","dining_sets","built_walls","wall_attachments","shell_products","shell_segment_products","floor_finishes","floor_style","owned_parcels","expanded","width","depth","cooks","waiters","cleaners","cashiers","included_bin_pending","included_checkout_pending","operating_open","duty_targets","duty_counts","served","total_earned","total_cleaned","payroll_elapsed","payroll_accrued","wages_due","total_wages_paid","_next_customer_id","_next_item_id","_next_wall_id","_next_attachment_id","next_checkout_ticket","_arrival_elapsed","_walking_customer_id","service_snapshot"]:state[key]=m.get(key)
 return encoded(state)
func roundtrip(m,label:String):
 var path="user://parking-"+label+".json"
 check(m.save(path),label+" save: "+m.last_error)
 if not FileAccess.file_exists(path):return null
 var hash=FileAccess.get_sha256(path);var copy=Model.new();check(copy.load_save(path),label+" load: "+copy.last_error)
 check(same(snapshot(m),snapshot(copy)),label+" exact snapshot preserved")
 check(FileAccess.get_sha256(path)==hash,label+" source bytes unchanged")
 return copy
func invalid(m,raw:Dictionary,label:String):
 var path="user://parking-invalid-"+label+".json";var f=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(raw));f.close()
 var before=snapshot(m);var hash=FileAccess.get_sha256(path)
 check(not m.load_save(path),label+" rejected")
 check(same(before,snapshot(m)),label+" rejected atomically")
 check(hash==FileAccess.get_sha256(path),label+" rejected bytes unchanged")
func run():
 check(OS.get_environment("XDG_DATA_HOME")!="" and OS.get_user_data_dir().begins_with(OS.get_environment("XDG_DATA_HOME")),"disposable generated save profile")
 var m=Model.new();var wallet=m.coins
 check(not m.parking_owned and m.parking_visits.is_empty(),"new parking unowned/empty")
 check(not m.buy_parking() and m.coins==wallet,"purchase requires Decorate")
 m.begin_decoration_session();check(not m.buy_parking() and m.coins==wallet,"insufficient funds atomic")
 m.coins=10000;check(m.buy_parking() and m.coins==8000 and m.parking_paid_cost==2000,"one-time configured purchase")
 check(not m.buy_parking() and m.coins==8000,"repeat purchase cannot charge")
 roundtrip(m,"session-owned")
 check(m.parking_refund()==2000,"saving retains same-session receipt")
 check(m.sell_parking() and m.coins==10000,"same-session sale full refund")
 check(not m.sell_parking() and m.coins==10000,"repeat sale cannot mint money")
 check(m.buy_parking(),"repurchase after cancellation");m.finish_decoration_session();m.begin_decoration_session()
 check(m.parking_refund()==1000 and m.sell_parking() and m.coins==9000,"Done ends full refund")
 check(m.buy_parking(),"buy before load");var loaded=roundtrip(m,"owned")
 loaded.begin_decoration_session();check(loaded.parking_refund()==1000,"load ends full refund entitlement")
 # Old saves migrate without retroactive ownership, charge, or rewrite.
 var legacy=Model.new();check(legacy.save("user://parking-legacy-source.json"),"legacy source")
 var raw=JSON.parse_string(FileAccess.get_file_as_string("user://parking-legacy-source.json"));raw.erase("parking")
 var f=FileAccess.open("user://parking-legacy.json",FileAccess.WRITE);f.store_string(JSON.stringify(raw));f.close()
 var old_hash=FileAccess.get_sha256("user://parking-legacy.json")
 check(m.load_save("user://parking-legacy.json") and not m.parking_owned and m.parking_visits.is_empty() and m.coins==Model.INITIAL_COINS,"missing parking migrates empty, wallet preserved")
 check(old_hash==FileAccess.get_sha256("user://parking-legacy.json"),"migration never rewrites source")
 # Real lifecycle starts in car, then one driver, one dining identity, return/car exit.
 m=owned();check(Parking.reserve(m),"reserve a real bay and ID")
 var id=int(m.parking_visits[0].id);check(m.customers.is_empty() and m.outside_queue.is_empty() and Parking.visual_walkers(m).is_empty(),"car arrival owns no table/service or visible pedestrian")
 m.begin_decoration_session();wallet=m.coins;check(not m.sell_parking() and m.coins==wallet,"reserved bay blocks sale");m.finish_decoration_session()
 roundtrip(m,"car-arriving")
 parking_step(m,17.0);check(m.parking_visits[0].phase=="walking_in","driver appears only after car parks")
 check(Parking.visual_walkers(m).size()==1 and Parking.visual_walkers(m)[0].id==id,"driver keeps one guest ID")
 roundtrip(m,"walking-in")
 for frame in range(500):
  parking_step(m,.1)
  if not m.customers.is_empty():break
 check(m.customers.size()==1 and m.customers[0].id==id and m.customers[0].parking_visit,"normal admission transfers original driver")
 check(m.parking_visits[0].phase=="dining" and Parking.visual_walkers(m).is_empty(),"admitted driver drawn once")
 check(Vector2(m.customers[0].x,m.customers[0].z)==Parking.HANDOFF,"pavement handoff keeps exact position")
 roundtrip(m,"dining-arrival")
 for frame in range(4000):
  step(m,.1)
  if m.parking_visits.is_empty() or m.parking_visits[0].phase=="walking_return":break
 check(not m.parking_visits.is_empty() and m.parking_visits[0].phase=="walking_return","paid dining exit returns to own car")
 check(m.served==1 and m.total_earned==Model.MEAL_PAYMENT,"one dinner pays once; parking generates no income")
 check(m.customers.size()==1 and m.customers[0].phase=="dirty","dirty table ownership survives driver return")
 roundtrip(m,"walking-return")
 for frame in range(1000):
  step(m,.1)
  if m.parking_visits.is_empty() or m.parking_visits[0].phase=="car_departing":break
 check(m.parking_visits[0].phase=="car_departing" and Parking.visual_walkers(m).is_empty(),"boarding hides driver before car departs")
 roundtrip(m,"car-departing")
 step(m,40);check(m.parking_visits.is_empty() and m.served==1,"exit releases bay exactly once")
 m.begin_decoration_session();check(m.sell_parking(),"empty parking can sell after trip")
 # Pending car cannot be overtaken by a later prospective guest.
 m=owned();check(Parking.reserve(m) and m.OutsideQueue.add(m),"mixed arrival requests")
 var later=m.outside_queue[0];later.x=m.OutsideQueue.target(later.slot).x;later.z=m.OutsideQueue.target(later.slot).y;later.route_index=2
 m.OutsideQueue.advance(m,.1);check(m.customers.is_empty(),"later queue guest cannot overtake inbound car")
 parking_step(m,40);check(not m.customers.is_empty() and int(m.customers[0].id)==1,"oldest car request admitted first")
 # Queue timeout and close return car guests, never send them to street endpoints.
 m=owned();m._spawn_walkers(2)
 check(Parking.reserve(m),"reserve when tables occupied")
 parking_step(m,55);check(m.parking_visits[0].phase=="queued","full dining room reuses existing queue")
 roundtrip(m,"queued")
 var q=m.outside_queue.filter(func(v):return int(v.id)==int(m.parking_visits[0].id))[0]
 q.wait_seconds=m.OutsideQueue.WAIT_SECONDS-.05
 var at=Vector2(q.x,q.z);m.OutsideQueue.advance(m,.1)
 check(m.parking_visits[0].phase=="walking_return" and m.parking_visits[0].walk_position==at and not m.outside_queue.has(q),"queue timeout transfers exact position to own car return")
 roundtrip(m,"timeout")
 parking_step(m,60);check(m.parking_visits.is_empty() and m.served==0,"timed-out trip exits without reward")
 for phase in ["car_arriving","walking_in","queued","dining"]:
  m=owned()
  if phase=="queued":m._spawn_walkers(2)
  Parking.reserve(m)
  if phase=="walking_in":parking_step(m,17)
  if phase in ["queued","dining"]:parking_step(m,50 if phase=="queued" else 35)
  m.set_operating_open(false)
  roundtrip(m,"closed-"+phase)
  m.set_operating_open(true)
  for frame in range(1600):
   step(m,.1)
   if m.parking_visits.is_empty():break
  check(m.parking_visits.is_empty(),"close/reopen drains original "+phase+" trip")
 # Unfinished seated dinner retains normal abort semantics and unpaid exit.
 m=owned();Parking.reserve(m);parking_step(m,35)
 for frame in range(1000):
  step(m,.1)
  if m.customers[0].seated:break
 m.abandon_meal(m.customers[0])
 step(m,100);check(m.parking_visits.is_empty() and m.total_earned==0,"abandoned dinner returns driver without payment")
 # Demand is bounded by original two attempts/4s; no second parking clock.
 m=owned();m._spawn_customer();check(m._next_customer_id==3 and m.customers.size()+m.outside_queue.size()+Parking.pending_count(m)==2,"two mixed requests per original batch")
 for frame in range(4):m._spawn_customer()
 check(m.parking_visits.size()<=4 and m.outside_queue.size()+Parking.pending_count(m)<=6,"pending requests and bay reservations stay bounded")
 var reserved={}
 for visit in m.parking_visits:reserved[int(visit.bay)]=true
 check(reserved.size()==m.parking_visits.size(),"reserved bays unique")
 # Four occupied bays never create another car; remaining demand walks once.
 m=owned()
 for index in range(4):
  check(Parking.reserve(m),"reserve distinct bay "+str(index))
  for frame in range(400):Parking.advance(m,.1)
 check(m.parking_visits.size()==4,"all four bays can be occupied")
 var sequence=m._next_customer_id;m._spawn_customer()
 check(m.parking_visits.size()==4 and m._next_customer_id==sequence+2,"full lot falls back to two ordinary requests")
 roundtrip(m,"all-four-bays")
 # Parking cannot inherit a foot guest's not-yet-reached street endpoint.
 var queued_source=JSON.parse_string(FileAccess.get_file_as_string("user://parking-queued.json"))
 for fault in ["before-handoff","wrong-origin"]:
  raw=queued_source.duplicate(true);var v=raw.outside_queue.visitors[0]
  if fault=="before-handoff":v.x=-2.76;v.z=-82;v.route_index=0;v.heading={"$vector2":[0,1]};v.waiting=false;v.wait_seconds=0
  else:v.origin_z=82
  invalid(m,raw,"queued-"+fault)
 # Adversarial present-field validation must be atomic.
 m=owned();Parking.reserve(m);roundtrip(m,"invalid-base")
 var base=JSON.parse_string(FileAccess.get_file_as_string("user://parking-invalid-base.json"))
 for kind in ["format","ownership","cost","duplicate","id","bay","slot","phase","position","car-route","walk-route","index","driver-before-park","closed","orphan-dining","premature-return","premature-departure"]:
  raw=base.duplicate(true);var parking=Codec.new().decode(raw.parking);var v=parking.visits[0]
  match kind:
   "format":parking.format="unknown"
   "ownership":parking.owned=false
   "cost":parking.paid_cost=-1
   "duplicate":parking.visits.append(v.duplicate(true))
   "id":v.id=raw.runtime.next_customer_id
   "bay":v.bay=4
   "slot":v.slot=6
   "phase":v.phase="unknown"
   "position":v.car_position.x=100
   "car-route":v.car_route[0].x=1
   "walk-route":v.walk_route[0].x=1
   "index":v.car_index=4
   "driver-before-park":v.walk_index=1;v.walk_position=v.walk_route[0]
   "closed":raw.operating_open=false
   "orphan-dining":v.phase="dining"
   "premature-return":v.phase="walking_return";v.car_index=3;v.car_position=Parking.bay_point(v.bay);v.slot=-1;v.walk_index=4;v.walk_position=Parking.HANDOFF
   "premature-departure":v.phase="car_departing";v.car_index=0;v.car_position=Parking.bay_point(v.bay);v.car_route=Parking.car_route(v.bay,true);v.slot=-1;v.walk_index=4;v.walk_position=Parking.HANDOFF
  raw.parking=encoded(parking);invalid(m,raw,kind)
 # All scalar identity/economy/progress values reject arbitrary types before casts.
 var bad_values=[null,true,"1",[],{},INF,-INF,NAN,-100,10000000000]
 for field in ["id","bay","slot","car_index","walk_index","paid_cost"]:
  for index in range(bad_values.size()):
   raw=base.duplicate(true)
   if field=="paid_cost":raw.parking[field]=bad_values[index]
   else:
    raw.parking.visits[0][field]=bad_values[index]
    if field=="walk_index":raw.parking.visits[0].phase="car_departing";raw.parking.visits[0].cancelled=true
   # JSON cannot represent infinities; direct validation still exercises them.
   if index in [5,6,7]:
    var rejected=Parking.validate(raw.parking,m.customers,m.outside_queue,m._next_customer_id,true)
    check(rejected.get("ok",true)==false,field+" rejects nonfinite value")
   else:invalid(m,raw,field+"-type-"+str(index))
 var nonfinite=encoded({"format":Parking.FORMAT,"owned":true,"paid_cost":2000,"visits":m.parking_visits});nonfinite.visits[0].car_position["$vector2"][0]=INF
 check(not Parking.validate(nonfinite,m.customers,m.outside_queue,m._next_customer_id,true).ok,"nonfinite parking coordinate rejected")
 print("PARKING_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"phases":phases.keys(),"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
