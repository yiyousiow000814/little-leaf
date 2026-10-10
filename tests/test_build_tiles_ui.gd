extends SceneTree
## Real shop controls and floor input transactions, using generated data only.
const Model=preload("res://scripts/cafe_model.gd")
const NoBottom=preload("res://tests/no_bottom_notifications.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var ui
var shop
var checks=0
var failures=[]
var observations=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func settle():
 game._update_ui()
 for frame in 5:await process_frame
func click(control:Control):
 var point=control.get_global_rect().get_center()
 var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
 await settle()
func labels(node:Node)->Array:
 var result=[]
 if node is Label:result.append(node)
 for child in node.get_children():result.append_array(labels(child))
 return result
func named_button(node:Node,title:String):
 if node is Button:
  if node.text==title:return node
  for label in labels(node):
   if label.text==title:return node
 for child in node.get_children():
  var found=named_button(child,title)
  if found!=null:return found
 return null
func snapshot()->String:
 return JSON.stringify([game.model.coins,game.model.floor_finishes,game.model.items,game.model.owned_parcels,game.model.revision,game.saves])
func point_for(cell:Vector2i)->Vector2:
 game.illustration.update_projection()
 return game.illustration.iso(cell.x+.5,cell.y+.5)
func floor_event(point:Vector2,pressed:bool):
 var event=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
 if pressed:game.build_tools.handle_unhandled_input(event)
 else:game.build_tools.handle_input(event)
func install(cell:Vector2i):
 var point=point_for(cell);game.build_tools.refresh(point);floor_event(point,true);floor_event(point,false)
func select_floor(style:String):
 shop.show_tiles();shop.choose_floor_style(style);await settle()
func same_state(before:String,label:String):check(snapshot()==before,label)
func stable_action(expected_title:String,label:String):
 shop.sync_action_details()
 var title=ui.context_label.text;var price=shop.price_label.text
 check(title==expected_title,label+" stable product title")
 check(shop.price_label!=ui.context_label,label+" separate title and price controls")
 for repeat in 20:
  ui.sync()
  check(ui.context_label.text==title and shop.price_label.text==price,label+" sync keeps title and price "+str(repeat))
  ui.update_pointer()
  check(ui.context_label.text==title and shop.price_label.text==price,label+" pointer keeps title and price "+str(repeat))
 observations.append({"case":label,"title":title,"price":price})
func target(control:Control,label:String,viewport:Rect2):
 check(control.size.x>=43.9 and control.size.y>=43.9,label+" minimum 44px target")
 check(viewport.grow(.5).encloses(control.get_global_rect()),label+" inside viewport")
func text_fits(label:Label,context:String):
 if not label.is_visible_in_tree():return
 if label.autowrap_mode==TextServer.AUTOWRAP_OFF:
  var font=label.get_theme_font("font");var size=label.get_theme_font_size("font_size")
  for line in label.text.split("\n"):check(font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x<=label.size.x+.6,context+" full text fits: "+line+" (glyphs "+str(font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x)+", label "+str(label.size.x)+", minimum "+str(label.get_minimum_size().x)+")")
 check(label.get_minimum_size().y<=label.size.y+.5,context+" full text height fits")
func action_layout(label:String):
 var viewport=Rect2(Vector2.ZERO,Vector2(root.size))
 check(ui.context.visible,label+" action strip shown")
 check(viewport.grow(.5).encloses(shop.action_background.get_global_rect()),label+" action board inside viewport")
 var buttons=[]
 for child in ui.context.get_children():
  if child is Button and child.is_visible_in_tree():
   target(child,label+" "+child.text,viewport);buttons.append(child)
   var face=child.get_node_or_null("PaintedSurface")
   check(face!=null and face.size.y<=child.size.y-7.9,label+" smaller painted face retains full target "+child.text)
   var text_width=0.0
   for line in child.text.split("\n"):text_width=maxf(text_width,child.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,child.get_theme_font_size("font_size")).x)
   check(text_width+19.9<=child.size.x,label+" action has interior text padding "+child.text)
   check(shop.action_background.get_global_rect().grow(.5).encloses(child.get_global_rect()),label+" target inside action board "+child.text)
 for a in buttons.size():
  for b in range(a+1,buttons.size()):check(not buttons[a].get_global_rect().intersects(buttons[b].get_global_rect()),label+" distinct action targets")
 for control in [ui.context_label,shop.price_label]:
  if control.is_visible_in_tree():
   text_fits(control,label)
   check(shop.action_background.get_global_rect().grow(.5).encloses(control.get_global_rect()),label+" label inside action board: "+control.text+" label="+str(control.get_global_rect())+" frame="+str(shop.action_background.get_global_rect()))
   if control.get_line_count()<=1:
    var line_height=control.get_theme_font("font").get_height(control.get_theme_font_size("font_size"))
    var text_top=control.global_position.y
    if control.vertical_alignment==VERTICAL_ALIGNMENT_CENTER:text_top+=(control.size.y-line_height)*.5
    elif control.vertical_alignment==VERTICAL_ALIGNMENT_BOTTOM:text_top+=control.size.y-line_height
    var frame=shop.action_background.get_global_rect()
    check(text_top-frame.position.y>=19.5 and frame.end.y-(text_top+line_height)>=19.5,label+" action text stays inside decorative frame safe inset: "+control.text+" top="+str(text_top-frame.position.y)+" bottom="+str(frame.end.y-(text_top+line_height))+" frame="+str(frame))
func full_shelf_pages(label:String):
 var scroll=ui.build_scroll
 for page in 4:
  await create_timer(.25).timeout
  await settle()
  var shelf=scroll.get_global_rect()
  for card in game.build_panel.get_children():
   if not card is Button or not card.visible:continue
   var bounds=card.get_global_rect()
   if bounds.intersects(shelf.grow(-.5)):check(shelf.grow(.5).encloses(bounds),label+" complete visible card on page "+str(page))
  if shop.product_next.disabled or not shop.product_next.visible:break
  await click(shop.product_next)
func check_card(card:Button,label:String):
 var body=card.get_child(0);var title:Label=body.get_child(1);var price:HBoxContainer=body.get_child(2);var status:Label=body.get_child(3)
 check(title.horizontal_alignment==HORIZONTAL_ALIGNMENT_CENTER,label+" title is centered")
 check(price.alignment==BoxContainer.ALIGNMENT_CENTER,label+" price row is centered")
 check(status.horizontal_alignment==HORIZONTAL_ALIGNMENT_CENTER,label+" status is centered")
 if card.size.x>=180 and not game.compact_ui.shop_ui.root.size.y<144:
  var top=title.position.y;var bottom=price.position.y+price.size.y
  if status.visible:bottom=status.position.y+status.size.y
  check(absf((top+bottom)*.5-(card.size.y-8)*.5)<=1.1,label+" title/price group is vertically balanced")
 check(card.size.x>=44 and card.size.y>=44,label+" minimum card hit target")
 for control in labels(card):
  text_fits(control,label)
  if control.is_visible_in_tree():check(card.get_global_rect().grow(.5).encloses(control.get_global_rect()),label+" label inside card")
func dispose():
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame
func shell_point(host_id:String)->Vector2:
 var host=game.model.get_wall_host(host_id)
 for fraction in [.25,.5,.75]:
  var world=host.a.lerp(host.b,fraction)
  for height in [40,70,100]:
   var point=game.illustration.iso(world.x,world.y,height)
   if game.build_tools._available(point) and game.illustration.hit_wall_host(point).get("host_id","")==host_id:return point
 return Vector2(-1000,-1000)
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("SAVEGUARD FAILED: use the isolated runner");quit(2);return
 root.size=Vector2i(1360,880)
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame
 ui=game.compact_ui;shop=ui.shop_ui
 game.editing=true;game.tray.show();game.model.coins=1000;game._set_catalog_category("Build");ui._set_tray_reveal(1);await settle()
 check(shop.build_page=="products","Build initially shows products")
 check(shop._visible_build_keys().size()==4,"Build shows exactly four product cards")
 for name in ["Wall","Door","Window","Tiles"]:check(named_button(game.build_panel,name)!=null,"Build contains "+name+" product")
 check(not NoBottom.has_property(ui,"floor_access") and not NoBottom.has_property(game.build_tools,"floor_option"),"obsolete floor dropdown route removed")
 var initial=snapshot()
 await click(named_button(game.build_panel,"Tiles"))
 check(shop.build_page=="tiles","Tiles product click opens nested shelf")
 check(shop._visible_build_keys().size()==3,"Tiles shows exactly three style cards")
 check(not ui.has_open_popup(),"Tiles browsing is a product shelf, not a popup")
 for style in game.build_tools.FLOOR_STYLES:
  check(shop.tile_cards.has(style),"nested shelf lists "+style)
  check(game.model.floor_price(style)=={"warm_oak":8,"cream_tile":10,"sage_tile":12}[style],"listed tile price "+style)
  await click(shop.tile_cards[style])
  check(game.build_tools.mode=="floor" and game.build_tools.floor_material==style,"click chooses "+style+" preview")
  same_state(initial,"choosing "+style+" does not buy or save")
  game._cancel_selection();shop.show_tiles();await settle()
 var back=shop.tiles_back
 check(back!=null,"nested shelf provides Back to Build")
 if back!=null:await click(back)
 check(shop.build_page=="products" and game.build_tools.mode=="","Back restores Build and cancels preview")
 same_state(initial,"browsing/back never changes money floors or saves")
 check(not ui.floor_repair_button.visible,"starter repair absent without missing starter tiles")
 game.model.floor_finishes.erase("11,8");game.model._notify();shop.show_tiles();await settle()
 check(ui.floor_repair_button.visible,"starter repair available on Tiles shelf when needed")
 var before_repair_navigation=snapshot()
 shop.show_build_products();await settle()
 check(not ui.floor_repair_button.visible,"starter repair absent from Build products")
 same_state(before_repair_navigation,"repair entry visibility never mutates flooring")
 game.model.floor_finishes["11,8"]={"style":"warm_oak","paid_cost":0};game.model._notify()
 # One matching press/release buys exactly one tile; hovering and pressing do not.
 var cell=Vector2i(5,5);game.model.floor_finishes.erase(game.model._floor_key(cell));game.model._notify()
 await select_floor("warm_oak")
 var before=snapshot();var point=point_for(cell);game.build_tools.refresh(point)
 same_state(before,"hover does not buy")
 stable_action("Warm oak","bare warm oak preview")
 check(game.build_tools.preview_valid,"bare owned tile has valid preview")
 floor_event(point,true);same_state(before,"press alone does not buy")
 var coins=game.model.coins;var saves=game.saves;var installed=game.model.floor_finishes.size()
 floor_event(point,false)
 check(game.model.coins==coins-8 and game.saves==saves+1,"matching release charges 8 and saves exactly once")
 check(game.model.floor_finishes.size()==installed+1 and game.model.floor_style_at(cell)=="warm_oak","release installs exactly one owned tile")
 before=snapshot();floor_event(point,false);same_state(before,"extra release cannot duplicate purchase")
 await select_floor("cream_tile");game.build_tools.refresh(point_for(cell))
 check(game.build_tools.floor_quote.new_cost==10 and game.build_tools.floor_quote.refund==4 and game.build_tools.floor_quote.net==6,"replacement quote preserves half paid-cost refund")
 stable_action("Cream tiles","replacement preview")
 coins=game.model.coins;saves=game.saves;install(cell)
 check(game.model.coins==coins-6 and game.saves==saves+1,"replacement charges net 6 once")
 check(game.model.floor_finishes[game.model._floor_key(cell)]=={"style":"cream_tile","paid_cost":10},"replacement records full new paid cost")
 before=snapshot();install(cell);same_state(before,"same-style tile is free and causes no save")
 stable_action("Cream tiles","already installed preview")
 check(shop.price_label.text.to_lower().contains("no charge"),"already installed price explicitly says no charge")
 await select_floor("sage_tile");game.model.coins=0;game.build_tools.refresh(point_for(cell));before=snapshot()
 check(not game.build_tools.preview_valid and game.build_tools.preview_reason.to_lower().contains("not enough"),"insufficient wallet preview is invalid")
 install(cell);same_state(before,"insufficient funds cannot purchase or save")
 game.model.coins=1000
 # Interrupted gestures stay nonmutating, even if the late release still arrives.
 for interruption in ["drag","escape","right-click","focus-loss","wheel","other-tile","over-ui","back"]:
  await select_floor("sage_tile");point=point_for(cell);before=snapshot();floor_event(point,true)
  match interruption:
   "drag":
    var motion=InputEventMouseMotion.new();motion.position=point+Vector2(25,0);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;game.build_tools.handle_input(motion)
   "escape":
    var event=InputEventKey.new();event.keycode=KEY_ESCAPE;event.pressed=true;game.build_tools.handle_input(event)
   "right-click":
    var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT;event.pressed=true;game.build_tools.handle_input(event)
   "focus-loss":game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
   "wheel":
    var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_WHEEL_UP;event.pressed=true;game.build_tools.handle_input(event)
   "back":shop.show_build_products()
  var release=point_for(cell+Vector2i(1,0)) if interruption=="other-tile" else (ui.cancel_button.get_global_rect().get_center() if interruption=="over-ui" else point)
  floor_event(release,false);same_state(before,interruption+" then late release cannot buy or save")
  game.illustration.pan_offset=Vector2.ZERO;game.interaction.pan_offset=Vector2.ZERO;game.illustration.update_projection()
 # Each style is a one-cell transaction at its own advertised amount.
 for index in game.build_tools.FLOOR_STYLES.size():
  var style=game.build_tools.FLOOR_STYLES[index];var bare=Vector2i(5+index,6)
  game.model.floor_finishes.erase(game.model._floor_key(bare));game.model._notify();await select_floor(style)
  coins=game.model.coins;saves=game.saves;installed=game.model.floor_finishes.size();install(bare)
  check(game.model.coins==coins-game.model.floor_price(style) and game.saves==saves+1,style+" buys at exact listed price")
  check(game.model.floor_finishes.size()==installed+1,style+" purchase changes only one tile")
 # A style change after pointer-down invalidates the pending price receipt.
 await select_floor("warm_oak");point=point_for(cell);before=snapshot();floor_event(point,true)
 shop.choose_floor_style("sage_tile");floor_event(point,false);same_state(before,"style change cancels old pressed purchase")
 # Flooring remains a decorative layer under existing furniture.
 var item=game.model.items[0];var furniture=game.model.items.duplicate(true);var under=Vector2i(int(item.x),int(item.z))
 await select_floor("sage_tile");coins=game.model.coins;saves=game.saves
 check(game.model.place_floor(under,"sage_tile"),"floor model still permits flooring under furniture")
 check(game.model.items==furniture and game.model.coins==coins-12,"under-furniture flooring preserves furnishing and charges once")
 check(game.saves==saves,"model-only fixture does not implicitly save")
 # Generated round trip: inherited zero-paid tiles and custom paid tiles survive UI use.
 game.model.floor_finishes["4,4"]={"style":"cream_tile","paid_cost":0}
 game.model.floor_finishes["6,5"]={"style":"sage_tile","paid_cost":12}
 var expected=game.model.floor_finishes.duplicate(true);coins=game.model.coins
 shop.show_build_products();shop.show_tiles();shop.choose_floor_style("cream_tile");shop.show_build_products();await settle()
 check(game.model.floor_finishes==expected and game.model.coins==coins,"Tiles navigation preserves inherited and custom tile records")
 var path="user://build-tiles-generated.json"
 check(game.model.save(path),"generated floor save succeeds")
 var saved_hash=FileAccess.get_sha256(path);var loaded=Model.new()
 check(loaded.load_save(path),"generated custom/inherited floor save loads")
 check(loaded.floor_finishes==expected and loaded.coins==coins,"custom and inherited floors round trip unchanged")
 check(loaded.floor_quote(Vector2i(4,4),"warm_oak").refund==0 and loaded.floor_quote(Vector2i(6,5),"warm_oak").refund==6,"inherited floor refund stays zero and paid floor refund stays six")
 check(FileAccess.get_sha256(path)==saved_hash,"load leaves source save bytes unchanged")
 # Stable title/price separation also covers other Build actions and furnishing selection.
 for mode in ["half","full","door","window"]:
  game.build_tools.choose(mode);game.build_tools.refresh(Vector2.ZERO);await settle()
  stable_action({"half":"Half wall","full":"Full wall","door":"Door","window":"Window"}[mode],mode+" action")
 # The stable title remains separate from the new one-grid inherited-wall
 # quote after pointer updates and repeated UI synchronization.
 game.build_tools.material="sage_panels";game.build_tools.choose("full")
 var wall_point=shell_point("shell:west");game.build_tools.refresh(wall_point);await settle()
 check(game.build_tools.replacing and game.build_tools.selected_key.begins_with("shell:west#"),"real pointer picks one inherited west-wall grid segment")
 check(game.build_tools.replacement_quote.get("net",-1)==55,"inherited shell replacement quotes one55-coin wall segment")
 before=snapshot();stable_action("Full wall","inherited wall Pay55 replacement")
 check(shop.price_label.text=="Pay 55","one-segment payment is separate from Full wall title")
 same_state(before,"wall quote sync never buys or saves")
 # Layout includes repeated viewport/category transitions and both nested shelves.
 for view in [Vector2i(1360,880),Vector2i(344,844),Vector2i(390,844),Vector2i(566,360),Vector2i(844,390),Vector2i(390,844),Vector2i(1360,880)]:
  root.size=view;shop.show_build_products();await settle()
  var label=str(view);var viewport=Rect2(Vector2.ZERO,Vector2(view))
  check(not ui.viewport_too_small,label+" is supported")
  for title in ["Wall","Door","Window","Tiles"]:check_card(named_button(game.build_panel,title),label+" "+title)
  await full_shelf_pages(label+" Build shelf")
  shop.show_tiles();await settle()
  back=shop.tiles_back
  if back!=null:target(back,label+" Back to Build",viewport)
  for style in game.build_tools.FLOOR_STYLES:check_card(shop.tile_cards[style],label+" "+style)
  await full_shelf_pages(label+" Tiles shelf")
  game.model.floor_finishes.erase("11,8");game.model._notify();shop.show_tiles();await settle()
  target(ui.floor_repair_button,label+" repair entry",viewport)
  for style in game.build_tools.FLOOR_STYLES:check_card(shop.tile_cards[style],label+" repair shelf "+style)
  for header in [shop.tiles_back,shop.tiles_title]:
   if header.is_visible_in_tree():check(not ui.floor_repair_button.get_global_rect().intersects(header.get_global_rect()),label+" repair entry does not overlap "+header.name)
  game.model.floor_finishes["11,8"]={"style":"warm_oak","paid_cost":0};game.model._notify();await settle()
  for arrow in [shop.product_back,shop.product_next]:
   if arrow.visible:target(arrow,label+" product arrow",viewport)
  await select_floor("cream_tile");game.build_tools.refresh(Vector2.ZERO);await settle();action_layout(label+" floor")
  game.build_tools.choose("full");await settle();action_layout(label+" wall")
  game._set_catalog_category("Decor");game._choose("plant");await settle();action_layout(label+" furnishing")
  game._set_catalog_category("Kitchen")
  var stove={}
  for furnishing in game.model.items:
   if furnishing.kind=="stove":stove=furnishing;break
  check(not stove.is_empty(),label+" existing stove fixture present")
  if not stove.is_empty():
   game.interaction._select_item(stove);await settle();action_layout(label+" existing stove")
   check(ui.rotate_button.visible and ui.remove_button.visible and ui.cancel_button.visible,label+" stove retains rotate, sell and cancel actions")
  game._set_catalog_category("Build");await settle()
  check(shop.build_page=="products","returning category resets Build products "+label)
  NoBottom.verify(game,check,label)
 print("BUILD_TILES_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"save_writes":game.saves,"player_save_used":false}))
 await dispose();quit(0 if failures.is_empty() else 1)
