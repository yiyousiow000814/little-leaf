extends SceneTree
class GeneratedMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
var output=OS.get_environment("PROPORTION_CAPTURE_OUTPUT")
func _initialize():root.size=Vector2i(1360,880);run.call_deferred()
func pair(p:Vector2)->Array:return [p.x,p.y]
func run():
 if DisplayServer.get_name()=="headless" or output=="":printerr("Native GL and output required");quit(2);return
 DirAccess.make_dir_recursive_absolute(output)
 seed(123456)
 var game=GeneratedMain.new();root.add_child(game)
 game.set_process(false);game.illustration.set_process(false);game.tutorial.skip()
 game.paused=false;game.editing=false;game.model.operating_open=true
 var stove=game.model.get_item(1);stove.x=9;stove.z=4;stove.rot=0
 game._rebuild_furniture();game._sync_staff_duty();game.model._spawn_customer()
 var chef={}
 for tick in 1600:
  game.model._arrival_elapsed=0.0;game._tick_live_service(.1);game._update_people();game._animate_staff(.1);game.illustration.update_motion(.1)
  for staff in game.staff_states:
   if staff.job_kind=="cook" and int(staff.job_step)==1 and staff.job_elapsed>=2.0:chef=staff;break
  if not chef.is_empty():break
 if chef.is_empty():printerr("No real cooking job");quit(1);return
 # Two generated idle observers make all three original species comparable.
 for index in [1,2]:
  var staff=game.staff_states[index]
  staff.pos=Vector2(7.5 if index==1 else 6.5,5.5)
  staff.art_action="idle";staff.art_payload="none";staff.art_tool="none"
  staff.art_target=Vector2.ZERO;staff.art_target_id=-1;staff.art_station=staff.pos+Vector2(1,0)
 for settle in 20:game.illustration.update_motion(.1)
 var art=game.illustration
 var actor_key="staff_%s"%game.staff_states.find(chef)
 var logical:Vector2=chef.pos;var rendered=art._render_position(actor_key,logical)
 if absf(rendered.distance_to(logical)-.32)>.001:printerr("Live inset is not settled");quit(1);return
 game._update_ui()
 var clock=float(chef.job_elapsed);var rows=[];var cameras={};var feet={}
 var normal_pan=art.pan_offset
 # Warm the ordinary runtime caches before any comparative frame.
 for warm in 30:art.queue_redraw();await process_frame
 for variant in ["baseline","A","B"]:
  game.set_meta("proportion_study",variant)
  for scale_name in ["normal","review"]:
   art.pan_offset=normal_pan;art.zoom=1.0 if scale_name=="normal" else 4.0
   art.update_projection()
   if scale_name=="review":
    art.pan_offset+=art.camera_play_rect().get_center()-(art.iso(8,5.25)+Vector2(0,-28)*art.ui_scale*art.zoom)
    art.update_projection()
   art.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
   var contacts=art.render_contacts.filter(func(c):return bool(c.staff) and int(c.id)==0)
   if contacts.is_empty():printerr("Missing actual chef render contact");quit(1);return
   var contact=contacts[0];var actual=contact.proportion_study
   var expected=0.0 if variant=="baseline" else (3.0 if variant=="A" else 5.0)
   if str(actual.get("variant",""))!=variant or float(actual.get("head_shift",-1))!=expected:printerr("Runtime study variant not applied");quit(1);return
   if chef.pos!=logical or chef.job_elapsed!=clock:printerr("Study changed simulated state");quit(1);return
   if not cameras.has(scale_name):cameras[scale_name]=art.origin;feet[scale_name]=contact.study_near_foot
   if art.origin.distance_to(cameras[scale_name])>.001 or contact.study_near_foot.distance_to(feet[scale_name])>.001:printerr("Camera/foot comparison mismatch");quit(1);return
   var name="%s-%s.png"%[variant,scale_name]
   root.get_texture().get_image().save_png(output.path_join(name))
   rows.append({"file":name,"variant":actual,"zoom":art.zoom,"camera_origin":pair(art.origin),"logical_position":pair(logical),"rendered_position":pair(rendered),"cooking_clock":clock,"near_foot":pair(contact.study_near_foot),"near_shoulder":pair(contact.study_near_shoulder),"staged_idle_staff_ids":[1,2],"motion_update_seconds":.1})
 FileAccess.open(output.path_join("study.json"),FileAccess.WRITE).store_string(JSON.stringify({"generated_profile":true,"head_art_scaled":false,"production_default_changed":false,"renderer":RenderingServer.get_video_adapter_name(),"frames":rows},"  "))
 game.free();quit()
