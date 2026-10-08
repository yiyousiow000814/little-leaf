extends SceneTree
## Fixed-upgrade UI transactions and responsive control geometry, no player save.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var ui
var shop
var checks=0
var failures=[]
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
func reveal_parking():
 shop._stop_product_scroll(game.catalog_scroll)
 var bar=game.catalog_scroll.get_h_scroll_bar();game.catalog_scroll.scroll_horizontal=int(maxf(0,bar.max_value-bar.page))
 await settle()
func state()->String:
 return JSON.stringify([game.model.coins,game.model.parking_owned,game.model.parking_paid_cost,game.model.items,game.saves])
func same(before:String,label:String):check(state()==before,label)
func labels(node:Node)->Array:
 var result=[]
 if node is Label:result.append(node)
 for child in node.get_children():result.append_array(labels(child))
 return result
func text_fits(label:Label,context:String):
 if not label.is_visible_in_tree():return
 if label.autowrap_mode==TextServer.AUTOWRAP_OFF:
  var font=label.get_theme_font("font");var font_size=label.get_theme_font_size("font_size")
  for line in label.text.split("\n"):check(font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x<=label.size.x+.6,context+" complete text width: "+line)
 check(label.get_minimum_size().y<=label.size.y+.6,context+" complete text height")
func card_fits(context:String):
 var card=shop.parking_card;var bounds=card.get_global_rect()
 check(card.size.x>=44 and card.size.y>=44,context+" minimum card target")
 check(game.catalog_scroll.get_global_rect().grow(.6).encloses(bounds),context+" whole parking card reachable on rail")
 for label in labels(card):
  text_fits(label,context)
  if label.is_visible_in_tree():check(bounds.grow(.6).encloses(label.get_global_rect()),context+" label stays inside card: "+label.text)
 var art=shop.parking_preview;var art_bounds=Rect2(art.global_position,Vector2(84,54)*art.scale)
 check(bounds.grow(.6).encloses(art_bounds),context+" four-bay thumbnail fits card")
func open_sale():
 await reveal_parking();await click(shop.parking_card)
 check(shop.parking_review.visible,"owned click opens explicit sale review")
 check(ui.has_open_popup() and not shop.root.visible,"sale review participates in modal guard")
func dispose():
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("SAVEGUARD FAILED: use isolated generated profile");quit(2);return
 root.size=Vector2i(1360,880)
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true;await process_frame
 ui=game.compact_ui;shop=ui.shop_ui
 check(not game.catalog_cards.has("parking"),"fixed upgrade is not a placeable furniture catalog product")
 game.model.coins=10000;game._toggle_edit();game._set_catalog_category("Decor");ui._set_tray_reveal(1);await settle();await reveal_parking()
 check(shop.parking_card.visible and not shop.parking_card.disabled,"parking is available in Decor")
 check(shop.parking_price.text==ui.Money.amount(game.model.parking_price()),"card displays model parking price")
 check(shop.parking_card.get_child(0).get_child(1).text=="Parking · 4 bays","card explicitly identifies four fixed bays")
 var before=state();game._set_catalog_category("Tables");await settle()
 check(not shop.parking_card.visible,"parking hidden outside Decor")
 shop._choose_parking();same(before,"hidden-category callback cannot buy")
 game._set_catalog_category("Decor");game.model.coins=game.model.parking_price()-1;await settle();before=state()
 check(shop.parking_card.disabled and shop.parking_status.text=="Need 1","insufficient funds shown and disabled")
 shop._choose_parking();same(before,"insufficient purchase never charges or saves")
 game.model.coins=10000;game.save_recovery_blocked=true;await settle();before=state()
 check(shop.parking_card.disabled and shop.parking_status.text=="Save recovery","save recovery locks purchase visibly")
 shop._choose_parking();same(before,"save recovery callback cannot buy")
 game.save_recovery_blocked=false;game.editing=false;before=state();shop._choose_parking();same(before,"Play callback cannot buy")
 game.editing=true;await settle();await reveal_parking()
 game._choose("plant");await settle()
 check(game.selected_kind=="plant" and is_instance_valid(game.ghost),"purchase begins with a real furnishing preview to cancel")
 var coins=game.model.coins;var saves=game.saves;var items=game.model.items.duplicate(true);var price=game.model.parking_price()
 await click(shop.parking_card)
 check(game.model.parking_owned and game.model.coins==coins-price and game.saves==saves+1,"real card click buys once at model price and requests one save")
 check(game.selected_kind=="" and game.selected_id<0 and not is_instance_valid(game.ghost) and game.model.items==items,"fixed parking creates no placement ghost or movable furniture")
 check(shop.parking_price.text=="Owned" and shop.parking_status.text=="0/4 in use","owned card shows bay occupancy")
 before=state();await open_sale();same(before,"repeated buy click only opens review without mutation")
 check(shop.parking_sell.text=="Sell +"+ui.Money.amount(price) and not shop.parking_sell.disabled,"same-session sale displays full actual paid refund")
 shop._choose_parking();same(before,"extra card callback during modal never sells")
 await click(shop.parking_cancel);same(before,"Cancel leaves parking and wallet unchanged")
 check(not ui.has_open_popup() and shop.root.visible,"Cancel restores existing shop")
 await open_sale()
 var escape=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;root.push_input(escape,true);await settle()
 same(before,"Escape dismisses sale without money or save change")
 check(not shop.parking_review.visible and not ui.has_open_popup(),"Escape closes registered parking popup")
 await open_sale();game._set_catalog_category("Kitchen");await settle();shop._sell_parking()
 same(before,"category change cancels pending sale and late callback")
 check(not shop.parking_review.visible and not ui.has_open_popup(),"category change restores shop without parking popup")
 game._set_catalog_category("Decor");await settle()
 await open_sale()
 var outside=InputEventMouseButton.new();outside.position=Vector2(8,8);outside.global_position=outside.position;outside.button_index=MOUSE_BUTTON_LEFT;outside.pressed=true;root.push_input(outside,true)
 outside=outside.duplicate();outside.pressed=false;root.push_input(outside,true);await settle()
 same(before,"outside pointer dismissal and release do not sell")
 check(not ui.has_open_popup() and shop.root.visible,"outside dismissal restores shop and consumes release")
 await open_sale();await click(shop.parking_sell)
 check(not game.model.parking_owned and game.model.coins==coins and game.saves==saves+2,"explicit sale returns full price once in same Decorate session")
 before=state();shop._sell_parking();same(before,"duplicate sale callback cannot refund again")
 await reveal_parking();await click(shop.parking_card);game._toggle_edit();await settle()
 check(not game.editing and not shop.parking_review.visible,"Done closes parking interaction")
 game._toggle_edit();ui._set_tray_reveal(1);await settle();await open_sale()
 var half=game.model.parking_refund()
 check(half==floori(float(price)*.5) and shop.parking_sell.text=="Sell +"+ui.Money.amount(half),"new Decorate session displays half original paid cost")
 # Closing Decorate invalidates an already open sale review and its callbacks.
 before=state();game._toggle_edit();var after_done=state();shop._sell_parking();same(after_done,"late sale after Done is ignored")
 check(not shop.parking_review.visible,"Done dismisses an open sale popup")
 game._toggle_edit();ui._set_tray_reveal(1);await settle();await open_sale()
 game.save_recovery_blocked=true;await settle();before=state()
 check(shop.parking_sell.disabled and shop.parking_review_text.text.contains("save recovery"),"recovery during sale review visibly disables sale")
 shop._sell_parking();same(before,"recovery blocks pending sale callback")
 game.save_recovery_blocked=false;await settle();await click(shop.parking_cancel)
 # Reserved trips count as in-use bays until the final car departure.
 check(game.model.Parking.reserve(game.model),"valid parking trip reserves occupied UI fixture")
 await settle();before=state();await open_sale()
 check(shop.parking_status.text=="1/4 in use" and shop.parking_sell.disabled,"reserved or occupied bay visibly locks sale")
 check(shop.parking_review_text.text.contains("Wait until all cars have left"),"occupied sale explains when it unlocks")
 shop._sell_parking();same(before,"occupied sale callback cannot mutate wallet or ownership")
 game.model.parking_visits.clear();await settle()
 check(not shop.parking_sell.disabled,"sale unlocks after final visit leaves")
 coins=game.model.coins;saves=game.saves;await click(shop.parking_sell)
 check(not game.model.parking_owned and game.model.coins==coins+half and game.saves==saves+1,"later-session sale credits exactly the advertised half refund")
 # Responsive headless layout checks only; no rendered or graphical benchmark.
 for view in [Vector2i(1360,880),Vector2i(344,844),Vector2i(390,844),Vector2i(566,360),Vector2i(844,390),Vector2i(390,844),Vector2i(1360,880)]:
  root.size=view;game.model.coins=10000;game._set_catalog_category("Decor");await settle();await reveal_parking()
  var context=str(view);check(not ui.viewport_too_small,context+" remains supported")
  card_fits(context+" unowned")
  await click(shop.parking_card);await reveal_parking();card_fits(context+" owned")
  await open_sale()
  check(Rect2(Vector2.ZERO,Vector2(view)).grow(.6).encloses(shop.parking_review.get_global_rect()),context+" review fits viewport")
  for button in [shop.parking_sell,shop.parking_cancel]:check(button.size.x>=44 and button.size.y>=44,context+" review action has 44px target")
  text_fits(shop.parking_review_text,context+" sale explanation")
  # Buttons may be below the fold in a short viewport; use the registered
  # popup scroll to reach the exact existing Sell button before activating it.
  var scroll:ScrollContainer=shop.parking_review.get_child(0);scroll.ensure_control_visible(shop.parking_sell)
  await settle();await click(shop.parking_sell)
  check(not game.model.parking_owned,context+" sale remains usable after responsive transitions")
  game._set_catalog_category("Kitchen");await settle();check(not shop.parking_card.visible,context+" category hides parking")
 print("PARKING_DECOR_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false,"native_render_verified":false}))
 await dispose();quit(0 if failures.is_empty() else 1)
