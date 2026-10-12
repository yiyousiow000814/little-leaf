extends SceneTree
## Working-side availability is operational; actual bodies still exclude placement.
const Model=preload("res://scripts/core/cafe_model.gd")
const Plan=preload("res://scripts/gameplay/cafe_edit_plan.gd")
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func fresh():
 var model=Model.new();model.items.clear();model.dining_sets.clear();model.customers.clear();model.coins=100000
 return model
func state(model):return JSON.stringify([model.items,model.customers,model.dining_sets,model.built_walls,model.wall_attachments,model.coins,model.revision,model._next_item_id])
func run():
 for rot in 4:
  var m=fresh();check(m.place("stove",5,4,rot),"stove places r"+str(rot))
  var stove=m.items[-1];var front=m.workface_cell(stove)
  check(m._walkable(front) and not m.path_between(Vector2i(1,5),front).is_empty(),"empty working side remains ordinary walkable floor r"+str(rot))
  var before=state(m)
  check(m.can_place("plant",front.x,front.y),"an empty working side is physically placeable r"+str(rot))
  check(state(m)==before,"physical preview is nonmutating r"+str(rot))
  check(m.place("plant",front.x,front.y),"physically valid working-side obstruction commits r"+str(rot))
  check(not m._sale_station_usable_in(stove,m.items,m._sale_reachable_in(m.items)),"blocked stove is unavailable for service r"+str(rot))
  check(not m.can_place("sink",front.x,front.y),"real object overlap still rejects r"+str(rot))
  var body=fresh();body.place("stove",5,4,rot);before=state(body)
  var actors=[Vector2(front)+Vector2(.5,.5)]
  check(not body.can_place("plant",front.x,front.y,-1,0,actors),"actual staff body excludes the work tile r"+str(rot))
  check(not body.place("plant",front.x,front.y,0,actors) and state(body)==before,"body rejection preserves the full transaction r"+str(rot))
  var route=fresh();route.place("stove",5,4,rot)
  route.customers.assign([{"id":1,"phase":"arriving","x":1.5,"z":5.5,"route":[Vector2(front.x+.5,front.y+.5)],"route_index":0}])
  check(route.can_place("plant",front.x,front.y),"a future route alone does not occupy the footprint r"+str(rot))
  var wall=fresh();wall.place("stove",5,4,rot)
  var base=Vector2i(5,4);var axis="x" if base.y!=front.y else "z"
  var x=maxi(base.x,front.x);var z=maxi(base.y,front.y)
  check(wall.can_place_wall(axis,x,z),"working edge alone does not veto a physical wall r"+str(rot))
  var mid=(Vector2(base)+Vector2(front)+Vector2.ONE)*.5
  check(not wall.can_place_wall(axis,x,z,"full","sage_panels",[mid]),"a real body on the wall edge still rejects r"+str(rot))
  check(wall.place_wall(axis,x,z),"body-free working edge wall commits r"+str(rot))
  var plan=Plan.new();var receipt=plan.prepare(body,"plant",-1,0,front,actors);var count=plan.validations
  for repeat in 100:plan.prepare(body,"plant",-1,0,front,actors)
  check(not receipt.physical_ok and plan.validations==count,"identical body-blocked hover reuses its receipt r"+str(rot))
 var m=fresh();m.place("stove",5,3);m.place("plant",5,4)
 check(m.save("user://idle-blocked-stove.json"),"current idle physical layout saves")
 var original=FileAccess.get_file_as_string("user://idle-blocked-stove.json");var restored=Model.new()
 check(restored.load_save("user://idle-blocked-stove.json") and restored.items==m.items,"idle reload preserves exact furniture and identities")
 check(FileAccess.get_file_as_string("user://idle-blocked-stove.json")==original,"reload preserves source bytes")
 check(not restored.can_place("stove",99,99),"ownership still rejects")
 check(restored.can_place("plant",restored.ENTRY_LANDING.x,restored.ENTRY_LANDING.y),"idle entrance access is independent of physical fit")
 print("STOVE_WORK_RESERVATION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
