extends SceneTree
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
class SelectionCapture extends RefCounted:
 var projection
 var ui_scale=1.0
 var fills=[]
 var strokes=[]
 func iso(x,z,height=0):return projection.iso(x,z,height)
 func draw_colored_polygon(points,color):fills.append({"points":points,"color":color})
 func draw_multiline(points,color,width,antialias):strokes.append({"points":points,"color":color,"width":width,"antialias":antialias})
var game
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func snapshot():return JSON.stringify([game.model.coins,game.model.shell_products,game.model.shell_segment_products,game.model.wall_attachments,game.saves])
func settle():
 game._update_ui();game.illustration.queue_redraw()
 for i in 8:await process_frame
func _initialize():run.call_deferred()
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated UI runner");quit(2);return
 root.size=Vector2i(1360,880);game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame;game.editing=true;game.tray.show();game.model.coins=10000;game._set_catalog_category("Build");await settle()
 var ui=game.compact_ui;var tool=game.build_tools;var art=game.illustration
 for root_id in game.model.OpeningGeometry.SHELL_HOSTS:
  for index in game.model.ShellSegments.active_count(root_id,game.model.built_walls):
   var key=root_id+"#"+str(index);var host=game.model.get_wall_host(key);var center=(host.a+host.b)*.5;var point=art.iso(center.x,center.y,70)
   var hit=art.hit_wall_host(point)
   check(hit.get("segment_key","")==key,"unit hit target "+key)
   check(host.a.distance_to(host.b)==1.0,"one-grid extent "+key)
   for height in ["full","half"]:
    var volume=host.duplicate(true);volume.height=height;var original=JSON.stringify(volume)
    var shape=tool.OpeningArt.segment_selection_geometry(art,volume);var h=game.model.WallGeometry.HEIGHT_PIXELS[height];var far=volume.b+volume.normal
    check(shape.edges.size()==18,"nine visible volume edges "+key+height)
    check(shape.cap[0]==shape.front[3] and shape.cap[1]==shape.front[2],"front joins top cap "+key+height)
    check(shape.cap[2]==art.iso(far.x,far.y,h) and shape.near_end[2]==shape.cap[2],"real outer thickness and end-cap corner "+key+height)
    check(shape.near_end[1]==art.iso(far.x,far.y) and shape.near_end[0]==shape.front[1],"side return reaches full wall base "+key+height)
    check(shape.cap[2].distance_to(shape.cap[1])>1.0,"cap has visible structural depth "+key+height)
    check(JSON.stringify(volume)==original,"selection geometry is nonmutating "+key+height)
 var point=art.iso(2.5,0,70);var e=InputEventMouseButton.new();e.position=point;e.pressed=true;e.button_index=MOUSE_BUTTON_LEFT
 check(ui.handle_unhandled_input(e),"shell selection consumes pointer")
 check(ui.selected_shell=="shell:back#2","selection stores unit key")
 ui.show_finishes();check(ui.product_target=="shell:back#2","finish menu retains selected segment")
 check(ui.wall_papers.item_count==4,"shell segment retains Original room option")
 ui.finishes.hide();tool.material="cream_stripe";tool.choose("half");tool.refresh(point)
 check(tool.replacing and tool.selected_key=="shell:back#2" and tool.preview_valid,"preview targets one shell cell")
 check(tool.replacement_quote.new_cost==35 and tool.replacement_quote.refund==0,"preview costs one tile")
 var rendered=tool.render_shell_host("shell:back")
 check(rendered.has("segment_runs") and rendered.segment_runs.size()==3,"middle cell preview splits root into three runs")
 check(tool.render_shell_corner_height("shell:back")==128.0,"middle preview cannot lower corner")
 var before=snapshot();tool._commit();await settle()
 check(ui.wall_review.visible and ui.pending_wall.key=="shell:back#2","confirmation retains one-grid key")
 check(ui.wall_review_text.text.begins_with("Selected one-tile wall") and not ui.wall_review_text.text.contains("Entire"),"confirmation describes one tile")
 check(snapshot()==before,"opening confirmation is nonmutating")
 ui.pending_wall={};ui.wall_review.hide();check(snapshot()==before,"cancelling review is nonmutating")
 tool.refresh(point);tool._commit();var neighbors=game.model.shell_segment_products.duplicate(true);ui._confirm_wall_replacement();await settle()
 check(game.model.coins==9965 and game.saves==1,"one confirmation charges35 once and saves once")
 check(ui.selected_shell=="shell:back#2" and ui.selected_wall=="","confirmed selection remains a shell segment")
 for key in neighbors:
  if key!="shell:back#2":check(neighbors[key]==game.model.shell_segment_products[key],"unchanged neighbor "+key)
 check(game.model.shell_segment_products["shell:back#2"].height=="half" and game.model.shell_segment_products["shell:back#2"].material=="cream_stripe","one charge buys the combined target height and finish")
 # Mixed-height root uses segment zero for its corner cap, independently of
 # the frozen inherited root's height and of any other selected segment.
 check(game.model.replace_wall("shell:back#0","half","sage_panels"),"corner segment edit")
 check(tool.render_shell_corner_height("shell:back")==58.0,"corner cap follows adjacent segment")
 ui.clear_selection();tool.cancel();await settle()
 var source=game.model.get_wall_attachment(1).duplicate(true);var door_point=art.iso(0,4.5,100)
 tool.choose("window");tool.refresh(door_point)
 check(not tool.opening_preview.is_empty() and tool.opening_preview.host_id=="shell:west" and is_equal_approx(float(tool.opening_preview.offset),4.5),"opening placement keeps root host and root offset")
 check(game.model.get_wall_attachment(1)==source,"opening preview cannot rewrite starter door")
 tool.cancel();await settle()
 ui.selected_shell="shell:west#5"
 var recorder=SelectionCapture.new();recorder.projection=art;before=snapshot();tool.draw_shell_selection(recorder)
 var selected_volume=tool.OpeningArt.segment_selection_geometry(recorder,game.model.get_wall_host("shell:west#5"))
 check(recorder.fills.is_empty(),"selection has no fill over the cap, wall or doorway hole")
 check(recorder.strokes.size()==1 and recorder.strokes[0].points==selected_volume.edges,"selection draws complete volume edges")
 check(snapshot()==before,"complete-volume selection does not mutate product, opening, wallet or saves")
 check(recorder.strokes[0].color==Color("444744"),"passive wall selection uses a dark-gray outline")
 tool.material="leaf_print";tool.choose("full");tool.refresh(art.iso(0,3.5,70));recorder=SelectionCapture.new();recorder.projection=art;tool.draw_shell_selection(recorder)
 check(tool.preview_valid and recorder.strokes[0].color==Color("444744"),"valid wall preview uses a dark-gray outline")
 tool.choose("half");tool.refresh(art.iso(0,5.5,70));recorder=SelectionCapture.new();recorder.projection=art;tool.draw_shell_selection(recorder)
 check(not tool.preview_valid and recorder.strokes[0].color==Color("444744"),"invalid preview keeps the dark-gray outline and validation state")
 for viewport in [Vector2i(1360,880),Vector2i(390,844),Vector2i(566,360)]:
  root.size=viewport;await settle();art.update_projection()
  var limits=art.camera_zoom_limits()
  for camera_zoom in [limits.x,clampf(1.15,limits.x,limits.y),limits.y]:
   art.zoom=camera_zoom;art.update_projection()
   for height in ["full","half"]:
    # This checks rendering at every zoom, including an offscreen host.
    # Pointer hit/quote/commit behavior is exercised above at a visible target.
    tool.mode=height;tool.selected_key="shell:west#3";tool.preview_shell=game.model.get_wall_host(tool.selected_key).duplicate(true);tool.preview_shell.height=height
    recorder=SelectionCapture.new();recorder.projection=art;recorder.ui_scale=art.ui_scale
    before=snapshot();tool.draw_shell_selection(recorder)
    var label=str(viewport)+" zoom="+str(camera_zoom)+" "+height
    check(tool.preview_shell.a.distance_to(tool.preview_shell.b)==1.0,"zoom preserves one-wall geometry "+label)
    check(recorder.fills.is_empty(),"no selection wash "+label)
    check(recorder.strokes.size()==1 and recorder.strokes[0].points.size()==18,"complete volume outline "+label)
    check(recorder.strokes[0].color==Color("444744") and is_equal_approx(recorder.strokes[0].width,.35) and recorder.strokes[0].antialias,"fine dark-gray stroke keeps subpixel coverage at every zoom "+label)
    check(snapshot()==before,"outline cannot change save or purchase state "+label)
 print("SHELL_SEGMENT_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
