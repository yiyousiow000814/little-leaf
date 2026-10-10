extends SceneTree
## Actual map tap/modal transactions in a disposable profile; optional native PNGs.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
const Sign=preload("res://scripts/cafe_parking_sign.gd")
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
 game._update_ui();game.illustration.queue_redraw()
 for frame in 5:await process_frame
func pointer(point:Vector2,pressed:bool):
 var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;root.push_input(e,true)
func click(control:Control):
 var point=control.get_global_rect().get_center();pointer(point,true);pointer(point,false);await settle()
func focus_sign():
 game.illustration.update_projection()
 game.illustration.pan_offset+=Vector2(root.size)*Vector2(.62,.44)-Sign.bounds(game.illustration).get_center()
 await settle()
func tap_sign():
 await focus_sign();var point=Sign.bounds(game.illustration).get_center();pointer(point,true);pointer(point,false);await settle()
func state()->String:
 return JSON.stringify([game.model.coins,game.model.parking_owned,game.model.parking_paid_cost,game.model.items,game.saves])
func capture(name:String):
 var output=OS.get_environment("PARKING_SIGN_CAPTURE_OUTPUT")
 if output.is_empty():return
 await RenderingServer.frame_post_draw
 var path=output.path_join(name+".png")
 check(root.get_texture().get_image().save_png(path)==OK,"native capture "+name)
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("SAVEGUARD FAILED");quit(2);return
 root.size=Vector2i(1360,880);game=TestMain.new();root.add_child(game);game.set_process(false);await process_frame
 if game.cafe_intro!=null:game.cafe_intro.finish()
 game.tutorial.skip();game.paused=true;game.model.set_operating_open(true)
 ui=game.compact_ui;shop=ui.shop_ui;game.model.coins=10000;await focus_sign()
 check(not game.editing and not shop.parking_card.visible,"normal play has no parking purchase catalog card")
 check(game.illustration.hit_parking_sign(Sign.bounds(game.illustration).get_center()),"render and hit share fixed sign anchor")
 await capture("01-map-for-sale")
 var before=state();await tap_sign()
 check(shop.parking_review.visible and ui.has_open_popup(),"real map tap opens registered purchase modal")
 check(shop.parking_sell.text=="Buy 2,000" and not shop.parking_sell.disabled,"explicit model price purchase action")
 check(state()==before,"opening sign does not charge or create bays")
 await capture("02-purchase-review")
 await click(shop.parking_cancel);check(state()==before and not ui.has_open_popup(),"Cancel spends nothing and closes modal")
 await capture("03-cancelled-map")
 # A world pan beginning on the sign keeps existing camera gesture ownership.
 await focus_sign();var point=Sign.bounds(game.illustration).get_center();pointer(point,true)
 var motion=InputEventMouseMotion.new();motion.position=point+Vector2(35,10);motion.global_position=motion.position;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
 pointer(motion.position,false);await settle()
 check(not ui.has_open_popup() and state()==before,"drag on sign pans without purchase")
 await focus_sign();point=Sign.bounds(game.illustration).get_center();pointer(point,true);game.interaction.on_focus_lost();pointer(point,false);await settle()
 check(not ui.has_open_popup() and state()==before,"focus loss cancels held sign tap")
 game.model.coins=1999;before=state();await tap_sign()
 check(shop.parking_sell.disabled and shop.parking_review_text.text.contains("Need 1 more"),"insufficient funds explained and disabled")
 shop._sell_parking();check(state()==before,"late insufficient callback is atomic")
 await capture("04-insufficient-funds");await click(shop.parking_cancel)
 game.model.coins=10000;await tap_sign();game.save_recovery_blocked=true;await settle();before=state()
 check(shop.parking_sell.disabled,"recovery disables open purchase")
 shop._sell_parking();check(state()==before,"recovery blocks purchase callback")
 game.save_recovery_blocked=false;await click(shop.parking_cancel);await tap_sign()
 var coins=game.model.coins;var saves=game.saves;var items=game.model.items.duplicate(true)
 await click(shop.parking_sell)
 check(game.model.parking_owned and game.model.coins==coins-2000 and game.saves==saves+1,"actual Buy unlocks once and requests one save")
 check(game.model.items==items and game.selected_kind=="" and not is_instance_valid(game.ghost),"fixed bays create no furniture or placement ghost")
 check(not ui.has_open_popup() and not game.illustration.hit_parking_sign(Sign.bounds(game.illustration).get_center()),"unlocked bays replace sale sign")
 before=state();shop._sell_parking();shop.show_parking_purchase();await tap_sign()
 check(state()==before and not ui.has_open_popup(),"repeat activation never charges or duplicates bays")
 await capture("05-unlocked-four-bays")
 check(game.model.save("user://parking-map-purchase.json"),"synthetic owned save")
 check(game.model.load_save("user://parking-map-purchase.json"),"owned reload")
 await settle();check(state()==before,"reload retains wallet ownership and no duplicate charge")
 await capture("06-owned-reload")
 check(game.model.Parking.reserve(game.model,4),"unlocked bays admit a real four-member car")
 check(game.model.parking_visits.size()==1 and game.model.parking_visits[0].members.size()==4,"bay usable after map purchase reload")
 game.model.parking_visits.clear()
 game._toggle_edit();game._set_catalog_category("Decor");ui._set_tray_reveal(1);await settle()
 check(shop.parking_card.visible,"owned sale review remains reachable in Decorate")
 shop._choose_parking();await settle()
 check(shop.parking_review.visible and shop.parking_sell.text=="Sell +1,000","map purchase retains existing later-session refund policy")
 before=state();await click(shop.parking_cancel);check(state()==before,"owned sale Cancel preserves bays")
 game._toggle_edit();await settle()
 for view in [Vector2i(390,844),Vector2i(844,390)]:
  root.size=view;await settle();game.model.parking_owned=false;game.model.parking_paid_cost=0;game.model.coins=10000;await tap_sign()
  check(shop.parking_review.visible and not ui.viewport_too_small,"supported viewport map action "+str(view))
  check(Rect2(Vector2.ZERO,Vector2(view)).grow(1).encloses(shop.parking_review.get_global_rect()),"purchase modal fits "+str(view))
  check(shop.parking_sell.size.x>=44 and shop.parking_sell.size.y>=44,"purchase target at least44px "+str(view))
  await click(shop.parking_cancel)
 var owned=[weakref(game),weakref(game.model),weakref(game.illustration),weakref(shop.parking_review)]
 var audio=[]
 for player in game.audio_players.values():
  audio.append(weakref(player.stream))
  if player.playing:audio.append(weakref(player.get_stream_playback()))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame
 # Native audio playback is released by the mixer after stop(), not by the
 # same render frame. The fixture must not quit during that handoff.
 await create_timer(.25).timeout
 for reference in owned:check(reference.get_ref()==null,"scene/model/art/purchase modal released")
 for reference in audio:check(reference.get_ref()==null,"stopped audio stream/playback released")
 print("PARKING_DECOR_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false,"native_render_verified":not OS.get_environment("PARKING_SIGN_CAPTURE_OUTPUT").is_empty()}))
 quit(0 if failures.is_empty() else 1)
