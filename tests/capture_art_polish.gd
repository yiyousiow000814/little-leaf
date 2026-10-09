extends SceneTree
## Exact same generated state and camera against pinned source revisions.
class GeneratedMain extends "res://tests/role_fixture.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
var output=OS.get_environment("CABINET_CAPTURE_OUTPUT")
var validate_only=DisplayServer.get_name()=="headless"
var records=[]
func _initialize():
 root.size=Vector2i(1360,880);run.call_deferred()
func fresh():
 seed(123456)
 var game=GeneratedMain.new();root.add_child(game)
 game.set_process(false);game.illustration.set_process(false);game.tutorial.skip()
 game.cafe_intro.active=false;game.editing=false;game.paused=false
 game.model.coins=100000;game.model.operating_open=false
 return game
func run():
 if not validate_only and output=="":printerr("CABINET_CAPTURE_OUTPUT required");quit(2);return
 if not validate_only:DirAccess.make_dir_recursive_absolute(output)
 for rotation in range(4):
  for kind in ["register"]:
   var game=fresh();var item={}
   for candidate in game.model.items:
    if candidate.kind==kind:item=candidate;break
   if item.is_empty():printerr("Missing fixture station ",kind);quit(1);return
   item.x=9;item.z=4;item.rot=rotation;game._rebuild_furniture()
   var worker={}
   if kind=="sink":
    game.setup_dirty(false);game.model.customers.clear();game.service_guests.clear()
    worker=game.worker("cleaner")
    game.dishwashing.dishes[1]={"id":1,"sink_id":int(item.id),"elapsed":0.0};game.dishwashing.next_id=2
    worker.pos=game.model.cell_center(game.model.workface_cell(item))
    game._assign_service_job(worker,game.staff_states.find(worker))
    for tick in range(20):
     game.advance(.1);game.illustration.update_motion(.1)
   else:
    if kind=="register":
     game.model.hire_staff("cashier");game._update_people();game._sync_staff_duty()
    game.model.operating_open=true;game.model._spawn_customer()
    for tick in range(12000):
     game.model._arrival_elapsed=0.0;game._tick_live_service(.1);game._update_people();game._animate_staff(.1);game.illustration.update_motion(.1)
     for candidate in game.staff_states:
      if candidate.art_action==("preparing_drink" if kind=="beverage" else "taking_payment") and float(candidate.job_elapsed)>=.7:worker=candidate;break
     if not worker.is_empty():break
   if worker.is_empty():printerr("No active fixture contact ",kind," r",rotation);quit(1);return
   # Let the existing planted-foot controller settle without advancing service.
   for tick in range(20):game.illustration.update_motion(.1)
   game._update_ui()
   var key="staff_%s"%game.staff_states.find(worker)
   var rendered=game.illustration._render_position(key,worker.pos)
   var pose=game.illustration.motion.sample(key)
   var receipt={"kind":kind,"rotation":rotation,"logical_position":worker.pos,"rendered_position":rendered,"motion":pose,"action":worker.art_action,"job_elapsed":worker.job_elapsed,"actual_shoes":shoe_receipt(pose,rendered-Vector2(item.x+.5,item.z+.5))}
   if kind=="register":
    var guests=[]
    for guest in game.model.customers:
     if guest.phase!="paying":continue
     var guest_key="guest_%s"%guest.id
     var guest_position=game.illustration._render_position(guest_key,Vector2(guest.x,guest.z))
     guests.append({"id":guest.id,"rendered_position":guest_position,"actual_shoes":shoe_receipt(game.illustration.motion.sample(guest_key),guest_position-Vector2(item.x+.5,item.z+.5))})
    receipt["paying_guests"]=guests
   await capture(game,"work-%s-r%d"%[kind,rotation],Vector2(item.x+.5,item.z+.5),receipt)
   game.free();await process_frame
 if validate_only:
  print("CABINET_CAPTURE_FIXTURE_RESULT ",JSON.stringify({"checks":8,"failures":[],"generated_scenes":4}));quit();return
 FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"generated_profile":true,"renderer":RenderingServer.get_video_adapter_name(),"frames":records},"  "))
 quit()
func capture(game,label:String,center:Vector2,receipt:Dictionary):
 var art=game.illustration
 for zoom_name in ["normal","medium"]:
  art.zoom=1.0 if zoom_name=="normal" else 2.5
  art.pan_offset=Vector2.ZERO;art.update_projection()
  art.pan_offset+=art.camera_play_rect().get_center()-(art.iso(center.x,center.y)+Vector2(0,-18)*art.ui_scale*art.zoom)
  art.update_projection()
  if validate_only:continue
  art.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
  var name="%s-%s.png"%[label,zoom_name]
  root.get_texture().get_image().save_png(output.path_join(name))
  var row=receipt.duplicate(true)
  row.merge({"file":name,"zoom":art.zoom,"camera_origin":[art.origin.x,art.origin.y],"render_contacts":art.render_contacts.duplicate(true)},true)
  records.append(row)

func shoe_receipt(pose:Dictionary,relative:Vector2)->Dictionary:
 var rows=[];var inside_body=0;var worst_overlap=0.0
 for side in ["left","right"]:
  var center:Vector2=pose.get(side+"_ground",Vector2.ZERO)
  var axis:Vector2=pose.get(side+"_axis",Vector2.RIGHT)
  var across=axis.orthogonal();var polygon=[]
  for q in [Vector2(-3.9,-1.25),Vector2(-2.8,-2),Vector2(1.4,-2.2),Vector2(3.5,-1.6),Vector2(4.1,-.3),Vector2(3.5,1.45),Vector2(1.4,2.15),Vector2(-2.8,1.9),Vector2(-3.9,.95)]:
   var pixel=center+axis*q.x+across*q.y
   var world=relative+Vector2(pixel.x/78+pixel.y/39,pixel.y/39-pixel.x/78)
   polygon.append([world.x,world.y])
   if absf(world.x)<.5 and absf(world.y)<.5:inside_body+=1
  var shape=PackedVector2Array()
  for q in polygon:shape.append(Vector2(q[0],q[1]))
  var solids=[Rect2(-.5,-.5,1.,1.)]
  var areas=[]
  for solid in solids:
   var box=PackedVector2Array([solid.position,Vector2(solid.end.x,solid.position.y),solid.end,Vector2(solid.position.x,solid.end.y)])
   var area=0.0
   for intersection in Geometry2D.intersect_polygons(shape,box):
    var signed_area=0.0
    for i in range(intersection.size()):signed_area+=intersection[i].cross(intersection[(i+1)%intersection.size()])
    area+=absf(signed_area)*.5
   areas.append(area);worst_overlap=maxf(worst_overlap,area)
  rows.append({"side":side,"world_polygon_relative_to_station":polygon,"solid_overlap_areas":areas})
 # Before images may expose the known defective support geometry; only
 # the new support candidate must pass this physical-footprint assertion.
 var constants=load("res://scripts/illustrated_furniture.gd").get_script_constant_map()
 if constants.has("CABINET_SOLID_BODY") and worst_overlap>.000001:
  printerr("Actual shoe overlaps solid cabinet body: ",worst_overlap);quit(1)
 return {"polygons":rows,"vertices_inside_full_body":inside_body,"max_solid_overlap_area":worst_overlap}
