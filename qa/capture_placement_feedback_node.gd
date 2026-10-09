extends Node
class SyntheticMain extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=false;MinimalStart.apply(model)
 func _save():return true
var observations=[]
func shot(viewport,label,game):
 for frame in 6:
  game._update_ui();await get_tree().process_frame
 await get_tree().create_timer(.7).timeout
 viewport.get_texture().get_image().save_png("res://placement-"+label+".png")
func _ready():
 if not "saveguard" in OS.get_user_data_dir():
  printerr("Use a disposable saveguard capture project");get_tree().quit(2);return
 for style in ["warm_oak","cream_tile","sage_tile"]:
  var viewport=SubViewport.new();viewport.size=Vector2i(1360,880);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
  var game=SyntheticMain.new();viewport.add_child(game);game.cafe_intro.finish();game.paused=true;game.set_process(false);game.illustration.set_process(false)
  for x in 12:
   for z in 9:game.model.floor_finishes["%d,%d"%[x,z]]={"style":style,"paid_cost":0}
  game.model._notify();game._toggle_edit();game.category_buttons["Decor"].pressed.emit();game.compact_ui._set_tray_reveal(1)
  await get_tree().create_timer(1.0).timeout
  game.illustration.zoom=1.25;game.illustration.update_projection()
  game.interaction._pan_by(game.illustration.camera_safe_rect().get_center()-game.illustration.iso(5.5,5.5))
  game.catalog_cards["plant"].pressed.emit();game.interaction.refresh(game.illustration.iso(7.5,7.5));game.illustration.queue_redraw()
  observations.append({"style":style,"valid_preview":game.interaction.drag_valid,"cell":str(game.interaction.drag_cell)})
  await shot(viewport,style+"-valid",game)
  var occupied=game.model.items[0];game.interaction.refresh(game.illustration.iso(occupied.x+.5,occupied.z+.5));game.illustration.queue_redraw()
  observations.append({"style":style,"invalid_preview":not game.interaction.drag_valid,"cell":str(game.interaction.drag_cell)})
  await shot(viewport,style+"-invalid",game)
  game._cancel_selection();game._set_catalog_category("Build");game.compact_ui.shop_ui.show_tiles();game.build_tools.floor_material="cream_tile";game.build_tools.choose("floor")
  var start=game.illustration.iso(4.5,7.5);var finish=game.illustration.iso(7.5,7.5)
  game.build_tools.paint_stroke.begin(start);game.build_tools.paint_stroke.drag(finish);game.illustration.queue_redraw()
  observations.append({"style":style,"stroke_ok":game.build_tools.paint_stroke.receipt.get("ok",false),"count":game.build_tools.paint_stroke.receipt.get("count",0),"net":game.build_tools.paint_stroke.receipt.get("net",0)})
  await shot(viewport,style+"-tile-stroke",game)
  viewport.queue_free();await get_tree().process_frame
 for view in [Vector2i(390,844),Vector2i(844,390)]:
  var viewport=SubViewport.new();viewport.size=view;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
  var game=SyntheticMain.new();viewport.add_child(game);game.cafe_intro.finish();game.paused=true;game.set_process(false);game.illustration.set_process(false)
  game._toggle_edit();game.category_buttons["Build"].pressed.emit();game.compact_ui._set_tray_reveal(1);game.compact_ui.shop_ui.show_tiles()
  for frame in 8:game._update_ui();await get_tree().process_frame
  if view.x<440:
   game.compact_ui.shop_ui.product_next.pressed.emit();await get_tree().create_timer(.3).timeout
  game.compact_ui.shop_ui.tile_cards["cream_tile"].pressed.emit()
  game.interaction._pan_by(game.illustration.camera_safe_rect().get_center()-game.illustration.iso(5.5,7.5))
  game.build_tools.paint_stroke.begin(game.illustration.iso(4.5,7.5));game.build_tools.paint_stroke.drag(game.illustration.iso(7.5,7.5));game.illustration.queue_redraw()
  await shot(viewport,"price-%dx%d"%[view.x,view.y],game)
  observations.append({"viewport":str(view),"count":game.build_tools.paint_stroke.receipt.get("count",0),"net":game.build_tools.paint_stroke.receipt.get("net",0),"stroke_ok":game.build_tools.paint_stroke.receipt.get("ok",false)})
  viewport.queue_free();await get_tree().process_frame
 FileAccess.open("res://placement-capture.json",FileAccess.WRITE).store_string(JSON.stringify(observations,"  "))
 get_tree().quit()
