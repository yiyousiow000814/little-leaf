extends SceneTree
## Native GL captures of the real shop using generated state and intercepted saves.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var records=[]
var failures=[]
var out=""
func _initialize():run.call_deferred()
func rect(control:Control)->Dictionary:
 var r=control.get_global_rect();return {"x":r.position.x,"y":r.position.y,"w":r.size.x,"h":r.size.y}
func capture(label:String):
 game._update_ui();game.illustration.queue_redraw()
 for frame in 8:await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 var path=out.path_join(label+".png")
 if image.save_png(path)!=OK:failures.append("capture failed: "+path)
 var ui=game.compact_ui;var shop=ui.shop_ui
 var bottom=maxi(0,floori(shop.root.global_position.y)-90)
 if image.get_region(Rect2i(0,bottom,image.get_width(),image.get_height()-bottom)).save_png(out.path_join(label+"-detail.png"))!=OK:failures.append("detail capture failed: "+label)
 var buttons=[]
 for button in ui.context.get_children():
  if button is Button and button.is_visible_in_tree():buttons.append({"title":button.text,"rect":rect(button)})
 records.append({"label":label,"image":label+".png","viewport":str(root.size),"page":shop.build_page,"mode":game.build_tools.mode,"title":ui.context_label.text,"price":shop.price_label.text,"title_rect":rect(ui.context_label),"price_rect":rect(shop.price_label),"action_rect":rect(shop.action_background),"action_buttons":buttons,"save_calls":game.saves})
func reveal_style(style:String):
 var shop=game.compact_ui.shop_ui
 for page in 3:
  if game.compact_ui.build_scroll.get_global_rect().grow(.5).encloses(shop.tile_cards[style].get_global_rect()):return
  shop._page_products(1)
  await create_timer(.25).timeout
func shell_point(host_id:String)->Vector2:
 var host=game.model.get_wall_host(host_id)
 for fraction in [.25,.5,.75]:
  var world=host.a.lerp(host.b,fraction)
  for height in [40,70,100]:
   var point=game.illustration.iso(world.x,world.y,height)
   if game.build_tools._available(point) and game.illustration.hit_wall_host(point).get("host_id","")==host_id:return point
 return Vector2(-1000,-1000)
func run():
 out=OS.get_environment("OUTPUT")
 if out=="" or not "saveguard" in OS.get_user_data_dir() or DisplayServer.get_name()=="headless":printerr("NATIVE CAPTURE SAVEGUARD FAILED");quit(2);return
 seed(8246);root.size=Vector2i(1360,880)
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame
 game.editing=true;game.tray.show();game.model.coins=1000;game._set_catalog_category("Build");game.compact_ui._set_tray_reveal(1)
 var shop=game.compact_ui.shop_ui
 for view in [Vector2i(1360,880),Vector2i(344,844),Vector2i(390,844),Vector2i(566,360),Vector2i(844,390)]:
  root.size=view
  shop.show_build_products();await capture("%dx%d-build-products"%[view.x,view.y])
  shop.show_tiles();await capture("%dx%d-tiles-shelf"%[view.x,view.y])
  await reveal_style("cream_tile")
  shop.choose_floor_style("cream_tile");game.build_tools.refresh(Vector2.ZERO)
  await capture("%dx%d-tile-selected"%[view.x,view.y])
  shop.show_build_products();game.build_tools.choose("full");game.build_tools.refresh(Vector2.ZERO)
  await capture("%dx%d-wall-selected"%[view.x,view.y])
  game._set_catalog_category("Kitchen")
  for item in game.model.items:
   if item.kind=="stove":game.interaction._select_item(item);break
  await capture("%dx%d-stove-selected"%[view.x,view.y])
  game._set_catalog_category("Build");game.model.floor_finishes.erase("11,8");game.model._notify();shop.show_tiles()
  await capture("%dx%d-tiles-repair-entry"%[view.x,view.y])
  game.model.floor_finishes["11,8"]={"style":"warm_oak","paid_cost":0};game.model._notify()
 root.size=Vector2i(1360,880);shop.show_build_products();game._update_ui()
 for frame in 6:await process_frame
 game.build_tools.material="sage_panels";game.build_tools.choose("full");game.build_tools.refresh(shell_point("shell:west"))
 await capture("1360x880-wall-pay495-preview")
 shop.show_tiles();shop.choose_floor_style("sage_tile")
 var cell=Vector2i(5,5);game.model.floor_finishes["5,5"]={"style":"cream_tile","paid_cost":10}
 game.illustration.update_projection();game.build_tools.refresh(game.illustration.iso(cell.x+.5,cell.y+.5))
 await capture("1360x880-tile-refund-preview")
 game.model.coins=0;game.build_tools.refresh(game.illustration.iso(cell.x+.5,cell.y+.5))
 await capture("1360x880-tile-insufficient-coins")
 var result={"checks":records.size(),"failures":failures,"records":records,"renderer":RenderingServer.get_video_adapter_name(),"player_save_used":false}
 FileAccess.open(out.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("BUILD_TILES_CAPTURE_RESULT ",JSON.stringify(result))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await create_timer(.1).timeout;quit(0 if failures.is_empty() else 1)
