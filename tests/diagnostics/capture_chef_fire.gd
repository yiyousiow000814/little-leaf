extends SceneTree
const FPS=24
const FRAMES=144
var stage="before" if OS.get_environment("CHEF_STAGE")=="before" else "after"
var rows=[]
var ending_rows=[]
var output=OS.get_environment("CHEF_OUTPUT")
func _initialize():
 root.size=Vector2i(1360,880)
 run.call_deferred()
func tick(game,delta):
 # Drive the actual frame controller, including notices/UI/music clocks.
 game._process(delta)
 game.illustration.update_motion(delta)

func run():
 if output=="":output=ProjectSettings.globalize_path("res://evidence")
 DirAccess.make_dir_recursive_absolute(output.path_join(stage))
 for rotation in range(4):
  seed(123456)
  var game=load("res://main.tscn").instantiate()
  game.set_process(false)
  root.add_child(game)
  await process_frame
  game.set_process(false)
  game.illustration.set_process(false)
  game.editing=false;game.paused=false
  game.model.operating_open=true
  game.compact_ui.starter_dismissed=true
  var stove=game.model.get_item(1)
  stove.x=9;stove.z=4;stove.rot=rotation
  stove.level=1 if rotation<2 else 3
  var staff
  for step in range(3000):
   tick(game,.1)
   for candidate in game.staff_states:
    if candidate.art_action=="cooking":staff=candidate;break
   if staff!=null:break
  if staff==null:
   push_error("No real cooking job found for rotation "+str(rotation));quit(1);return
  # Start at the real cooking transition, after preparation at the workface.
  game._update_ui()
  game.illustration.zoom=1.15
  game.illustration.update_projection()
  for frame in range(FRAMES):
   tick(game,1.0/FPS)
   game.illustration.queue_redraw()
   await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(output.path_join("%s/rot%d-%03d.png"%[stage,rotation,frame]))
   var art=game.illustration
   var render_pos=art._render_position("staff_0",staff.pos)
   var facing=art.character_facings["staff_0"]
   var unit=art.ui_scale*art.zoom
   var p=art.iso(render_pos.x,render_pos.y)
   var contact=(art.iso(staff.art_target.x,staff.art_target.y)-p)/unit+art._stove_pan_point(rotation)
   var shoulder=Vector2(7,-24) if facing.back else Vector2(-7,-24)
   var local_pan=Vector2(contact.x*float(facing.mirror),contact.y)
   rows.append({"rotation":rotation,"frame":frame,"seconds":float(staff.job_elapsed),"progress":float(staff.art_phase),"chef_screen":[p.x,p.y],"unit":unit,"back":facing.back,"mirror":facing.mirror,"pan":[local_pan.x,local_pan.y],"shoulder":[shoulder.x,shoulder.y],"action":staff.art_action,"stove_level":stove.level,"recipe_duration":game.Model.cooking_seconds(game.Model.stove_speed_multiplier(stove))})
  # Capture paused and completed service states with the same real station.
  var held_clock=float(staff.job_elapsed)
  game.paused=true;game.compact_ui.viewport_too_small=false;game._process(.5)
  game.illustration.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output.path_join("paused-rot%d.png"%rotation))
  if not is_equal_approx(staff.job_elapsed,held_clock):push_error("Pause advanced chef/fire clock")
  game.paused=false
  staff.job_elapsed=game.Model.cooking_seconds(game.Model.stove_speed_multiplier(stove))-.70
  for end_frame in range(24):
   tick(game,1.0/FPS)
   game.illustration.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(output.path_join("ending-rot%d-%03d.png"%[rotation,end_frame]))
   ending_rows.append({"rotation":rotation,"frame":end_frame,"action":staff.art_action,"elapsed":staff.job_elapsed,"progress":staff.art_phase,"stove_level":stove.level})
  game.illustration.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output.path_join("plating-rot%d.png"%rotation))
  if not game.illustration._stove_heat_state(int(stove.id)).is_empty():push_error("Flame survived cooking completion")
  game.editing=true;game._update_ui();game.illustration.queue_redraw()
  await process_frame;await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output.path_join("decorate-rot%d.png"%rotation))
  game.queue_free();staff=null;game=null
  for cleanup_frame in range(4):await process_frame
 FileAccess.open(output.path_join(stage+"-runtime.json"),FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
 FileAccess.open(output.path_join("ending-runtime.json"),FileAccess.WRITE).store_string(JSON.stringify(ending_rows,"  "))
 print("CHEF_FOOD_CONTACT_CAPTURE_COMPLETE ",stage)
 await RenderingServer.frame_post_draw
 await process_frame
 quit()
