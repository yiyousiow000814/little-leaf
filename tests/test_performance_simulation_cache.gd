extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Main=preload("res://scripts/main.gd")
class AdmissionModel extends "res://scripts/cafe_model.gd":
 var attempts=0
 func _try_admit_queued_visitor(_visitor:Dictionary)->bool:attempts+=1;return false
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
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
 for node in [game.world,game.furnishings,game.people,game.camera,game.ui]:node.free()
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
 admission.shell_products["west"]="half";admission._admit_queued_visitor(visitor)
 check(admission.attempts==7,"shell host change invalidates admission")
 visitor.id=100;admission._admit_queued_visitor(visitor)
 check(admission.attempts==8,"new FIFO head invalidates admission")
 admission.operating_open=false;admission._admit_queued_visitor(visitor)
 check(admission.attempts==9,"closed cafe invalidates admission")
 print("PERFORMANCE_SIMULATION_CACHE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"status":"passed" if failures.is_empty() else "failed"}));quit(0 if failures.is_empty() else 1)
