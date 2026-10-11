extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Plan=preload("res://scripts/cafe_edit_plan.gd")
const Floor=preload("res://scripts/cafe_floor_availability.gd")
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func fresh():
 var m=Model.new();m.items.clear();m.dining_sets.clear();m.customers.clear();m.coins=100000
 return m
func state(m):
 return JSON.stringify([m.items,m.customers,m.dining_sets,m.built_walls,m.wall_attachments,m.coins,m.revision,m._next_item_id,m._next_wall_id,m._next_attachment_id])
func edge(base,front):
 return {"axis":"x" if base.y!=front.y else "z","x":maxi(base.x,front.x),"z":maxi(base.y,front.y)}
func legacy_blocker(m,front):
 var item={"id":m._next_item_id,"kind":"plant","x":front.x,"z":front.y,"rot":0}
 m._next_item_id+=1;m.items.append(item);m._notify();return item
func run():
 var perf={}
 for rot in 4:
  var m=fresh();var base=Vector2i(5,4)
  check(m.place("stove",base.x,base.y,rot),"open stove places r"+str(rot))
  var stove=m.items[-1];var front=m.workface_cell(stove);var floor=Floor.new()
  check(floor.refresh(m)[front].blocked,"front is a red reserved floor cell r"+str(rot))
  check(m._walkable(front) and not m.path_between(Vector2i(1,5),front).is_empty(),"reservation preserves normal walking r"+str(rot))
  var before=state(m)
  for kind in ["plant","table_set","stove","sink","counter","bin"]:
   check(not m.can_place(kind,front.x,front.y),"solid preview rejected "+kind+" r"+str(rot))
   check(not m.place(kind,front.x,front.y),"solid confirmation rejected "+kind+" r"+str(rot))
   check(state(m)==before,"rejection preserves layout, wallet, ids and revision "+kind+" r"+str(rot))
  check(m.can_place("rug",front.x,front.y),"walkable rug preview remains allowed r"+str(rot))
  check(m.place("rug",front.x,front.y),"walkable rug commits r"+str(rot))
  check(m.layout_access_issues().is_empty(),"rug does not block chef r"+str(rot))
  m.remove(int(m.items[-1].id),false)
  check(m.place("plant",8,6),"move blocker fixture r"+str(rot))
  var plant=m.items[-1];before=state(m)
  check(not m.can_move(int(plant.id),front.x,front.y,0),"move preview rejected r"+str(rot))
  check(not m.move(int(plant.id),front.x,front.y,0),"move confirm rejected r"+str(rot))
  check(state(m)==before,"rejected move is atomic r"+str(rot))
  var blocked_rotation=posmod(rot+1,4)
  var next_front=m.workface_cell({"kind":"stove","x":5,"z":4,"rot":blocked_rotation})
  check(m.move(int(plant.id),next_front.x,next_front.y),"block next rotation fixture r"+str(rot))
  before=state(m)
  check(not m.can_move(int(stove.id),5,4,blocked_rotation),"stove rotation preview rejected r"+str(rot))
  check(not m.move(int(stove.id),5,4,blocked_rotation),"stove rotation confirmation rejected r"+str(rot))
  check(state(m)==before,"rejected rotation is atomic r"+str(rot))
  var e=edge(base,front)
  check(not m.can_place_wall(e.axis,e.x,e.z),"wall preview rejects work edge r"+str(rot))
  check(not m.place_wall(e.axis,e.x,e.z),"wall confirmation rejects work edge r"+str(rot))
  check(state(m)==before,"rejected wall is atomic r"+str(rot))
  check(m.place_wall("x",8,7),"unrelated wall places r"+str(rot))
  var key=Model.WallGeometry.key_of(m.built_walls[-1]);before=state(m)
  check(not m.move_wall(key,e.axis,e.x,e.z),"wall move rejects work edge r"+str(rot))
  check(state(m)==before,"rejected wall move is atomic r"+str(rot))
  var plan=Plan.new();var receipt=plan.prepare(m,"plant",-1,0,front)
  check(not receipt.ok and not plan.commit(m,receipt),"authoritative hover and confirm agree r"+str(rot))
  var validations=plan.validations;var builds=floor.builds;floor.refresh(m);builds=floor.builds
  var started=Time.get_ticks_usec()
  for repeat in 1000:plan.prepare(m,"plant",-1,0,front);floor.refresh(m)
  perf[str(rot)]=Time.get_ticks_usec()-started
  check(plan.validations==validations and floor.builds==builds,"1000 repeated hovers reuse cached plans and floor r"+str(rot))
  var blocked=fresh();check(blocked.place("plant",front.x,front.y),"pre-existing blocker places r"+str(rot));before=state(blocked)
  check(not blocked.can_place("stove",5,4,-1,rot) and not blocked.place("stove",5,4,rot),"new stove requires its own clear front r"+str(rot))
  check(state(blocked)==before,"rejected new stove is atomic r"+str(rot))
 # Only generated legacy layouts bypass authoring guards, like older saves.
 var m=fresh();m.place("stove",5,3);var stove=m.items[-1];var front=m.workface_cell(stove);var blocker=legacy_blocker(m,front)
 check(m.save("user://legacy-blocked-stove.json"),"legacy invalid layout can still save without rearrangement")
 var original=FileAccess.get_file_as_string("user://legacy-blocked-stove.json");var restored=Model.new()
 check(restored.load_save("user://legacy-blocked-stove.json"),"legacy blocked layout still loads")
 check(restored.items==m.items,"load preserves exact legacy furniture and ids")
 check(FileAccess.get_file_as_string("user://legacy-blocked-stove.json")==original,"load leaves original bytes untouched")
 var before=state(restored)
 check(restored.can_place("plant",8,6),"unrelated edit remains available in legacy layout")
 check(restored.can_move(int(blocker.id),8,6),"legacy blocker can move away")
 check(state(restored)==before,"legacy repair preview is nonmutating")
 check(restored.move(int(blocker.id),8,6) and restored.layout_access_issues().is_empty(),"legacy repair commits")
 check(not restored.move(int(blocker.id),front.x,front.y),"new obstruction cannot reintroduce repaired legacy problem")
 check(FileAccess.get_file_as_string("user://legacy-blocked-stove.json")==original,"editing never rewrites source file without save")
 var bad=fresh();bad.place("stove",5,3);var bad_stove=bad.items[-1];legacy_blocker(bad,bad.workface_cell(bad_stove));bad.place("plant",8,5)
 check(not bad.can_move(int(bad_stove.id),8,4,0),"legacy issue identity cannot excuse a newly blocked stove position")
 check(bad.can_move(int(bad_stove.id),5,3,1),"legacy blocked stove can rotate toward clear floor")
 for fixture in [{"x":1,"z":4,"rot":1},{"x":5,"z":0,"rot":2},{"x":11,"z":4,"rot":3},{"x":5,"z":8,"rot":0}]:
  var ownership=fresh();before=state(ownership)
  check(not ownership.place("stove",fixture.x,fixture.z,fixture.rot),"new workface cannot leave owned staff floor "+str(fixture))
  check(state(ownership)==before,"ownership rejection is atomic "+str(fixture))
 # The required space includes a route to it, not just an empty square.
 var route=fresh();route.place("stove",5,4);route.place("plant",4,5);route.place("plant",6,5);before=state(route)
 check(not route.place("plant",5,6),"cannot cut off the only path to chef work tile")
 check(not route.place_wall("x",5,6),"wall cannot cut off the only path to chef work tile")
 check(state(route)==before,"route obstruction previews and commits preserve state")
 # A doorway can keep a stove's working edge usable, but moving/removing it
 # must not silently close that edge. Existing blocked walls remain repairable.
 var doorway=fresh();check(doorway.place_wall("x",5,4),"doorway host fixture")
 var host="wall:%d"%int(doorway.built_walls[-1].id)
 check(doorway.place_wall_attachment("door",host,.5),"doorway fixture opens working edge")
 var door_id=int(doorway.wall_attachments[-1].id)
 check(doorway.place("stove",5,3),"stove can work through an open edge")
 check(doorway.place_wall("x",8,6),"doorway move destination fixture")
 var destination="wall:%d"%int(doorway.built_walls[-1].id);before=state(doorway)
 check(not doorway.can_remove_wall_attachment(door_id) and not doorway.remove_wall_attachment(door_id),"door removal cannot close stove workface")
 check(not doorway.can_move_wall_attachment(door_id,destination,.5) and not doorway.move_wall_attachment(door_id,destination,.5),"door move cannot close stove workface")
 check(state(doorway)==before,"blocked doorway edits are atomic")
 var old_wall=fresh();old_wall.place("stove",5,3)
 var injected_wall=Model.WallGeometry.make("x",5,4);injected_wall.id=old_wall._next_wall_id;old_wall._next_wall_id+=1;old_wall.built_walls.append(injected_wall);old_wall._notify()
 check(old_wall.move_wall(Model.WallGeometry.key_of(injected_wall),"x",8,6),"legacy blocking wall can move away")
 check(old_wall.layout_access_issues().is_empty(),"legacy wall repair restores workface")
 for furniture_first in [false,true]:
  var double_blocked=fresh();double_blocked.place("stove",5,3)
  var old_blocker=legacy_blocker(double_blocked,Vector2i(5,4))
  var old_edge=Model.WallGeometry.make("x",5,4);old_edge.id=double_blocked._next_wall_id;double_blocked._next_wall_id+=1;double_blocked.built_walls.append(old_edge);double_blocked._notify()
  if furniture_first:
   check(double_blocked.move(int(old_blocker.id),8,6),"partial legacy repair can clear furniture before wall")
   check(double_blocked.move_wall(Model.WallGeometry.key_of(old_edge),"x",8,7),"complete legacy repair clears remaining wall")
  else:
   check(double_blocked.move_wall(Model.WallGeometry.key_of(old_edge),"x",8,7),"partial legacy repair can clear wall before furniture")
   check(double_blocked.move(int(old_blocker.id),8,6),"complete legacy repair clears remaining furniture")
  check(double_blocked.layout_access_issues().is_empty(),"multi-obstruction legacy layout is repairable in either order")
 var shared=fresh();check(shared.place("stove",5,3,0) and shared.place("stove",5,5,2),"stoves may share a walkable front under runtime worker reservations")
 check(shared.layout_access_issues().is_empty(),"shared front stays physically available")
 print("STOVE_WORK_RESERVATION_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"cached_1000_hover_usec":perf}))
 quit(0 if failures.is_empty() else 1)
