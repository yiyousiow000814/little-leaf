extends SceneTree
const NoBottom=preload("res://tests/no_bottom_notifications.gd")
class TestMain extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():return true
var game
var out=OS.get_environment("OUTPUT")
var phase=OS.get_environment("PHASE")
var records=[]
func _initialize():run.call_deferred()
func reset_fixture(material:String="original",back_height:String="full",extension:bool=false,west_height:String="full"):
 game.build_tools.cancel();game.compact_ui.clear_selection();game.model.built_walls.clear()
 if extension:game.model.built_walls.append({"id":41,"axis":"z","x":0,"z":8,"height":"full","material":"leaf_print"})
 game.model.wall_attachments.assign(game.model.OpeningGeometry.initial_attachments())
 game.model.shell_products=game.model.OpeningGeometry.initial_shell_products(material)
 game.model.shell_products["shell:back"].height=back_height
 game.model.shell_products["shell:west"].height=west_height
 game.model.shell_products["shell:west"].paid_cost=(495 if west_height=="full" else 315) if material!="original" else 0
 if extension:game.model.wall_attachments.assign([{"id":77,"kind":"door","host_id":"shell:west","offset":5.5,"width":1.5,"paid_cost":40}])
 if west_height=="half":game.model.wall_attachments[0].host_id="shell:back"
 if NoBottom.has_property(game.model,"shell_segment_products"):
  game.model.shell_segment_products=game.model.ShellSegments.migrate(game.model.shell_products,game.model.built_walls).segments
 game.model._next_wall_id=42 if extension else 1;game.model._next_attachment_id=78 if extension else 2
 game.model.coins=10000;game.illustration.update_projection()
func capture(name:String):
 game.ui.visible=false;game.tray.hide();game.illustration.queue_redraw()
 for i in 10:await process_frame
 await RenderingServer.frame_post_draw
 var file=phase+"-"+name+".png";root.get_texture().get_image().save_png(out.path_join(file))
 records.append({"file":file,"viewport":str(root.size),"origin":str(game.illustration.origin),"tile":str(game.illustration.tile),"zoom":game.illustration.zoom,"selected_key":game.build_tools.selected_key,"quote":game.build_tools.replacement_quote,"coins":game.model.coins})
func run():
 root.size=Vector2i(1360,880);game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame;game.editing=true;game.illustration.set_process(false);game._set_catalog_category("Build");game.ui.visible=false;game.tray.hide();game.illustration.zoom=1.15
 for i in 60:await process_frame
 for spec in [["original","full",false],["cream_stripe","full",false],["leaf_print","half",false],["sage_panels","full",true]]:
  reset_fixture(spec[0],spec[1],spec[2]);await capture(str(spec[0])+"-"+str(spec[1])+"-"+str(spec[2]))
 for west_height in ["full","half"]:
  for action in ["removed","moved"]:
   reset_fixture("cream_stripe","full",true,west_height)
   var ledger=game.model.get("shell_segment_products").duplicate(true) if NoBottom.has_property(game.model,"shell_segment_products") else {}
   var changed=game.model.remove_wall("z:0:8") if action=="removed" else game.model.move_wall("z:0:8","x",0,9)
   assert(changed,game.model.last_error)
   assert(game.model.save("user://extension-"+action+".json"),game.model.last_error)
   assert(game.model.load_save("user://extension-"+action+".json"),game.model.last_error)
   if not ledger.is_empty():assert(game.model.shell_segment_products==ledger,"Transition cannot reallocate the ledger")
   await capture("extension-"+action+"-"+west_height+"-roundtrip")
 reset_fixture();game.build_tools.material="leaf_print";game.build_tools.choose("full");game.ui.visible=false;game.tray.hide();game.build_tools.refresh(game.illustration.iso(0,3.5,70));await capture("hover-one-wall-tile")
 if NoBottom.has_property(game.model,"shell_segment_products"):
  reset_fixture();game.model.replace_wall("shell:back#2","half","cream_stripe");game.model.replace_wall("shell:back#0","half","sage_panels");game.model.replace_wall("shell:west#3","full","leaf_print");game.compact_ui.selected_shell="shell:west#3";await capture("mixed-saved-styles")
 FileAccess.open(out.path_join(phase+"-records.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"  "))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit()
