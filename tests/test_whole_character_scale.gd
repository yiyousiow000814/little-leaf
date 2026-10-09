extends SceneTree
class GeneratedMain extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():root.size=Vector2i(1360,880);run.call_deferred()
func run():
 for rotation in range(4):
  seed(123456)
  var game=GeneratedMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.tutorial.skip()
  game.paused=false;game.editing=false;game.model.operating_open=true
  var stove=game.model.get_item(1);stove.x=9;stove.z=4;stove.rot=rotation
  game._rebuild_furniture();game._sync_staff_duty();game.model._spawn_customer()
  var chef={}
  for tick in 6000:
   game.model._arrival_elapsed=0;game._tick_live_service(.1);game._update_people();game._animate_staff(.1);game.illustration.update_motion(.1)
   for staff in game.staff_states:
    if staff.job_kind=="cook" and staff.job_step==1 and staff.job_elapsed>=2:chef=staff;break
   if not chef.is_empty():break
  check(not chef.is_empty(),"real stove work reached")
  if chef.is_empty():game.free();continue
  for i in 20:game.illustration.update_motion(.1)
  var art=game.illustration;var e={"type":"staff","entry":chef,"index":game.staff_states.find(chef)}
  var original=chef.pos;var clock=chef.job_elapsed
  for scale in [1.0,1.25,1.40]:
   game.set_meta("whole_character_scale_study",scale)
   var state=art.character_draw_state(e)
   var description=art.character_description(state.id,state.staff,state.seated,state.action,state.progress,state.reach,state.direction,state.payload,state.tool,state.pose,state.role)
   description.options.geometry_only=true
   var geometry=art.DirectionalCharacter.new().draw(art,Vector2.ZERO,description.species,description.away,state.moving,float(state.pose.phase),state.staff,false,description.options)
   check(state.transform.origin==state.position,"uniform scale uses grounded root")
   check(absf(state.transform.x.length()-art.ui_scale*art.zoom*scale)<.0001,"actual runtime whole scale")
   check(chef.pos==original and chef.job_elapsed==clock,"scale leaves simulated state unchanged")
   art._character_prop_scale=scale;art._art_transform=state.transform
   for anchor in [Vector2(2,-18),Vector2(13,-17),Vector2(4,-2)]:
    var prop_transform=art._world_prop_transform(anchor)
    check(absf(prop_transform.x.length()-art.ui_scale*art.zoom)<.0001,"plate/cup world scale unchanged in handoff")
    check((prop_transform*anchor).distance_to(state.transform*anchor)<.001,"unscaled prop retains its world support anchor")
   art._character_prop_scale=1.0
   var grip=geometry.cooking_pose
   var world_error=float(grip.grip_error)*scale
   check(world_error<.5,"world grip contact survives uniform scale")
   var polygons=[]
   var rendered=art._render_position("staff_%s"%e.index,chef.pos)
   var offset=rendered-Vector2(stove.x+.5,stove.z+.5)
   for outline in [geometry.near_shoe_polygon,geometry.far_shoe_polygon]:
    var polygon=[]
    for point in outline:
     var q=point*Vector2(float(state.pose.mirror),1)*scale
     polygon.append([offset.x+q.x/78.0+q.y/39.0,offset.y-q.x/78.0+q.y/39.0])
    polygons.append(polygon)
    var shape=PackedVector2Array()
    for point in polygon:shape.append(Vector2(point[0],point[1]))
    var solids=[Rect2(-.33,-.33,.66,.66)]
    for x in [-.438974358974,.438974358974]:
     for z in [-.438974358974,.438974358974]:solids.append(Rect2(x-.03923076923,z-.03923076923,.07846153846,.07846153846))
    for solid in solids:
     var p0=solid.position;var p1=solid.end
     var clipped=Geometry2D.intersect_polygons(shape,PackedVector2Array([p0,Vector2(p1.x,p0.y),p1,Vector2(p0.x,p1.y)]))
     check(clipped.is_empty(),"actual shoe polygon clears toe plinth and grounded corner supports")
   print("WHOLE_SCALE_SAMPLE ",JSON.stringify({"rotation":rotation,"scale":scale,"grip_error_world":world_error,"shoe_polygons":polygons,"door_rabbit_clearance":97.0-72.0*scale}))
  for guest in game.model.customers:
   if not bool(guest.get("seated",false)):continue
   var reference=Vector2.INF
   for scale in [1.0,1.25,1.40]:
    game.set_meta("whole_character_scale_study",scale)
    var state=art.character_draw_state({"type":"guest","entry":guest})
    var description=art.character_description(state.id,state.staff,state.seated,state.action,state.progress,state.reach,state.direction,state.payload,state.tool,state.pose,state.role)
    description.options.geometry_only=true
    var geometry=art.DirectionalCharacter.new().draw(art,Vector2.ZERO,description.species,description.away,state.moving,float(state.pose.phase),false,false,description.options)
    var hip=state.transform*((geometry.near_hip+geometry.far_hip)*.5)
    if scale==1.0:reference=hip
    check(hip.distance_to(reference)<.001,"uniform seated scale preserves actual hip support plane")
  game.free()
 print("WHOLE_SCALE_RESULT checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
