extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Bodies=preload("res://scripts/cafe_departing_bodies.gd")
const Reception=preload("res://scripts/cafe_reception.gd")
const V1Reader=preload("res://tests/fixtures/reception_original_v15_contract.gd")
var checks=0
var failures=[]
var serial=0
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func frozen(value):return JSON.stringify(Model.RuntimeCodec.new().encode(value))
func same(a,b)->bool:
 if (a is int or a is float) and (b is int or b is float):return absf(float(a)-float(b))<1e-7
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not same(a[key],b[key]):return false
  return true
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for i in a.size():
   if not same(a[i],b[i]):return false
  return true
 return a==b
func base():
 var m=fresh();m._spawn_walkers(1)
 var guest=m.customers[0]
 # Explicit synthetic already-reserved historical service; ordinary reception
 # construction/entry is independently covered by the reception/native suites.
 var chair=m.get_item(int(guest.chair_id));guest.x=chair.x+.5;guest.z=chair.z+.5
 guest.phase="eating";guest.seated=true;guest.route=[];guest.route_index=0
 guest.paid=true;guest.settlement_mode="legacy";guest.checkout_ticket=0
 m.served=1;m.total_earned=m.MEAL_PAYMENT
 m._begin_departure(guest)
 return m
func advance(m,seconds):
 for frame in ceili(seconds/.1):
  m._arrival_elapsed=0
  for guest in m.customers:
   if guest.phase in ["dirty","cleaning"]:guest.duration=99999
  m.tick(minf(.1,seconds-float(frame)*.1))
func roundtrip(m,label):
 serial+=1;var path="user://departing-body-%s.json"%serial
 var old=[m.customers,m.reception_visits,m.departing_bodies,m.parking_visits].duplicate(true)
 check(m.save_reception(path),label+" save: "+m.last_error)
 if not FileAccess.file_exists(path):return m
 var hash=FileAccess.get_sha256(path);var loaded=fresh()
 check(loaded.load_reception(path),label+" load: "+loaded.last_error)
 check(same(old,[loaded.customers,loaded.reception_visits,loaded.departing_bodies,loaded.parking_visits]),label+" exact actors and ownership retained")
 check(FileAccess.get_sha256(path)==hash,label+" original bytes unchanged")
 return loaded
func _initialize():run.call_deferred()
func run():
 check("saveguard" in OS.get_user_data_dir(),"generated test profile only")
 var m=base();var guest=m.customers[0];var id=int(guest.id);var chair_id=int(guest.chair_id);var table_id=int(guest.table_id)
 check(not Bodies.can_split(m,guest),"seated/dismounting diner keeps dining claim")
 check(int(m.TableOccupancy.inspect(m).tables[table_id].occupant_id)==id,"old body owns chair during dismount")
 m=roundtrip(m,"before split");guest=m.customers[0]
 m._advance_walk(guest,.5)
 check(not Bodies.can_split(m,guest),"partial footprint cannot release chair")
 var prior=Vector2(guest.x,guest.z);m._advance_walk(guest,.2)
 check(Vector2(guest.x,guest.z).distance_to(prior)<=m.WALK_SPEED*.2+.00001,"clearance movement uses normal budget")
 check(Bodies.can_split(m,guest),"fully cleared body can release dining place")
 var pos=Vector2(guest.x,guest.z);var heading=guest.heading;var future=guest.route.slice(int(guest.route_index))
 check(Bodies.split(m,guest),"split creates one movement-only continuation")
 check(m.departing_bodies.size()==1 and m.departing_bodies[0].id==id and Vector2(m.departing_bodies[0].x,m.departing_bodies[0].z)==pos and m.departing_bodies[0].heading==heading and m.departing_bodies[0].route==future,"same actor, position, heading and remaining route survive split")
 check(guest.phase=="dirty" and guest.route.is_empty() and not guest.seated,"old service record becomes cleanup-only")
 var inventory=m.TableOccupancy.inspect(m)
 check(inventory.tables[table_id].occupant_id==-1 and inventory.tables[table_id].cleanup_owner_id==id,"vacated place has no live occupant and one cleanup owner")
 check(m.visual_customers().filter(func(v):return int(v.id)==id).size()==1,"renderer receives one live actor for split identity")
 check(m.departing_bodies[0].chair_id==-1 and m.departing_bodies[0].table_id==-1,"departing body has no dining claims")
 m=roundtrip(m,"immediately after split")
 # Route edits cannot block the actual body or any future leg. They need not
 # preserve the old chair once cleanup and its next occupant release it.
 var body=m.departing_bodies[0];var cell=m.Reception.cell(Vector2(body.x,body.z))
 check(m._guest_route_uses(cell),"normal furniture guards include departing body")
 var old_state=frozen([m.items,m.customers,m.departing_bodies,m.coins])
 var direction=Vector2i(roundi(body.heading.x),roundi(body.heading.y));var wall_key=m.WallGeometry.edge_between(cell,cell+direction).split(":")
 check(not m.can_place_wall(wall_key[0],int(wall_key[1]),int(wall_key[2])),"wall preview cannot cut actual departing route")
 check(old_state==frozen([m.items,m.customers,m.departing_bodies,m.coins]),"cancelled wall preview leaves body, cleanup and money unchanged")
 var shadow=m.FurnitureMotion.copy_model(m)
 check(frozen(shadow.departing_bodies)==frozen(m.departing_bodies),"layout transaction copy preserves departing route")
 var block=shadow._next_item_id;shadow._next_item_id+=1;shadow.items.append({"id":block,"kind":"plant","x":cell.x,"z":cell.y,"rot":0})
 check(Bodies.layout_error(shadow)!="","placing furniture into departure footprint is rejected")
 var initial_coins=m.coins;var initial_served=m.served;var initial_earned=m.total_earned
 m.set_operating_open(false)
 check(m.operating_status()=="Closing","closed cafe still accounts for indoor departing body")
 m=roundtrip(m,"closed mid-departure")
 advance(m,.3);m=roundtrip(m,"moved mid-departure")
 check(m.coins==initial_coins and m.served==initial_served and m.total_earned==initial_earned,"splitting and departure never award another payment")
 # Cleanup may retire before the actor reaches its handoff, without deleting
 # the body or reusing any dining identity.
 m.customers.clear();Bodies.refresh_cleanup_references(m)
 check(m.departing_bodies[0].cleanup_owner_id==-1,"finished cleanup reference retires independently")
 m=roundtrip(m,"cleanup gone while body remains")
 advance(m,30)
 check(m.departing_bodies.is_empty(),"body reaches existing street handoff once")
 check(m.served==initial_served and m.total_earned==initial_earned,"handoff never repeats revenue")
 m=roundtrip(m,"after handoff")
 var capped=base();guest=capped.customers[0];capped._advance_walk(guest,1)
 for i in Bodies.CAPACITY:capped.departing_bodies.append({"id":1000+i})
 var unchanged=frozen(guest)
 check(not Bodies.split(capped,guest) and frozen(guest)==unchanged,"full departure ledger retains original guest safely")
 capped.departing_bodies.clear();check(Bodies.split(capped,guest),"capacity release permits original continuation without reset")
 # Accepted legacy public routes need not share the new ledger endpoint.
 # Keep those old records untouched rather than producing an unsaveable body.
 var legacy=base();var historical=legacy.customers[0];legacy._advance_walk(historical,1)
 historical.route.append(Vector2(-1.5,historical.route[-1].y))
 check(legacy.save_reception("user://legacy-wide-endpoint.json"),"historical noncanonical public endpoint is valid before split")
 var legacy_state=frozen(historical)
 check(not Bodies.split(legacy,historical) and frozen(historical)==legacy_state,"legacy endpoint keeps its unchanged historical movement authority")
 check(legacy.save_reception("user://legacy-wide-endpoint-after.json"),"retained historical route stays saveable after split refusal")
 # Starter-door migration must test the actual new ledgers' body radius and
 # remaining sweep, even after their old service record became cleanup-only.
 for ledger in ["departing_bodies","reception_visits"]:
  var narrow=base();var departed=narrow.customers[0];narrow._advance_walk(departed,1)
  check(Bodies.split(narrow,departed),ledger+" migration starts from a valid split")
  narrow.wall_attachments[0].width=narrow.Footprint.LEGACY_DOOR_WIDTH
  if ledger=="reception_visits":
   narrow.departing_bodies.clear();check(Reception.add(narrow),"migration reception visitor constructed")
  var actor=narrow.get(ledger)[0]
  actor.phase="leaving";actor.x=1.5;actor.z=5.1;actor.route_origin=Vector2(1.5,5.1);actor.route_index=0
  actor.route=[Vector2(-.85,5.1),Vector2(-.85,12.5)]
  if ledger=="departing_bodies":actor.endpoint=actor.route[-1]
  else:actor.goal=actor.route[-1];actor.ready_order=-1
  narrow=roundtrip(narrow,ledger+" legacy jamb sweep")
  check(is_equal_approx(narrow.wall_attachments[0].width,narrow.Footprint.LEGACY_DOOR_WIDTH),ledger+" shoulder sweep preserves the wider starter opening")
 await parking_and_corruption()
 print("RECEPTION_CLEARANCE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)

func parking_and_corruption():
 var m=base();m.parking_owned=true;m.parking_paid_cost=m.Parking.PRICE
 check(m.Parking.reserve(m),"synthetic owned parking visit constructed")
 var visit=m.parking_visits[0];var guest=m.customers[0];visit.id=guest.id
 # Synthetic already parked diner. Both route prefixes are consumed through
 # the existing movement helper, rather than forged return coordinates.
 m.Parking._move(visit,"car_",1000.0);m.Parking._move(visit,"walk_",1000.0)
 visit.phase="dining";visit.slot=-1;guest.parking_visit=true
 m._advance_walk(guest,1.0);check(Bodies.split(m,guest),"parking diner releases cleared chair into its own departing body")
 m=roundtrip(m,"parking split")
 var path="user://departing-malformed.json";check(m.save_reception(path),"valid departure corruption baseline")
 var valid=JSON.parse_string(FileAccess.get_file_as_string(path))
 check(not V1Reader.accepts_header(valid),"actual original15 reader refuses genuine18 rather than dropping bodies")
 for mode in ["duplicate","live-diner","parking-owner","orphan-cleanup","seat-claim","over-capacity"]:
  var raw=valid.duplicate(true)
  match mode:
   "duplicate":raw.reception.departures.append(raw.reception.departures[0].duplicate(true))
   "live-diner":raw.runtime.customers[0].phase="leaving"
   "parking-owner":raw.reception.departures[0].parking_visit=false
   "orphan-cleanup":raw.reception.departures[0].cleanup_owner_id=-1
   "seat-claim":raw.reception.departures[0].chair_id=raw.runtime.customers[0].chair_id
   "over-capacity":
    for i in 60:raw.reception.departures.append(raw.reception.departures[0].duplicate(true))
  FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(raw));var target=fresh();target.coins=888
  check(not target.load_reception(path) and target.coins==888,mode+" rejects atomically")
 var transitions=0;var income=m.total_earned;var served=m.served;var saw_return=false
 for frame in 700:
  var before={}
  for actor in m.visual_customers():
   if actor.phase not in ["dirty","cleaning"]:before[int(actor.id)]=Vector2(actor.x,actor.z)
  var prior=m.parking_visits[0].phase if not m.parking_visits.is_empty() else "done"
  advance(m,.1)
  var actors={}
  for actor in m.visual_customers():
   if actor.phase in ["dirty","cleaning"]:continue
   check(not actors.has(int(actor.id)),"one parking pedestrian authority per frame")
   actors[int(actor.id)]=true
   if before.has(int(actor.id)):check(Vector2(actor.x,actor.z).distance_to(before[int(actor.id)])<=m.WALK_SPEED*.1+.00002,"departure-to-parking handoff spends one walking budget")
  var phase=m.parking_visits[0].phase if not m.parking_visits.is_empty() else "done"
  if phase=="walking_return" and prior!="walking_return":
   transitions+=1;saw_return=true;check(m.departing_bodies.is_empty(),"parking takes over only after departing body retires")
   m=roundtrip(m,"parking handoff")
  if phase=="done":break
 check(saw_return and transitions==1 and m.parking_visits.is_empty(),"exactly one parking return then ordinary car departure")
 check(m.total_earned==income and m.served==served,"parking continuation never repeats payment")

func fresh():
 var m=Model.new();assert(m.enable_reception_review(),m.last_error);return m
