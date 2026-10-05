extends SceneTree
var output=OS.get_environment("CHEF_HAT_OUTPUT")
func _initialize():
 root.size=Vector2i(1360,880)
 run.call_deferred()
func run():
 if output=="":output=ProjectSettings.globalize_path("res://evidence/native")
 DirAccess.make_dir_recursive_absolute(output)
 var painter=load("res://tests/chef_hat_review_painter.gd").new()
 root.add_child(painter)
 for frame in range(30):await process_frame
 for species in range(3):
  painter.reviewed_species=species;painter.cached=false;painter.queue_redraw()
  await process_frame;await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output.path_join("hat-%s-native-before-after.png"%["rabbit","fox","bear"][species]))
  painter.cached=true;painter.queue_redraw()
  await process_frame;await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output.path_join("hat-%s-native-cached-before-after.png"%["rabbit","fox","bear"][species]))
 print("CHEF_HAT_CAPTURE_COMPLETE cache=",painter.head_atlas.state)
 quit()
