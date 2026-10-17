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
 for frame in 5:await process_frame
func click(control:Control):
 await click_point(control.get_global_rect().get_center())
func click_point(point:Vector2):
 var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
 await settle()
func category(name:String):
 var shop=game.compact_ui.shop_ui
 if shop.category_picker.visible:
  if not shop.category_panel.visible:await click(shop.category_picker)
  await click(shop.category_panel_buttons[name])
 else:
  shop.category_scroll.ensure_control_visible(game.category_buttons[name])
  for frame in 5:await process_frame
  await click(game.category_buttons[name])
 check(game.catalog_category==name,"real category input selects "+name)
func settled_page():
 await create_timer(.3).timeout
 await settle()
func show_count(kind:String,view:Vector2i):
 var shop=game.compact_ui.shop_ui
 for attempt in 8:
  if game.catalog_scroll.get_global_rect().encloses(game.catalog_cards[kind].get_global_rect()):break
  await click(shop.product_next);await settled_page()
 check(game.catalog_scroll.get_global_rect().encloses(game.catalog_cards[kind].get_global_rect()),"count example is fully visible "+kind+str(view))
 board_fit("Storage count "+kind,view)
 await capture("storage-count"+shop.stock_counts[kind].text,view)
func board_fit(mode:String,view:Vector2i):
 var shop=game.compact_ui.shop_ui
 var board=shop.background.get_global_rect();var interior=board.grow_individual(-26,-23,-26,-23)
 check(Rect2(Vector2.ZERO,Vector2(view)).encloses(board),mode+" board inside viewport "+str(view))
 for control in [shop.shop_mode,shop.storage_mode,shop.category_picker,shop.category_scroll,shop.category_back,shop.category_more,shop.product_back,shop.product_next,game.catalog_scroll]:
  if control.is_visible_in_tree():check(interior.encloses(control.get_global_rect()),mode+" controls inside painted wood "+control.name+str(view))
 for card in game.catalog_cards.values():
  if not card.visible:continue
  var painted=card.get_global_rect().intersection(game.catalog_scroll.get_global_rect())
  check(not painted.has_area() or interior.encloses(painted),mode+" visible card inside painted wood "+str(view))
  check(not painted.has_area() or game.catalog_scroll.get_global_rect().grow(.5).encloses(card.get_global_rect()),mode+" resting page shows whole cards "+str(view))
  for child in card.get_child(0).get_children():
   if child is Control and child.is_visible_in_tree():check(card.get_global_rect().encloses(child.get_global_rect()),mode+" card contents stay inside "+str(view))

func capture(state:String,view:Vector2i):
 if capture_dir=="":return
 await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png(capture_dir.path_join(state+"-"+str(view.x)+"x"+str(view.y)+".png"))==OK,"capture "+state+str(view))
func run():
 if not "saveguard" in OS.get_user_data_dir():quit(2);return
 game=Fixture.new();root.add_child(game);game.set_process(false);game.paused=true;await process_frame
 for kind in ["plant","lamp","bookshelf","rug","divider","sink","stove"]:
  var quantity=105 if kind=="plant" else (2 if kind=="lamp" else 1)
  for count in quantity:
   game.model.storage.items.append({"id":game.model._next_item_id,"kind":kind,"x":0,"z":0,"rot":0,"paid_cost":0});game.model._next_item_id+=1
 game.model.storage_used=true;game._toggle_edit();game._set_catalog_category("Decor");game.compact_ui.set_tray_open(true)
 for frame in 25:await process_frame
 game._set_catalog_mode("Storage");await settle()
 var shop=game.compact_ui.shop_ui
 check(game.catalog_category=="Decor" and not game.category_buttons.Build.visible and not game.category_buttons.has("All"),"Storage keeps Decorate category and has no All or Build")
 check(shop.category_panel.find_children("*","LineEdit",true,false).is_empty(),"categories contain no text input")
 check(game.catalog_cards.plant.visible and not game.catalog_cards.stove.visible,"shared categories filter owned catalogue")
 check(int(game.catalog_stock.plant)==105 and shop.stock_counts.plant.text=="105","plain crate count reuses real stock including105")
 check(game.catalog_cards.size()==game.model.catalog.size(),"one shared card per catalogue kind, not per owned item")
 game._set_catalog_category("Drinks");await settle();check(shop.empty_stock.visible,"empty owned category stays explicit")
 game._set_catalog_category("Decor");game.model.storage.items[0].rot=2;game._choose("plant");await settle()
 check(game.rotation_step==2,"owned selection starts with stored rotation")
 check(game.selected_stored_id>=0 and not shop.price_label.visible and not shop.action_coin.visible,"owned preview adds no free or sales copy")
 game._cancel_selection()
 for view in [Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390)]:
  root.size=view;await settle()
  await click(shop.shop_mode);await category("Decor")
  check(game.catalog_mode=="Shop" and game.category_buttons.Build.visible,"Shop source and categories retained "+str(view))
  check(game.catalog_prices.plant.text=="45" and not shop.stock_badges.plant.visible,"Shop retains price and no inventory badge "+str(view))
  board_fit("Shop",view)
  await capture("shop",view)
  await click(shop.storage_mode)
  var board=shop.background.get_global_rect();var viewport=Rect2(Vector2.ZERO,Vector2(view))
  var interior=board.grow_individual(-26,-23,-26,-23)
  check(viewport.encloses(board),"board stays inside viewport "+str(view))
  for control in [shop.shop_mode,shop.storage_mode,shop.category_picker,shop.category_scroll,shop.category_back,shop.category_more,shop.product_back,shop.product_next]:
   if not control.is_visible_in_tree():continue
   check(interior.encloses(control.get_global_rect()),"control stays inside painted wood interior "+control.name+str(view))
   check(control.size.y>=44,"touch target remains44 "+control.name+str(view))
  check(not shop.shop_mode.get_global_rect().intersects(shop.storage_mode.get_global_rect()),"source tabs do not overlap "+str(view))
  var rail=game.catalog_scroll.get_global_rect()
  check(interior.encloses(rail),"product rail stays inside painted wood interior "+str(view))
  for kind in game.catalog_cards:
   var card:Button=game.catalog_cards[kind]
   if not card.visible:continue
   var body=card.get_child(0)
   check(not body.get_child(1).visible and not body.get_child(2).visible and not body.get_child(3).visible,"owned card has no name/price/status copy "+kind+str(view))
   check(shop.stock_badges[kind].visible and shop.stock_counts[kind].text==str(int(game.catalog_stock[kind])),"small crate has plain stock number "+kind+str(view))
   check(card.get_global_rect().encloses(shop.stock_badges[kind].get_global_rect()),"crate badge stays inside item card "+kind+str(view))
   var digits:Label=shop.stock_counts[kind];var font=digits.get_theme_font("font");var font_size=digits.get_theme_font_size("font_size")
   var ink=font.get_string_size(digits.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
   check(not digits.clip_text and font_size>=14 and digits.size.x>=ceilf(ink.x) and digits.size.y>=ceilf(font.get_height(font_size)),"all stock digits have readable glyph bounds "+kind+str(view))
   check(shop.stock_badges[kind].get_global_rect().encloses(digits.get_global_rect()) and card.get_global_rect().encloses(digits.get_global_rect()),"stock number is not clipped by badge/card "+kind+str(view))
   var painted=card.get_global_rect().intersection(rail)
   check(not painted.has_area() or interior.encloses(painted),"visible item card stays inside board "+kind+str(view))
  board_fit("Storage",view)
  var full_cards=0
  for kind in game.catalog_cards:
   var card:Button=game.catalog_cards[kind]
   if card.visible and rail.encloses(card.get_global_rect()):full_cards+=1
   if card.visible:
    check(card.size.x>=44 and card.size.x<=96,"icon-only width remains compact with44px minimum "+kind+str(view))
    var art_slot=card.get_child(0).get_child(0).get_global_rect()
    check(not art_slot.intersects(shop.stock_badges[kind].get_global_rect()),"crate digits do not overlap the original art slot "+kind+str(view))
  check(full_cards>=(5 if view.x==1360 else (2 if view.x==390 else 3)),"denser full-card Storage page "+str(view))
  await capture("storage",view)
  await show_count("lamp",view);await show_count("bookshelf",view)
  if not shop.product_next.disabled:
   await click(shop.product_next);await settled_page();board_fit("Storage next page",view)
  for attempt in 8:
   if shop.product_back.disabled:break
   await click(shop.product_back);await settled_page()
  if shop.category_picker.visible:
   await click(shop.category_picker)
   check(shop.category_panel.visible and viewport.encloses(shop.category_panel.get_global_rect()),"category-only picker fits viewport "+str(view))
   check(shop.category_panel.find_children("*","LineEdit",true,false).is_empty() and not shop.category_panel_buttons.has("All"),"picker has no search or All "+str(view))
  else:
   check(shop.category_scroll.visible and not shop.category_picker.visible,"Decorate category rail retained "+str(view))
  await capture("storage-categories",view)
  await category("Cleaning")
  check(game.catalog_cards.sink.visible and not game.catalog_cards.plant.visible,"category selection filters owned items "+str(view))
  await category("Decor")
  game.selected_id=int(game.model.items.filter(func(i):return i.kind=="stove")[0].id);await settle()
  var action_board=shop.action_background.get_global_rect()
  check(viewport.encloses(action_board),"selected action board stays inside "+str(view))
  for button in [game.compact_ui.store_button,game.compact_ui.remove_button]:
   check(action_board.encloses(button.get_global_rect()),"Store and Sell stay separate inside action board "+str(view))
  await capture("store-action",view)
  game._cancel_selection();await settle()
 # Include the existing344px minimum, not only the photographed390px portrait.
 for view in [Vector2i(344,844),Vector2i(360,640)]:
  root.size=view
  for mode in ["Shop","Storage"]:
   game._set_catalog_mode(mode);await settle();board_fit(mode,view)
   check(shop.shop_mode.size.y>=44 and shop.storage_mode.size.y>=44 and shop.category_picker.size.y>=44,"minimum-width touch targets stay44")
   check(shop.shop_mode.get_theme_font_size("font_size")==14 and shop.storage_mode.get_theme_font_size("font_size")==14,"minimum-width source type is not shrunk")
 root.size=Vector2i(1360,880);game.model.coins=0;game._set_catalog_mode("Shop");game._set_catalog_category("Decor");await settle()
 check(shop.affordability_labels.plant.visible and shop.affordability_labels.plant.text=="Need 45","Shop affordability restores after Storage")
 check(game.catalog_cards.plant.accessibility_name==game.model.name_of("plant") and "Storage" not in game.catalog_cards.plant.accessibility_description,"Shop accessibility restores after Storage")
 game.model.coins=1200;game._set_catalog_category("Build");game._set_catalog_mode("Storage");await settle()
 check(game.catalog_category=="Tables","Build falls back to first existing furniture category")
 var original=game.model.items.duplicate(true);var wallet=game.model.coins;var id=int(game.model.items.filter(func(i):return i.kind=="stove")[0].id)
 game.selected_id=id;await settle();check(game.compact_ui.store_button.visible and game.compact_ui.remove_button.visible,"Store and Sell remain distinct")
 await click(game.compact_ui.store_button)
 check(game.model.get_item(id).is_empty() and game.model.stored_ids("stove").has(id) and game.model.coins==wallet,"real Store click packs without refund")
 check(int(game.catalog_stock.stove)==2 and shop.stock_counts.stove.text=="2","Store refreshes shared stock count")
 await category("Kitchen");await click(game.catalog_cards.stove)
 check(game.selected_stored_id==id,"actual stock card keeps stored furnishing identity")
 var original_stove=original.filter(func(item):return int(item.id)==id)[0]
 await click_point(game.illustration.iso(float(original_stove.x)+.5,float(original_stove.z)+.5))
 check(not game.model.get_item(id).is_empty() and game.model.coins==wallet,"real floor click places owned item without purchase")
 check(int(game.catalog_stock.stove)==1 and shop.stock_counts.stove.text=="1","place-back refreshes shared stock count")
 game.selected_id=id;await settle();await click(game.compact_ui.store_button)
 check(int(game.catalog_stock.stove)==2,"second Store remains one transfer")
 game._cancel_edit();check(game.model.items==original and game.model.coins==wallet and not game.model.stored_ids("stove").has(id),"session Cancel restores exact pre-Store ownership")
 check(int(game.catalog_stock.stove)==1,"whole-session Cancel refreshes stock cache to original baseline")
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 game.queue_free();await process_frame;await process_frame
 print("STORAGE_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false,"pixels_inspected":false}))
 quit(0 if failures.is_empty() else 1)
