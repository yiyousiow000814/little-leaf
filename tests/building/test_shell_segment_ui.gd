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
 func draw_colored_polygon(points,color,_uvs=PackedVector2Array(),_texture=null):fills.append({"points":points,"color":color})
 func draw_polygon(points,colors,_uvs=PackedVector2Array(),_texture=null):fills.append({"points":points,"colors":colors})
 func draw_multiline(points,color,width,antialias):strokes.append({"points":points,"color":color,"width":width,"antialias":antialias})
var game
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func snapshot():return JSON.stringify([game.model.coins,game.model.built_walls,game.model.wall_attachments,game.model.revision,game.model._next_wall_id,game.model._next_attachment_id,game.saves,game.platform_dirty_generation])
func stroke(recorder)->Dictionary:return recorder.strokes[0] if recorder.strokes.size()==1 else {}
func wall_host(key:String)->Dictionary:return game.model.OpeningGeometry.wall_host(game.model.get_wall(key))
func check_volume(view,volume:Dictionary,label:String):
 var original=JSON.stringify(volume);var shape=game.build_tools.OpeningArt.segment_selection_geometry(view,volume)
 var h=game.model.WallGeometry.HEIGHT_PIXELS[volume.height]
 # Installed walls use the grid edge as the center of their visible .26-tile
 # thickness. Do not derive expected offsets from the production helper.
 var normal=Vector2.DOWN if volume.axis=="x" else Vector2.RIGHT
 var near_a=volume.a+normal*.13;var near_b=volume.b+normal*.13
 var far_a=volume.a-normal*.13;var far_b=volume.b-normal*.13
 var a=view.iso(near_a.x,near_a.y);var b=view.iso(near_b.x,near_b.y)
 var ah=view.iso(near_a.x,near_a.y,h);var bh=view.iso(near_b.x,near_b.y,h)
 var ab=view.iso(far_a.x,far_a.y,h);var bb=view.iso(far_b.x,far_b.y,h);var bottom_back=view.iso(far_b.x,far_b.y)
 check(volume.a.distance_to(volume.b)==1.0,"one-grid extent "+label)
 check(volume.visual_front==normal*.13 and volume.visual_back==-normal*.13,"visible thickness stays centered on the grid "+label)
 check(shape.edges.size()==18,"nine visible volume edges "+label)
 check(shape.front==PackedVector2Array([a,b,bh,ah]) and shape.cap==PackedVector2Array([ah,bh,bb,ab]),"exact centered front and cap geometry "+label)
 check(shape.cap[0]==shape.front[3] and shape.cap[1]==shape.front[2],"front joins top cap "+label)
 check(shape.cap[2]==bb and shape.near_end[2]==shape.cap[2],"real outer thickness and end-cap corner "+label)
 check(shape.near_end==PackedVector2Array([b,bottom_back,bb,bh]),"side return reaches full wall base "+label)
 check(shape.edges==PackedVector2Array([a,b,b,bh,bh,ah,ah,a,ah,ab,ab,bb,bb,bh,b,bottom_back,bottom_back,bb]),"complete exact centered volume outline "+label)
 check(shape.cap[2].distance_to(shape.cap[1])>1.0,"cap has visible structural depth "+label)
 check(JSON.stringify(volume)==original,"selection geometry is nonmutating "+label)
func check_corner_height(height:String,label:String):
 var host=wall_host("x:0:0");var shape=game.build_tools.OpeningArt.segment_selection_geometry(game.illustration,host)
 var near=Vector2(0,.13);var far=Vector2(0,-.13);var h=game.model.WallGeometry.HEIGHT_PIXELS[height]
 check(host.height==height and shape.cap[0]==game.illustration.iso(near.x,near.y,h) and shape.cap[3]==game.illustration.iso(far.x,far.y,h),label)
func settle():
 game._update_ui();game.illustration.queue_redraw()
 for i in 8:await process_frame
func _initialize():run.call_deferred()
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated UI runner");quit(2);return
 root.size=Vector2i(1360,880);game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame;game.editing=true;game.tray.show();game.model.coins=10000;game._set_catalog_category("Build");await settle()
 var ui=game.compact_ui;var tool=game.build_tools;var art=game.illustration
 # Every starter wall is now an ordinary installed wall, including both
 # boundary axes and the one-tile host containing the starter doorway.
 check(game.model.built_walls.size()==21,"all21 starter boundary walls are covered")
 for wall in game.model.built_walls:
  var key=game.model.WallGeometry.key_of(wall);var host=game.model.get_wall_host(wall.id);var center=(host.a+host.b)*.5;var point=art.iso(center.x,center.y,70)
  var hit=art.hit_wall_host(point);var hit_wall=art.hit_wall(point)
  check(hit.get("host_id","")==wall.id and hit.get("wall_ids",[])==[wall.id],"unit host hit target "+key)
  check(not hit_wall.is_empty() and game.model.WallGeometry.key_of(hit_wall)==key,"unit wall hit target "+key)
  for height in ["full","half"]:
   var volume=host.duplicate(true);volume.height=height;check_volume(art,volume,key+" "+height)
 var point=art.iso(2.5,0,70);var e=InputEventMouseButton.new();e.position=point;e.pressed=true;e.button_index=MOUSE_BUTTON_LEFT
 check(ui.handle_unhandled_input(e),"wall selection consumes pointer")
 check(ui.selected_wall=="x:2:0" and ui.selected_shell=="","selection stores unified one-grid key")
 ui.show_finishes();check(ui.product_target=="x:2:0" and ui.shop_ui.wall_target=="x:2:0","finish menu retains selected segment")
 check(ui.shop_ui.wall_cards["wall:full:original"].visible and ui.shop_ui.wall_cards["wall:half:original"].visible,"installed starter wall retains Original room cards")
 ui.finishes.hide();tool.material="cream_stripe"
 var before=snapshot();var neighbors=game.model.built_walls.duplicate(true);var openings=game.model.wall_openings().duplicate(true)
 for height in ["full","half"]:
  tool.choose(height);tool.refresh(point)
  check(tool.replacing and tool.selected_key=="x:2:0" and tool.preview_valid,"preview targets one installed cell "+height)
  check(tool.replacement_quote.new_cost==game.model.WallGeometry.PRICES[height] and tool.replacement_quote.refund==0,"preview costs one tile "+height)
  check(tool.preview.id==game.model.get_wall("x:2:0").id and tool.preview.height==height and tool.preview.material=="cream_stripe","preview changes only the selected product "+height)
  check_volume(art,tool.OpeningGeometry.wall_host(tool.preview),"middle preview "+height)
  check(game.model.get_wall("x:1:0").height=="full" and game.model.get_wall("x:3:0").height=="full","middle preview leaves both adjacent wall heights unchanged "+height)
  check_corner_height("full","middle preview cannot lower corner "+height)
  check(snapshot()==before,"preview leaves every installed wall and opening unchanged "+height)
 tool._commit();await settle()
 check(ui.wall_review.visible and ui.pending_wall.key=="x:2:0","confirmation retains one-grid key")
 check(ui.wall_review_text.text.begins_with("Selected one-tile wall") and not ui.wall_review_text.text.contains("Entire"),"confirmation describes one tile")
 check(snapshot()==before,"opening confirmation is nonmutating")
 ui.pending_wall={};ui.wall_review.hide();check(snapshot()==before,"cancelling review is nonmutating")
 tool.refresh(point);tool._commit();var dirty_generation=game.platform_dirty_generation;ui._confirm_wall_replacement();await settle()
 check(game.model.coins==9965 and game.saves==0 and game.platform_dirty_generation>dirty_generation,"one confirmation charges35 once and marks progress dirty")
 check(ui.selected_wall=="x:2:0" and ui.selected_shell=="","confirmed selection remains the unified wall segment")
 check(game.model.built_walls.size()==neighbors.size(),"replacement preserves installed wall count")
 for neighbor in neighbors:
  var key=game.model.WallGeometry.key_of(neighbor)
  if key!="x:2:0":check(neighbor==game.model.get_wall(key),"unchanged neighbor "+key)
 check(game.model.get_wall("x:2:0").height=="half" and game.model.get_wall("x:2:0").material=="cream_stripe","one charge buys the combined target height and finish")
 check(game.model.wall_openings()==openings,"replacement preserves every opening's host and world geometry")
 before=snapshot();ui._confirm_wall_replacement();check(snapshot()==before,"a second confirmation cannot charge again")
 # The actual corner wall owns its cap height. Changing it cannot alter the
 # middle wall or the perpendicular corner neighbor, and vice versa.
 var middle=game.model.get_wall("x:2:0").duplicate(true);var corner_neighbor=game.model.get_wall("z:0:0").duplicate(true)
 check(game.model.replace_wall("x:0:0","half","sage_panels"),"corner segment edit")
 check_corner_height("half","corner cap follows its own adjacent segment")
 check(game.model.get_wall("x:2:0")==middle and game.model.get_wall("z:0:0")==corner_neighbor,"corner edit leaves middle and perpendicular wall independent")
 before=snapshot();tool.material="leaf_print";point=art.iso(2.5,0,30)
 for height in ["full","half"]:
  tool.choose(height);tool.refresh(point)
  check(tool.replacing and tool.selected_key=="x:2:0" and tool.preview_valid and tool.preview.height==height,"mixed-height middle preview stays one cell "+height)
  check_corner_height("half","middle preview cannot raise edited corner "+height)
  check(snapshot()==before,"mixed-height preview leaves installed geometry unchanged "+height)
 ui.clear_selection();tool.cancel();await settle()
 var source=game.model.get_wall_attachment(1).duplicate(true);var source_geometry=game.model.OpeningGeometry.aperture(source,game.model.built_walls);var door_point=art.iso(0,4.5,100)
 tool.choose("window");tool.refresh(door_point)
 var window_host=game.model.get_wall("z:0:4");var opening_geometry={}
 if not tool.opening_preview.is_empty():opening_geometry=game.model.OpeningGeometry.aperture(tool.opening_preview,game.model.built_walls)
 check(not tool.opening_preview.is_empty() and tool.opening_preview.host_id==window_host.id and tool.opening_preview.wall_ids==[window_host.id] and is_equal_approx(float(tool.opening_preview.offset),.5),"opening placement keeps exact installed host and local offset")
 check(not opening_geometry.is_empty() and (opening_geometry.a+opening_geometry.b)*.5==Vector2(0,4.5),"opening placement preserves original world center")
 check(game.model.get_wall_attachment(1)==source and game.model.OpeningGeometry.aperture(game.model.get_wall_attachment(1),game.model.built_walls)==source_geometry,"opening preview cannot rewrite starter door or its geometry")
 tool.cancel();await settle()
 ui.selected_wall="z:0:5"
 var recorder=SelectionCapture.new();recorder.projection=art;before=snapshot();tool.draw_wall_selection(recorder)
 var selected_volume=tool.OpeningArt.segment_selection_geometry(recorder,wall_host("z:0:5"))
 check(recorder.fills.is_empty(),"selection has no fill over the cap, wall or doorway hole")
 check(recorder.strokes.size()==1 and stroke(recorder).get("points")==selected_volume.edges,"selection draws complete volume edges")
 check(snapshot()==before,"complete-volume selection does not mutate product, opening, wallet or saves")
 check(stroke(recorder).get("color")==Color("8a8d88"),"passive wall selection uses a soft-gray outline")
 tool.material="leaf_print";tool.choose("full");tool.refresh(art.iso(0,3.5,70));recorder=SelectionCapture.new();recorder.projection=art;tool.draw_wall_selection(recorder)
 check(tool.preview_valid and recorder.strokes.size()==1 and stroke(recorder).get("color")==Color("8a8d88"),"valid wall preview uses a soft-gray outline")
 tool.choose("half");tool.refresh(art.iso(0,5.5,70));recorder=SelectionCapture.new();recorder.projection=art;tool.draw_wall_selection(recorder)
 check(not tool.preview_valid and recorder.strokes.size()==1 and stroke(recorder).get("color")==Color("8a8d88"),"invalid preview keeps the soft-gray outline and validation state")
 for viewport in [Vector2i(1360,880),Vector2i(390,844),Vector2i(566,360)]:
  root.size=viewport;await settle();art.update_projection()
  var limits=art.camera_zoom_limits()
  for camera_zoom in [limits.x,clampf(1.15,limits.x,limits.y),limits.y]:
   art.zoom=camera_zoom;art.update_projection()
   for height in ["full","half"]:
    # This checks rendering at every zoom, including an offscreen host.
    # Pointer hit/quote/commit behavior is exercised above at a visible target.
    tool.mode=height;tool.selected_key="z:0:3";tool.preview=game.model.get_wall(tool.selected_key).duplicate(true);tool.preview.height=height
    recorder=SelectionCapture.new();recorder.projection=art;recorder.ui_scale=art.ui_scale
    before=snapshot();tool.draw_wall_selection(recorder)
    var label=str(viewport)+" zoom="+str(camera_zoom)+" "+height
    var volume=tool.OpeningGeometry.wall_host(tool.preview);selected_volume=tool.OpeningArt.segment_selection_geometry(recorder,volume)
    check(volume.a.distance_to(volume.b)==1.0,"zoom preserves one-wall geometry "+label)
    check(recorder.fills.is_empty(),"no selection wash "+label)
    check(recorder.strokes.size()==1 and stroke(recorder).get("points",PackedVector2Array()).size()==18 and stroke(recorder).get("points")==selected_volume.edges,"complete volume outline "+label)
    check(stroke(recorder).get("color")==Color("8a8d88") and is_equal_approx(float(stroke(recorder).get("width",0)),.35) and stroke(recorder).get("antialias",false),"fine soft-gray stroke keeps subpixel coverage at every zoom "+label)
    check(snapshot()==before,"outline cannot change save or purchase state "+label)
 print("SHELL_SEGMENT_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
