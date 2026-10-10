extends SceneTree
## Run identical file against pinned base and candidate in separate profiles.
## Requires a native GL renderer; never substitutes headless/illustrative images.
class GeneratedMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
var output=OS.get_environment("GENTLE_CAPTURE_OUTPUT")
var validate_only="--validate-fixture" in OS.get_cmdline_user_args()
func _initialize():
 root.size=Vector2i(1360,880)
 run.call_deferred()
func run():
 if not validate_only and (DisplayServer.get_name()=="headless" or output==""):
  printerr("Native GL and GENTLE_CAPTURE_OUTPUT are required");quit(2);return
 if not validate_only:DirAccess.make_dir_recursive_absolute(output)
 var records=[]
 for rotation in range(4):
  print("CAPTURE_ROTATION_START ",rotation)
  seed(123456)
  var game=GeneratedMain.new();root.add_child(game)
  game.set_process(false);game.illustration.set_process(false)
  game.tutorial.skip()
  game.cafe_intro.active=false;game.editing=false;game.paused=false;game.model.operating_open=true
  var stove=game.model.get_item(1);stove.rot=rotation;stove.x=9;stove.z=4
  game._rebuild_furniture();game._sync_staff_duty();game.model._spawn_customer()
  var chef={}
  for tick in 6000:
   game.model._arrival_elapsed=0.0;game._tick_live_service(.1);game._update_people();game._animate_staff(.1);game.illustration.update_motion(.1)
   for staff in game.staff_states:
    if staff.job_kind=="cook" and int(staff.job_step)==1 and staff.job_elapsed>=1.0:chef=staff;break
   if not chef.is_empty():break
  if chef.is_empty():printerr("No cooking job for rotation ",rotation);quit(1);return
  var actor_key="staff_%s"%game.staff_states.find(chef)
  var logical:Vector2=chef.pos
  var target=Vector2(stove.x+.5,stove.z+.5)
  var cooking_script=load("res://scripts/cooking_tool_pose.gd")
  var inset=float(cooking_script.get_script_constant_map().get("WORK_INSET",.40))
  var expected_inset=(target-logical).normalized()*inset
  var rendered=game.illustration._render_position(actor_key,logical)
  var actual_inset=rendered-logical
  var settled_pose=game.illustration.motion.sample(actor_key)
  if actual_inset.distance_to(expected_inset)>.001:
   printerr("Work inset did not settle: ",actual_inset," expected ",expected_inset);quit(1);return
  print("CAPTURE_COOKING_READY ",rotation," logical=",logical," rendered=",rendered," inset=",actual_inset)
  game._update_ui()
  var normal_pan=game.illustration.pan_offset
  for moment in [1.0,2.0,6.0]:
   # Generated review state only: same work clock and ownership on both refs.
   chef.job_elapsed=moment
   chef.art_phase=moment/game.Model.cooking_seconds(game.Model.stove_speed_multiplier(stove))
   for scale_name in ["normal","max"]:
    var art=game.illustration
    art.pan_offset=normal_pan
    art.zoom=1.0 if scale_name=="normal" else art.camera_zoom_limits().y
    art.update_projection();art.update_motion(0.0)
    if scale_name=="max":
     # Maximum legal zoom must inspect the actual chef/pot, not the register.
     var unit=art.ui_scale*art.zoom
     var pot_center=art.iso(stove.x+.5,stove.z+.5)+Vector2(0,-27)*unit
     var reference_position=logical+(target-logical).normalized()*.40
     var chef_center=art.iso(reference_position.x,reference_position.y)+Vector2(0,-28)*unit
     art.pan_offset+=art.camera_play_rect().get_center()-(pot_center+chef_center)*.5
     art.update_projection()
    if validate_only:continue
    print("CAPTURE_FRAME ",rotation," ",scale_name," ",moment)
    art.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
    var name="rot%d-%s-t%.1f.png"%[rotation,scale_name,moment]
    root.get_texture().get_image().save_png(output.path_join(name))
    records.append({"file":name,"rotation":rotation,"elapsed":moment,"zoom":art.zoom,"plate_owner":game.service_guests[chef.job_guest_id].plate_owner,"logical_position":[logical.x,logical.y],"rendered_position":[rendered.x,rendered.y],"work_inset":[actual_inset.x,actual_inset.y],"motion_update_seconds":.1,"left_shoe_axis":[settled_pose.left_axis.x,settled_pose.left_axis.y],"right_shoe_axis":[settled_pose.right_axis.x,settled_pose.right_axis.y],"left_lift":settled_pose.left_lift,"right_lift":settled_pose.right_lift,"camera_origin":[art.origin.x,art.origin.y]})
  game.free();await process_frame
 if validate_only:print("CAPTURE_FIXTURE_VALIDATED rotations=4");quit();return
 await capture_context(records)
 FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"generated_profile":true,"renderer":RenderingServer.get_video_adapter_name(),"frames":records},"  "))
 quit()

func capture_context(records:Array):
 var game=GeneratedMain.new();root.add_child(game)
 game.set_process(false);game.illustration.set_process(false);game.tutorial.skip()
 game.model.coins=100000;game.model.operating_open=false
 for cell in [Vector2i(7,1),Vector2i(1,0),Vector2i(2,0)]:
  if not game.model.place("stove",cell.x,cell.y,0):
   printerr("Context stove placement failed: ",game.model.last_error);quit(1);return
 game._rebuild_furniture();game._update_ui()
 var art=game.illustration
 for label in ["adjacent","wall-corner"]:
  art.zoom=3.0;art.pan_offset=Vector2.ZERO;art.update_projection()
  var center=Vector2(8,1.5) if label=="adjacent" else Vector2(2,.5)
  art.pan_offset+=art.camera_play_rect().get_center()-(art.iso(center.x,center.y)+Vector2(0,-18)*art.ui_scale*art.zoom)
  art.update_projection();art.queue_redraw()
  await process_frame;await RenderingServer.frame_post_draw
  var name="context-%s.png"%label
  root.get_texture().get_image().save_png(output.path_join(name))
  records.append({"file":name,"context":label,"zoom":art.zoom,"camera_origin":[art.origin.x,art.origin.y],"motion_update_seconds":0.0})
 game.free();await process_frame
