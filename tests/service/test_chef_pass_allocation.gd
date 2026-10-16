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
 print("CHEF_PASS_ALLOCATION_RESULT checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
