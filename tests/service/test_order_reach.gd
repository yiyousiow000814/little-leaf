extends SceneTree
const Fixture=preload("res://tests/fixtures/order_reach_fixture.gd")
const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
const REAR=Vector2i(5,6)
const INVALID=Vector2i(-1,-1)
var checks=0
var failures=[]
var evidence={}
class CountedFixture extends Fixture:
 var rear_route_calls=0
 func _staff_route(index:int,cell:Vector2i)->Array:
  if cell in [Vector2i(5,6),Vector2i(8,6)]:rear_route_calls+=1
  return super._staff_route(index,cell)
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
 peer.job_guest_id=201;peer.job_token=g.service_guests[201].token
 check(destination(g)==INVALID,"peer work endpoint excludes rear")
 g._clear_service_job(peer);peer.pos=g.model.cell_center(REAR)
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
 check(not saved.staff[0].has("work_route_key") and not saved.staff[0].has("work_route_lengths"),"bounded route verdicts are absent from save projection")
 g._clear_service_job(s)
 check(not s.has("work_route_key") and not s.has("work_route_lengths"),"clearing job releases route verdicts")
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
 idle_fallback_priority()
 targetless_cook_priority()
 combined_work_priority()
 negative_routes()
 print("ORDER_REACH_EVIDENCE ",JSON.stringify(evidence))
 print("ORDER_REACH_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)

func idle_fallback_priority():
 var g=fixture();g.setup_idle_chef()
 var chef=g.staff_states[0];var waiter=g.staff_states[1];var record=g.service_guests[201]
 check(chef.job_kind=="" and chef.idle_home_cell==INVALID and chef.pos==g.model.cell_center(REAR),"earlier idle chef has no home and stands on rear endpoint")
 check(waiter.job_kind=="order" and waiter.table_face_cell==REAR,"later waiter already owns an actual reachable rear order endpoint")
 var token=record.token;var yielded=false
 for tick in range(160):
  g._animate_staff(.05)
  if waiter.job_kind=="order":yielded=yielded or chef.destination!=REAR
  if record.order_done:break
 evidence.idle_chef=g.snapshot()
 check(yielded,"idle fallback chooses a standing alternative to productive order endpoint")
 check(record.order_done and record.token==token and record.plate_owner=="kitchen","later waiter completes same order despite earlier idle chef")
 # Protection is released as soon as the order finishes.
 chef.pos=g.model.cell_center(REAR);g._animate_staff(.05)
 check(chef.destination==REAR,"completed order releases its endpoint for idle standing")
 cleanup(g)
 g=fixture();g.setup_idle_chef();chef=g.staff_states[0]
 g.service_guests[201].guest.seated=false;g._animate_staff(.05)
 check(chef.destination==REAR,"ineligible diner releases rear protection immediately")
 cleanup(g)
 g=fixture();g.model.items.erase(g.model.get_item(103));g.staff_states.clear()
 g._add_staff("chef",g.model.cell_center(REAR));g._add_staff("waiter",Vector2(3.5,6.5))
 g._assign_service_job(g.staff_states[1],1);g._animate_staff(.05)
 check(g.staff_states[1].table_face_cell==Vector2i(4,4) and g.staff_states[0].destination==REAR,"only selected ordinary endpoint is protected; unused rear remains free")
 cleanup(g)
 # If no standing alternative exists, remaining in place is not a work claim.
 g=fixture();g.setup_idle_chef();waiter=g.staff_states[1];record=g.service_guests[201]
 waiter.pos=g.model.cell_center(REAR)
 for cell in [Vector2i(4,6),Vector2i(6,6),Vector2i(5,7)]:g.model.items.append({"id":200+cell.x*10+cell.y,"kind":"plant","x":cell.x,"z":cell.y,"rot":0})
 for tick in range(80):g._animate_staff(.05)
 check(g.staff_states[0].pos==g.model.cell_center(REAR),"no alternate standing cell does not teleport the idle chef")
 check(record.order_done,"unavoidable idle fallback does not claim the productive endpoint")
 cleanup(g)

func negative_routes():
 var g=CountedFixture.new();g.setup();var s=g.staff_states[0]
 # Two independently eligible but enclosed rear cells, one resting waiter.
 for item in g.model.items.duplicate(true):
  item.id+=10;item.x+=3;g.model.items.append(item)
 var guest=g.model.customers[0].duplicate(true)
 guest.id=202;guest.table_id=111;guest.chair_id=112;guest.x+=3;g.model.customers.append(guest)
 for cell in [Vector2i(4,6),Vector2i(6,6),Vector2i(5,7),Vector2i(7,6),Vector2i(9,6),Vector2i(8,7)]:g.model.items.append({"id":400+cell.x*10+cell.y,"kind":"plant","x":cell.x,"z":cell.y,"rot":0})
 g._sync_service_guests();g._assign_service_job(s,0)
 var first=g.rear_route_calls
 for frame in range(200):g._assign_service_job(s,0)
 evidence.negative_route_calls={"initial":first,"after_200_retries":g.rear_route_calls}
 check(first==2 and s.job_kind=="","both actual rear candidates are unreachable")
 check(g.rear_route_calls==first,"negative results memoize both diners across idle assignment retries")
 check(s.get("work_route_lengths",{}).size()==2,"cache retains only two endpoint verdicts for this start/topology")
 s.pos=Vector2(3.5,7.5);g._assign_service_job(s,0)
 check(g.rear_route_calls==first+2,"changed start cell rechecks both unreachable rear endpoints")
 first=g.rear_route_calls
 g.model.customers[0].seated=false;g._assign_service_job(s,0)
 g.model.customers[0].seated=true;g._assign_service_job(s,0)
 check(g.rear_route_calls==first and s.job_kind=="","live diner eligibility changes do not cache claims or repeat static searches")
 g.model.items.erase(g.model.get_item(446)) # Opening (4,6) changes topology without a revision bump.
 g._add_staff("waiter",Vector2(2.5,7.5));var peer=g.staff_states[1]
 peer.job_kind="order";peer.destination=REAR
 peer.job_guest_id=201;peer.job_token=g.service_guests[201].token
 g._assign_service_job(s,0)
 check(s.job_kind=="" and g.rear_route_calls==first+1,"live peer claim excludes newly open rear while topology invalidates other verdict")
 g._clear_service_job(peer);g._assign_service_job(s,0)
 check(s.job_kind=="order" and s.table_face_cell==REAR and g.rear_route_calls==first+2,"released endpoint claim permits fresh successful route after topology change")
 first=g.rear_route_calls
 var target=g.model.get_item(101)
 check(g._service_destination(s,target,Vector2i(s.pos.floor()),[REAR])==INVALID,"positive cached route still rechecks same-frame endpoint claim")
 check(g._service_destination(s,target,Vector2i(s.pos.floor()))==REAR and g.rear_route_calls==first,"released same-frame claim reuses positive verdict")
 cleanup(g)

func targetless_cook_priority():
 var g=fixture();g.setup_targetless_cook()
 var chef=g.staff_states[0];var waiter=g.staff_states[1]
 var held=g.service_guests[202];var order=g.service_guests[201]
 var chef_token=held.token;var order_token=order.token
 check(chef.job_kind=="cook" and chef.job_token==chef_token and chef.job_step==3,"targetless cook retains a valid live guest/token and placing stage")
 check(g.model.get_item(112).kind=="counter" and held.meal_pass_id==-1 and not held.pass_reserved and g._service_target(chef).is_empty(),"existing pass is genuinely unavailable so the cook has no current target")
 check(chef.idle_home_cell==INVALID and chef.destination==REAR and waiter.table_face_cell==REAR,"targetless cook fallback conflicts with the already pinned order endpoint")
 check(g._table_face_available(REAR,waiter,[]),"targetless nonempty job does not own the table endpoint")
 check(not g._staff_cell_claimed(REAR,1),"common workface ownership also excludes targetless fallback")
 var kept_custody=true;var safe_motion=true;var yielded=false
 for tick in range(160):
  var previous:Vector2=chef.pos
  g._animate_staff(.05)
  safe_motion=safe_motion and not g.model.segment_blocked(previous,chef.pos) and g._staff_walkable(Vector2i(chef.pos.floor()))
  kept_custody=kept_custody and chef.job_kind=="cook" and chef.job_token==chef_token and chef.job_step==3 and chef.job_elapsed==0.0 and held.plate_owner=="staff" and held.plate_staff_index==0 and held.plate_target_id==-1 and held.meal_pass_id==-1 and not held.pass_reserved
  if waiter.job_kind=="order":yielded=yielded or chef.destination!=REAR
  if order.order_done:break
 evidence.targetless_cook=g.snapshot()
 check(yielded and safe_motion,"targetless cook yields the selected endpoint using a real clear-floor route")
 check(order.order_done and order.token==order_token,"later waiter completes its own order despite the targetless cook job")
 check(kept_custody and held.token==chef_token,"every tick preserves held plate, owner, token and unfinished cook stage")
 # Once the pass really becomes usable, its productive endpoint still owns
 # work space. Merely classifying an endpoint never transfers plate custody.
 g.model.items.erase(g.model.get_item(113));g._reserve_pass(chef)
 var pass_target=g._service_target(chef)
 check(not pass_target.is_empty() and int(pass_target.id)==112 and held.pass_reserved,"opening the pass restores the same cook's actual target")
 chef.destination=g._service_cell(pass_target,Vector2i(chef.pos.floor()),[],"chef")
 check(chef.destination!=INVALID and not g._table_face_available(chef.destination,waiter,[]) and g._staff_cell_claimed(chef.destination,1),"both ownership gates retain a real productive cook endpoint")
 check(held.plate_owner=="staff" and held.plate_staff_index==0 and held.token==chef_token,"pass retry and endpoint checks preserve held food custody")
 cleanup(g)

func combined_work_priority():
 var g=fixture();g.setup_combined_work()
 var pass_record=g.service_guests[204];var order=g.service_guests[201]
 var tokens=[g.service_guests[202].token,g.service_guests[203].token,pass_record.token,order.token]
 check(pass_record.meal_pass_id==130 and pass_record.pass_reserved,"combined fixture pins productive chef to its only available pass")
 check(g._service_target(g.staff_states[0]).is_empty() and g._service_target(g.staff_states[2]).is_empty(),"both other retained cooks genuinely have no current pass target")
 check(g.staff_states[1].table_face_cell==REAR,"combined waiter retains the selected rear endpoint")
 var retained=true;var both_yielded=false;var placed=false
 for tick in range(200):
  g._animate_staff(.05)
  for pair in [[202,0],[203,2]]:
   var record=g.service_guests[pair[0]];var chef=g.staff_states[pair[1]]
   retained=retained and record.plate_owner=="staff" and record.plate_staff_index==pair[1] and chef.job_kind=="cook" and chef.job_step==3 and chef.job_elapsed==0.0
  if tick==0:both_yielded=g.staff_states[0].destination!=REAR and g.staff_states[2].destination!=Vector2i(2,3)
  placed=placed or (pass_record.plate_owner=="counter" and pass_record.plate_target_id==130)
  if order.order_done and pass_record.meal_ready:break
 evidence.combined={"order":g.snapshot(),"placed":placed,"meal_ready":pass_record.meal_ready,"fallback_custody_retained":retained}
 check(both_yielded,"one frame excludes both selected order and productive chef endpoints from fallback")
 check(placed and pass_record.meal_ready and order.order_done,"chef pass contact and rear order both finish in the same scene")
 check(retained,"both waiting cooks retain their held plates and unfinished stage throughout")
 check(tokens==[g.service_guests[202].token,g.service_guests[203].token,pass_record.token,order.token],"combined arbitration preserves all four service tokens")
 cleanup(g)
