extends SceneTree
const Fixture=preload("res://tests/fixtures/order_reach_fixture.gd")
const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
const REAR=Vector2i(5,6)
const INVALID=Vector2i(-1,-1)
var checks=0
var failures=[]
var evidence={}
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func fixture():
 var g=Fixture.new();g.setup();return g
func cleanup(g):g.people.free();g.ui.free();g.free()
func destination(g):
 var s=g.staff_states[0]
 return g._service_destination(s,g.model.get_item(101),Vector2i(s.pos.floor()))
func assign(g):g._assign_service_job(g.staff_states[0],0)
func pin_order(g):
 var s=g.staff_states[0]
 s.job_kind="order";s.job_guest_id=201;s.job_token=g.service_guests[201].token;s.station_id=101
func run():
 var g=fixture();var s=g.staff_states[0];var record=g.service_guests[201]
 check(g.model.table_service_cells(g.model.get_item(101)).is_empty(),"fixture blocks all physical table faces")
 check(not g._staff_route(0,REAR).is_empty(),"rear has an actual furniture-safe staff route")
 assign(g)
 check(s.job_kind=="order","assignment accepts reachable rear-only order")
 pin_order(g) # Exercise the other two gates independently on the old source.
 check(destination(g)==REAR,"destination selects the bounded rear cell")
 var token=record.token;var walked=true;var reached=false
 for tick in range(120):
  var previous:Vector2=s.pos
  g._animate_staff(.05)
  walked=walked and not g.model.segment_blocked(previous,s.pos) and g._staff_walkable(Vector2i(s.pos.floor()))
  if s.art_action=="taking_order":reached=true
  if record.order_done:break
 evidence.rear_only=g.snapshot()
 check(walked and reached,"waiter walks to the rear and starts an actual order gesture")
 check(record.order_done and record.token==token,"rear contact completes the original order once")
 check(record.plate_owner=="kitchen","conversation does not create or deliver food")
 cleanup(g)
 # Prefer ordinary faces, then retain a selected endpoint until invalidation.
 g=fixture();g.model.items.erase(g.model.get_item(103));assign(g);s=g.staff_states[0]
 check(destination(g)==Vector2i(4,4),"ordinary reachable table face wins over shorter rear route")
 g.model.items.append({"id":103,"kind":"plant","x":4,"z":4,"rot":0})
 check(destination(g)==REAR,"blocked ordinary pin falls back to rear")
 g.model.items.erase(g.model.get_item(103))
 check(destination(g)==REAR,"valid rear pin remains stable when an ordinary face reopens")
 g.model.items.append({"id":106,"kind":"plant","x":5,"z":6,"rot":0})
 check(destination(g)==Vector2i(4,4),"blocked rear pin replans to ordinary face")
 cleanup(g)
 # Claims use the existing endpoint ownership; transient bodies are pass-through.
 g=fixture();assign(g);s=g.staff_states[0]
 check(g._service_destination(s,g.model.get_item(101),Vector2i(3,6),[REAR])==INVALID,"same-frame claim excludes rear")
 g._add_staff("waiter",Vector2(7.5,6.5))
 var peer=g.staff_states[1];peer.job_kind="order";peer.destination=REAR
 check(destination(g)==INVALID,"peer work endpoint excludes rear")
 peer.job_kind="";peer.pos=g.model.cell_center(REAR)
 check(destination(g)==REAR,"passing body does not reserve the rear floor")
 g.model.customers.append({"id":202,"phase":"checkout_walk","checkout_cell":REAR,"checkout_register_id":999,"table_id":-1,"chair_id":-1})
 check(destination(g)==INVALID,"checkout endpoint claim excludes rear")
 cleanup(g)
 # Refuse wrong association, unsafe edges/floor and unreachable endpoints.
 for fault in ["chair_id","seat_far","not_seated","withdrawn","mobility","table_seat_wall","seat_rear_wall","furniture","unowned","unreachable"]:
  g=fixture();record=g.service_guests[201]
  match fault:
   "chair_id":record.guest.chair_id=999
   "seat_far":g.model.get_item(102).x=7
   "not_seated":record.guest.seated=false
   "withdrawn":record.guest.withdrawn=true
   "mobility":record.guest.mobility={"active":true}
   "table_seat_wall":g.model.built_walls.append(Walls.make("x",5,5,"half"))
   "seat_rear_wall":g.model.built_walls.append(Walls.make("x",5,6,"half"))
   "furniture":g.model.items.append({"id":106,"kind":"plant","x":5,"z":6,"rot":0})
   "unowned":
    for item in g.model.items:item.z+=g.Model.BASE_DEPTH-6
   "unreachable":
    for cell in [Vector2i(4,6),Vector2i(6,6),Vector2i(5,7)]:g.model.items.append({"id":200+cell.x*10+cell.y,"kind":"plant","x":cell.x,"z":cell.y,"rot":0})
  assign(g)
  check(g.staff_states[0].job_kind!="order",fault+" prevents assignment")
  pin_order(g)
  check(destination(g)==INVALID,fault+" prevents destination/contact")
  cleanup(g)
 # The actual chair association overrides incidental neighboring seats/rotation.
 g=fixture();g.model.get_item(102).kind="bench";g.model.get_item(102).rot=2
 assign(g)
 check(destination(g)==REAR,"actual occupied bench defines rear regardless of idle rotation")
 if g.model.has_method("order_rear_cell"):
  check(g.model.order_rear_cell(g.model.get_item(101),g.model.customers[0].duplicate(true))==INVALID,"stale copied guest is not the actual diner")
  check(g.model.order_rear_cell(g.model.get_item(103),g.model.customers[0])==INVALID,"rear reach cannot target unrelated furniture")
 cleanup(g)
 # A layout change invalidates a pinned endpoint even if the model's wider
 # navigation domain still finds an x=0-only route that staff cannot walk.
 g=fixture();s=g.staff_states[0];s.pos=Vector2(3.5,8.5)
 for x in range(1,g.model.width):
  if x!=3:g.model.items.append({"id":300+x,"kind":"plant","x":x,"z":7,"rot":0})
 assign(g);check(destination(g)==REAR,"real open passage permits initial rear pin")
 g.model.items.append({"id":303,"kind":"plant","x":3,"z":7,"rot":0})
 check(not g.model.path_between(Vector2i(3,8),REAR).is_empty() and g._staff_route(0,REAR).is_empty(),"fixture distinguishes model x0 detour from actual staff domain")
 check(destination(g)==INVALID,"closed real route invalidates rear pin without waiting for a stall")
 g.model.items.erase(g.model.get_item(303));check(destination(g)==REAR,"reopening real route permits retry")
 var saved=g._service_save_snapshot()
 check(not saved.staff[0].has("order_route_key") and not saved.staff[0].has("order_route_available"),"bounded route verdict is absent from save projection")
 g._clear_service_job(s)
 check(not s.has("order_route_key") and not s.has("order_route_available"),"clearing job releases route verdict")
 cleanup(g)
 # Invalidate contact in place after the real waiter has begun its gesture.
 g=fixture();record=g.service_guests[201];s=g.staff_states[0]
 for tick in range(60):
  g._animate_staff(.05)
  if s.job_elapsed>0.0:break
 var elapsed=s.job_elapsed
 g.model.built_walls.append(Walls.make("x",5,6,"half"))
 g._animate_staff(.05)
 check(elapsed>0.0 and s.job_elapsed==elapsed and not record.order_done,"new seat-to-rear wall stops an in-progress order clock")
 cleanup(g)
 # Physical tasks cannot borrow order-only conversation reach.
 for kind in ["deliver_meal","deliver_drink","cleanup"]:
  g=fixture();s=g.staff_states[0];record=g.service_guests[201]
  s.job_kind=kind;s.job_guest_id=201;s.job_token=record.token;s.job_step=2 if kind=="cleanup" else 1
  s.pos=g.model.cell_center(REAR);s.table_face_id=101;s.table_face_cell=REAR
  check(destination(g)==INVALID,kind+" cannot use rear order pin")
  cleanup(g)
 print("ORDER_REACH_EVIDENCE ",JSON.stringify(evidence))
 print("ORDER_REACH_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
