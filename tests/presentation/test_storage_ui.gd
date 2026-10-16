extends SceneTree
class Fixture extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():return true
var checks=0
var failures=[]
var game
var capture_dir=OS.get_environment("LL_CAPTURE_OUTPUT")
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func settle():
 game._update_ui()
 for frame in 4:await process_frame
func click(control:Control):
 var point=control.get_global_rect().get_center()
 var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
 await settle()
func run():
 if not "saveguard" in OS.get_user_data_dir():quit(2);return
 game=Fixture.new();root.add_child(game);game.set_process(false);game.paused=true;await process_frame
 for kind in ["plant","lamp","sink","stove"]:
  for count in (105 if kind=="plant" else 1):
   game.model.storage.items.append({"id":game.model._next_item_id,"kind":kind,"x":0,"z":0,"rot":0,"paid_cost":0});game.model._next_item_id+=1
 game.model.storage_used=true;game._toggle_edit();game.compact_ui.set_tray_open(true)
 for frame in 25:await process_frame
 game._set_catalog_mode("Storage");await settle()
 var shop=game.compact_ui.shop_ui
 check(game.catalog_category=="All" and not game.category_buttons.Build.visible and game.category_buttons.All.visible,"Storage opens all owned categories, excludes Build")
 check(game.catalog_cards.plant.visible and not game.catalog_cards.rug.visible,"only owned catalogue entries appear")
 check(game.catalog_prices.plant.text=="Owned ×105" and not shop.price_icons.plant.visible,"quantity is real stock without arbitrary gift cap or coin price")
 game._set_catalog_query("LAMP");await settle()
 check(game.catalog_cards.lamp.visible and not game.catalog_cards.plant.visible,"case-insensitive name search filters stock")
 game._set_catalog_query("not an item");await settle();check(shop.empty_stock.visible,"no-result state is explicit")
 game._set_catalog_query("");game._set_catalog_category("Cleaning");await settle()
 check(game.catalog_cards.sink.visible and not game.catalog_cards.plant.visible,"shared categories filter owned stock")
 game._set_catalog_category("All");game.model.storage.items[0].rot=2;game._choose("plant");await settle()
 check(game.rotation_step==2,"owned selection starts with the stored rotation")
 check(game.selected_stored_id>=0 and "Storage" in shop.price_label.text and not shop.action_coin.visible,"selected owned item says free Storage source")
 game._cancel_selection()
 for view in [Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390)]:
  root.size=view;await settle()
  var board=shop.background.get_global_rect();var viewport=Rect2(Vector2.ZERO,Vector2(view))
  check(viewport.encloses(board),"Shop/Storage board stays inside "+str(view))
  for control in [shop.shop_mode,shop.storage_mode,shop.category_picker]:
   check(board.encloses(control.get_global_rect()),"mode/search stays inside board "+str(view))
   check(control.size.y>=44,"touch target is at least44 "+str(view))
  check(not shop.shop_mode.get_global_rect().intersects(shop.storage_mode.get_global_rect()) and not shop.storage_mode.get_global_rect().intersects(shop.category_picker.get_global_rect()),"mode/search controls do not overlap "+str(view))
  if capture_dir!="":
   await RenderingServer.frame_post_draw
   check(root.get_texture().get_image().save_png(capture_dir.path_join("storage-"+str(view.x)+"x"+str(view.y)+".png"))==OK,"capture "+str(view))
  await click(shop.category_picker)
  check(shop.category_panel.visible and viewport.encloses(shop.category_panel.get_global_rect()) and shop.category_panel.get_global_rect().encloses(shop.search.get_global_rect()),"category popup keeps search reachable "+str(view))
  await click(shop.search)
  var key=InputEventKey.new();key.keycode=KEY_S;key.unicode=115;key.pressed=true;root.push_input(key,true);key=key.duplicate();key.pressed=false;root.push_input(key,true);await settle()
  check(game.catalog_query=="s","real keyboard input reaches the stock search "+str(view))
  if capture_dir!="":
   await RenderingServer.frame_post_draw
   check(root.get_texture().get_image().save_png(capture_dir.path_join("storage-filter-open-"+str(view.x)+"x"+str(view.y)+".png"))==OK,"capture open category/search "+str(view))
  shop.search.text="";shop.search.text_changed.emit("")
  shop.category_panel.hide();await settle()
  game.selected_id=int(game.model.items.filter(func(i):return i.kind=="stove")[0].id);await settle()
  var action_board=shop.action_background.get_global_rect()
  check(viewport.encloses(action_board),"selected-action board stays inside "+str(view))
  for button in [game.compact_ui.store_button,game.compact_ui.remove_button]:
   check(action_board.encloses(button.get_global_rect()),"Store/Sell stay inside selected-action board "+str(view))
  if capture_dir!="":
   await RenderingServer.frame_post_draw
   check(root.get_texture().get_image().save_png(capture_dir.path_join("store-action-"+str(view.x)+"x"+str(view.y)+".png"))==OK,"capture selected "+str(view))
  game._cancel_selection();await settle()
 root.size=Vector2i(1360,880);game._set_catalog_mode("Shop");await settle()
 check(not game.category_buttons.All.visible and game.category_buttons.Build.visible and game.catalog_prices.plant.text=="45","Shop restores prices and purchasable categories")
 var original=game.model.items.duplicate(true);var wallet=game.model.coins;var id=int(game.model.items.filter(func(i):return i.kind=="stove")[0].id)
 game.selected_id=id;await settle();check(game.compact_ui.store_button.visible and game.compact_ui.remove_button.visible,"Store and Sell are separate selected-item actions")
 game.compact_ui.store_button.pressed.emit();await settle()
 check(game.model.get_item(id).is_empty() and game.model.stored_ids("stove").has(id) and game.model.coins==wallet,"actual Store button packs without refund")
 game._cancel_edit();check(game.model.items==original and game.model.coins==wallet and not game.model.stored_ids("stove").has(id),"session Cancel restores exact pre-Store ownership")
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 game.queue_free();await process_frame;await process_frame
 print("STORAGE_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false,"pixels_inspected":false}))
 quit(0 if failures.is_empty() else 1)
