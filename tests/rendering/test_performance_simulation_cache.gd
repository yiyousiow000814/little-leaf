extends SceneTree
const Model=preload("res://scripts/core/cafe_model.gd")
const Main=preload("res://scripts/main.gd")
class AdmissionModel extends "res://scripts/core/cafe_model.gd":
 var attempts=0
 func _try_admit_queued_visitor(_visitor:Dictionary)->bool:attempts+=1;return false
class CapacityModel extends "res://scripts/core/cafe_model.gd":
 var capacity_rows=0
 func _tick_service_capacity()->Vector3i:
  capacity_rows+=items.size()
  return super._tick_service_capacity()
 func _begin_departure(customer:Dictionary)->void:
  customer.phase="leaving"
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func capacity_guest(id:int,phase:String,elapsed=0.0)->Dictionary:
 return {"id":id,"phase":phase,"elapsed":elapsed,"duration":1.0,"paid":false}
func verify_step_capacity():
 var m=CapacityModel.new()
 m.items.clear();m.customers.clear();m.operating_open=false;m.cooks=3
 for i in 64:m.items.append({"id":i+100,"kind":"plant"})
 for fixture in [{"id":1,"kind":"stove"},{"id":2,"kind":"beverage"},{"id":3,"kind":"sink"}]:m.items.append(fixture)
 for phase in ["cooking","cleaning","drinking"]:
  for i in 16:m.customers.append(capacity_guest(m.customers.size()+1,phase))
 m._tick_step(.25)
 check(m.capacity_rows==m.items.size(),"gear counts visit each furnishing once per ordinary simulation step")
 check(m.customers[0].elapsed==.25 and m.customers[1].elapsed==0.0,"one stove caps cooks and keeps first guest order")
 check(m.customers[16].elapsed==.25 and m.customers[17].elapsed==0.0,"one sink caps cleaners and keeps first guest order")
 check(m.customers[32].elapsed==.25 and m.customers[-1].elapsed==.25,"beverage station enables all existing drinking guests")
 # A direct item mutation without revision must be seen next slice, and a
 # synchronous legacy payment callback invalidates the in-flight capacity.
 m.customers.insert(32,capacity_guest(1000,"eating",.75))
 m.meal_completed.connect(func(_id,_amount): m.items[-2].kind="plant",CONNECT_ONE_SHOT)
 var before=m.capacity_rows
 m._tick_step(.25)
 check(m.capacity_rows-before==m.items.size()*2,"one callback rebuilds gear counts only once for all later diners")
 check(m.customers[33].elapsed==.25,"later guests see beverage removed by synchronous listener")
 m.customers.remove_at(32)
 m.items[-2].kind="beverage"
 m._tick_step(.25)
 check(m.customers[32].elapsed==.5,"next simulation step sees direct beverage restoration without revision")
func _initialize():run.call_deferred()
func run():
 verify_step_capacity()
 var m=Model.new();m.items.clear();m.customers.clear();m.built_walls.clear();m.wall_attachments.clear()
 var a=Vector2i(3,3);var b=Vector2i(4,3)
 check(m.path_between(a,b)==[a,b],"initial clear path")
 m.items.append({"id":1,"kind":"plant","x":4,"z":3,"rot":0})
 check(m.path_between(a,b).is_empty(),"direct append invalidates occupancy without revision")
 m.items[0].kind="rug"
 check(m.path_between(a,b)==[a,b],"in-place rug conversion invalidates occupancy")
 var replacement=m.items[0].duplicate();m.items[0]=replacement
 check(is_same(m.get_item(1),replacement),"same-value replacement retains authoritative item identity")
 m.items[0].x=5
 check(m.path_between(a,b)==[a,b],"direct move changes occupied cell")
 m.items.clear();m.navigation_cells()
 var game=Main.new();game.model=m
 var staff={"pos":Vector2(3.5,3.5),"path":[Vector2i(4,3),Vector2i(5,3)],"index":0}
 check(not game._staff_route_invalid(staff,m.navigation_signature()),"clear route validates")
 check(not game._staff_route_invalid(staff,m.navigation_signature()),"unchanged route retains validity")
 m.items.append({"id":2,"kind":"plant","x":5,"z":3,"rot":0});m.navigation_cells()
 check(game._staff_route_invalid(staff,m.navigation_signature()),"future furniture insertion invalidates cached route")
 m.items.clear();m.navigation_cells()
 check(not game._staff_route_invalid(staff,m.navigation_signature()),"removal restores route")
 m.built_walls.append({"id":1,"x":4,"z":3,"axis":"z","height":"full","material":"original","paid_cost":0});m.navigation_cells()
 check(game._staff_route_invalid(staff,m.navigation_signature()),"direct wall insertion invalidates route and collision cache")
 m.built_walls.clear();m.navigation_cells()
 check(not game._staff_route_invalid(staff,m.navigation_signature()),"wall removal restores route")
 staff.path=[Vector2i(4,3),Vector2i(-1,-1)]
 check(game._staff_route_invalid(staff,m.navigation_signature()),"changed route cannot reuse old validation")
 for node in [game.people,game.ui]:node.free()
 game.free()
 var admission=AdmissionModel.new();admission.customers.clear()
 var visitor={"id":99,"x":-1.6,"z":7.5}
 for i in 10:admission._admit_queued_visitor(visitor)
 check(admission.attempts==1,"unchanged failed FIFO request retries only once")
 admission.customers.append({"id":1,"table_id":1,"chair_id":2,"phase":"arriving"});admission._admit_queued_visitor(visitor)
 check(admission.attempts==2,"arrival slot occupancy invalidates")
 admission.customers[0].phase="eating";admission._admit_queued_visitor(visitor)
 check(admission.attempts==3,"freeing arrival slot invalidates")
 admission.customers[0].elapsed=123.0;admission._admit_queued_visitor(visitor)
 check(admission.attempts==3,"elapsed-only change preserves failed admission cache")
 admission.customers[0].withdrawn=true;admission._admit_queued_visitor(visitor)
 check(admission.attempts==4,"withdrawal releases seat and invalidates")
 admission.items[0].rot+=1;admission._admit_queued_visitor(visitor)
 check(admission.attempts==5,"rotation invalidates admission")
 admission.wall_attachments.clear();admission._admit_queued_visitor(visitor)
 check(admission.attempts==6,"door removal invalidates admission")
 admission.built_walls[0].height="half";admission._admit_queued_visitor(visitor)
 check(admission.attempts==7,"installed wall change invalidates admission")
 visitor.id=100;admission._admit_queued_visitor(visitor)
 check(admission.attempts==8,"new FIFO head invalidates admission")
 admission.operating_open=false;admission._admit_queued_visitor(visitor)
 check(admission.attempts==9,"closed cafe invalidates admission")
 verify_station_assignment_scope()
 print("PERFORMANCE_SIMULATION_CACHE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"status":"passed" if failures.is_empty() else "failed"}));quit(0 if failures.is_empty() else 1)


class StationAuditMain extends "res://scripts/main.gd":
 var station_searches=0
 var face_checks=0
 func _service_station(kind:String,from:Vector2i,index:int)->Dictionary:
  station_searches+=1
  return super._service_station(kind,from,index)
 func _service_cell(item:Dictionary,_from=Vector2i(7,1),_claimed=[],_role="")->Vector2i:
  face_checks+=1
  return Vector2i(6,4) if bool(item.get("work_ok",false)) else Vector2i(-1,-1)

func verify_station_assignment_scope():
 for role in ["chef","waiter"]:
  var game=StationAuditMain.new();var model=game.model
  var kind="stove" if role=="chef" else "beverage"
  var job="cook" if role=="chef" else "brew"
  var phase="cooking" if role=="chef" else "drinking"
  model.items.clear();model.customers.clear()
  for i in 16:
   var guest={"id":i+10,"phase":phase,"table_id":-1,"withdrawn":false}
   model.customers.append(guest)
   game.service_guests[guest.id]={"guest":guest,"token":guest.id,"plate_owner":"table","plate_target_id":-1,"drink_owner":"table","drink_target_id":-1,"meal_ready":false,"drink_ready":false}
   model.items.append({"id":100+i,"kind":kind,"work_ok":false})
  for i in 2:game.staff_states.append({"role":role,"job_kind":"","pos":Vector2(6.5,4.5),"on_duty":true})
  var first=game.staff_states[0];var second=game.staff_states[1]
  game._assign_service_job(first,0)
  check(first.job_kind=="" and first.blocked_guest_id==25 and first.blocked_target_id==115,role+" blocked attempt preserves the last eligible diner and station")
  check(game.station_searches==1 and game.face_checks==33,role+" repeated blocked diners share one search and one blocked explanation")
  for item in model.items:item.work_ok=true
  var record=game.service_guests[11]
  if role=="chef":record.plate_owner="station";record.plate_target_id=100
  else:record.drink_owner="station";record.drink_target_id=100
  game._assign_service_job(first,0)
  check(first.job_kind==job and first.job_guest_id==10 and first.station_id==101,role+" sees direct workface change and skips live payload custody")
  game._assign_service_job(second,1)
  check(second.job_kind==job and second.job_guest_id==11 and second.station_id==102,role+" next assignment sees the preceding worker's new station claim")
  for node in [game.people,game.ui]:node.free()
  game.free()
