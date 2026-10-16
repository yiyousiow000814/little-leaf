extends SceneTree
const Main=preload("res://scripts/main.gd")
var checks=0
var failures=[]
var evidence={}
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func fixture():
 var g=Main.new();g.set_process(false);g.model.reset_new()
 g.model.items.assign([
  {"id":101,"kind":"stove","x":5,"z":3,"rot":0},
  {"id":102,"kind":"stove","x":7,"z":3,"rot":0},
  {"id":103,"kind":"counter","x":5,"z":5,"rot":0}])
 g.model.revision+=1
 g.model.customers.assign([
  {"id":201,"table_id":-1,"chair_id":-1,"phase":"cooking","x":3.5,"z":7.5,"paid":false,"elapsed":0.0,"duration":0.0,"mobility":{},"withdrawn":false,"meal_abandoned":false},
  {"id":202,"table_id":-1,"chair_id":-1,"phase":"cooking","x":4.5,"z":7.5,"paid":false,"elapsed":0.0,"duration":0.0,"mobility":{},"withdrawn":false,"meal_abandoned":false}])
 g._add_staff("chef",Vector2(5.5,4.5));g._add_staff("chef",Vector2(7.5,4.5));g._sync_service_guests()
 for i in range(2):
  var s=g.staff_states[i];var r=g.service_guests[201+i]
  s.job_kind="cook";s.job_step=3;s.station_id=101+i;s.job_guest_id=201+i;s.job_token=r.token
  r.plate_owner="staff";r.plate_staff_index=i;r.meal_station_id=101+i
 g._refresh_idle_homes()
 return g
func snapshot(g):
 var rows=[]
 for i in range(2):
  var s=g.staff_states[i];var r=g.service_guests[201+i]
  rows.append({"index":i,"pos":str(s.pos),"destination":str(s.destination),"home":str(s.idle_home_cell),"step":s.job_step,"elapsed":s.job_elapsed,"pass":r.meal_pass_id,"reserved":r.pass_reserved,"plate_owner":r.plate_owner,"reason":s.blocked_reason})
 return rows
func cleanup(g):
 g.people.free();g.ui.free();g.free()
func run():
 var g=fixture();var a=g.staff_states[0];var b=g.staff_states[1]
 var r=g.service_guests[202];var x=Vector2i(5,4)
 g._reserve_pass(b)
 check(r.meal_pass_id==103,"later chef reserves the only pass")
 var token=r.token
 var standing_yielded=false
 for i in range(200):
  g._animate_staff(.1)
  if r.plate_owner=="counter" and b.job_kind=="cook":standing_yielded=standing_yielded or a.pos!=Vector2(5.5,4.5)
 evidence.after_20_simulated_seconds=snapshot(g)
 check(r.plate_owner=="counter" and r.plate_target_id==103,"idle fallback cannot deadlock reserved placing work")
 check(r.meal_ready and r.token==token,"normal placing completes with the same meal token")
 check(standing_yielded,"blocked chef uses a standing alternative during the real handoff")
 cleanup(g)
 g=fixture();b=g.staff_states[1];r=g.service_guests[202]
 g.model.items.append({"id":104,"kind":"counter","x":8,"z":5,"rot":0});g.model.revision+=1
 g._reserve_pass(b)
 check(r.meal_pass_id==104,"nearest reachable chef endpoint wins over furniture order")
 token=r.token
 b.pos=Vector2(5.5,4.5)
 for i in range(20):g._reserve_pass(b)
 check(r.meal_pass_id==104,"valid reservation does not thrash when another counter becomes closer")
 r.meal_pass_id=104;r.pass_reserved=true # Independent invalidation fixture on both old/new implementations.
 b.job_elapsed=.3
 g.model.items.append({"id":105,"kind":"plant","x":8,"z":4,"rot":0}) # direct mutation without revision bump
 g._reserve_pass(b)
 check(r.meal_pass_id==103 and r.pass_reserved,"blocked rear invalidates and replaces the old reservation")
 check(r.plate_owner=="staff" and r.plate_staff_index==1 and r.token==token,"retarget preserves dish custody and token")
 check(b.job_step==3 and b.job_elapsed==0.0,"only incomplete placing contact restarts on target change")
 g._service_contact(b,1,"placing_plate",g.model.get_item(103),.65)
 b.job_elapsed=.6
 g.model.items.erase(g.model.get_item(105));g.model.revision+=1
 g._reserve_pass(b)
 check(r.meal_pass_id==103 and r.plate_target_id==103 and r.plate_owner=="counter","post-contact dish never jumps to a newly available pass")
 check(b.job_elapsed==.6,"post-contact handoff clock is preserved")
 cleanup(g)
 g=fixture();b=g.staff_states[1];r=g.service_guests[202]
 var other=g.service_guests[201];other.meal_pass_id=103;other.pass_reserved=true
 g._reserve_pass(b)
 check(r.meal_pass_id==-1 and r.plate_owner=="staff","full pass preserves held food")
 other.pass_reserved=false
 g._reserve_pass(b)
 check(r.meal_pass_id==103,"released pass invalidates a waiting search immediately")
 cleanup(g)
 g=fixture();b=g.staff_states[1];r=g.service_guests[202]
 g.model.items.append({"id":104,"kind":"counter","x":8,"z":5,"rot":0})
 g.model.items.append({"id":105,"kind":"plant","x":8,"z":6,"rot":0})
 g._reserve_pass(b)
 check(r.meal_pass_id==103,"near counter with blocked waiter front is unavailable")
 cleanup(g)
 g=fixture();b=g.staff_states[1];r=g.service_guests[202]
 g.model.get_item(103).x=6
 g.model.items.push_front({"id":104,"kind":"counter","x":8,"z":5,"rot":0})
 g._reserve_pass(b)
 check(r.meal_pass_id==103,"equal routes use stable lower counter ID despite list order")
 cleanup(g)
 g=fixture();b=g.staff_states[1];r=g.service_guests[202]
 g.model.items.append({"id":104,"kind":"counter","x":8,"z":5,"rot":0});g._reserve_pass(b)
 g.model.items.erase(g.model.get_item(104));g._reserve_pass(b)
 check(r.meal_pass_id==103 and r.plate_owner=="staff","direct counter deletion safely replans held food")
 var saved=g._service_save_snapshot()
 check(not saved.staff[1].has("pass_validation") and not saved.staff[1].has("pass_search") and not saved.staff[1].has("work_wait_seconds"),"runtime allocation caches do not change saved staff schema")
 cleanup(g)
 g=fixture();a=g.staff_states[0];b=g.staff_states[1]
 # Two independently usable stoves share a work cell. Later chef is mid-cook.
 g.model.get_item(102).x=6;g.model.get_item(102).z=4;g.model.get_item(102).rot=1;g.model.revision+=1
 a.job_step=0;b.job_step=1;b.job_elapsed=3.0
 a.pos=Vector2(5.5,4.5);b.pos=a.pos
 check(g.model.workface_cell(g.model.get_item(101))==g.model.workface_cell(g.model.get_item(102)),"stove fixture shares a physical work cell")
 g._animate_staff(.1)
 check(b.job_elapsed>3.0 and a.job_elapsed==0.0,"ongoing cooking wins over earlier new request")
 # On the next action boundary, the waiting chef gets its turn.
 b.job_step=2;b.job_elapsed=0.0
 g._animate_staff(.1)
 check(a.job_elapsed>.0 and b.job_elapsed==0.0,"older blocked request wins the next free action boundary")
 cleanup(g)
 g=fixture();a=g.staff_states[0];b=g.staff_states[1]
 a.work_wait_seconds=1.0;b.work_wait_seconds=10.0
 g._animate_staff(.1)
 check(g.service_guests[202].meal_pass_id==103 and g.service_guests[201].meal_pass_id==-1,"longer waiting chef gets a newly available pass before roster order")
 cleanup(g)
 incumbent_endpoints()
 route_boundary()
 evidence.checks=checks;evidence.failures=failures
 print("CHEF_PASS_RUNTIME ",JSON.stringify(evidence))
 print("CHEF_PASS_ALLOCATION_RESULT checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)

class SmallModel extends "res://scripts/core/cafe_model.gd":
 func is_floor_owned(cell:Vector2i)->bool:return cell.x>=0 and cell.x<4 and cell.y>=0 and cell.y<3
func route_boundary():
 var g=Main.new();g.model=SmallModel.new();g.model.reset_new();g.model.items.clear();g.model.built_walls.clear()
 for x in range(1,4):g.model.items.append({"id":x,"kind":"plant","x":x,"z":1,"rot":0})
 g._add_staff("chef",Vector2(1.5,.5))
 check(not g.model.path_between(Vector2i(1,0),Vector2i(1,2)).is_empty(),"model retains its existing x0 route semantics")
 check(g._staff_route(0,Vector2i(1,2)).is_empty(),"staff cannot use x0-only detour")
 if g.has_method("_staff_distances"):
  check(not g._staff_distances(Vector2i(1,0)).has(Vector2i(1,2)),"assignment uses actual staff route domain")
  check(g._staff_distances(Vector2i(0,2)).has(Vector2i(1,2)),"legacy boundary start may enter the legal staff grid")
  g.model.items.erase(g.model.get_item(2))
  check(g._staff_distances(Vector2i(1,0)).has(Vector2i(1,2)) and not g._staff_route(0,Vector2i(1,2)).is_empty(),"opening a legal staff route restores eligibility")
 else:check(false,"assignment must observe the actual staff route domain")
 cleanup(g)

func incumbent_endpoints():
 var g=fixture();var a=g.staff_states[0];var b=g.staff_states[1]
 g.model.get_item(102).x=6;g.model.get_item(102).z=4;g.model.get_item(102).rot=1;g.model.revision+=1
 g._clear_service_job(a)
 # A is genuinely idle: its own guest has already finished cooking.
 g.service_guests[201].meal_ready=true
 a.pos=Vector2(5.5,4.5);b.pos=a.pos;b.job_step=1;b.job_elapsed=3.0
 g._animate_staff(.1)
 check(a.job_kind=="" and b.job_elapsed>3.0,"earlier idle chef cannot claim an incumbent cooking endpoint")
 check(a.destination!=Vector2i(5,4),"idle home yields the real stove endpoint")
 cleanup(g)
 g=fixture();a=g.staff_states[0];b=g.staff_states[1]
 g.model.get_item(102).x=6;g.model.get_item(102).z=4;g.model.get_item(102).rot=1;g.model.revision+=1
 a.job_step=0;b.job_step=0;a.pos=Vector2(3.5,4.5);b.pos=Vector2(4.5,6.5)
 var owner=-1;var retained=true;var began=false
 for tick in range(70):
  g._animate_staff(.1)
  if tick==0:owner=0 if a.destination==Vector2i(5,4) else 1
  if tick==1:
   g.model.items.append({"id":107,"kind":"plant","x":10,"z":8,"rot":0})
   g.staff_states[1-owner].work_wait_seconds=100.0
  var winner=g.staff_states[owner]
  if winner.job_elapsed>0.0 or winner.job_step>0:began=true;break
  retained=retained and winner.destination==Vector2i(5,4)
 check(owner>=0 and retained,"in-flight chef retains its endpoint throughout approach")
 check(began,"shared endpoint approach reaches actual preparation instead of framewise livelock")
 # Finish the real action rather than manually jumping its step.
 var winner=g.staff_states[owner];var waiter=g.staff_states[1-owner]
 for tick in range(100):
  if winner.job_step>0:break
  g._animate_staff(.1)
 check(winner.job_step==1 and not winner.has("work_endpoint"),"natural action completion releases the endpoint")
 g._animate_staff(.1)
 check(waiter.destination==Vector2i(5,4),"waiting chef wins after incumbent action releases")
 for tick in range(100):
  if waiter.job_elapsed>0.0 or waiter.job_step>0:break
  g._animate_staff(.1)
 check(waiter.job_elapsed>0.0 or waiter.job_step>0,"released endpoint lets the waiting chef arrive and begin work")
 var saved=g._service_save_snapshot()
 check(not saved.staff[owner].has("work_endpoint"),"in-flight endpoint ownership is runtime-only")
 # A genuine static invalidation releases any in-flight claim.
 g.model.items.append({"id":106,"kind":"plant","x":5,"z":4,"rot":0})
 g._animate_staff(.1)
 check(not a.has("work_endpoint") and not b.has("work_endpoint"),"blocked workface invalidates in-flight claims")
 cleanup(g)
