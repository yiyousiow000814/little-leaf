extends SceneTree
## Real scene and callbacks, with synthetic startup profiles and no player save.
const NoBottom=preload("res://tests/no_bottom_notifications.gd")
class TestMain extends "res://scripts/main.gd":
 var startup_kind="fresh"
 var save_calls=0
 func _load_startup():
  save_writes_suppressed=true
  fresh_start=startup_kind!="loaded"
  if startup_kind=="loaded":
   assert(model.load_save("res://tests/fixtures/startup-retry-v15.json"),model.last_error)
   startup_notice="Saved café loaded. You can continue playing."
  else:MinimalStart.apply(model)
  if startup_kind=="recovery":
   save_recovery_blocked=true;paused=true;startup_notice="Synthetic startup recovery details"
 func _save():save_calls+=1;return true
var game
var checks=0
var failures=[]
var observations={}
var capture_dir=""
func _initialize():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--capture-dir="):capture_dir=arg.trim_prefix("--capture-dir=")
 call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func refresh():game._process(.02);game._update_ui()
func snapshot():return JSON.stringify([game.model.items,game.model.customers,game.model.coins,game.model.served,game.model.total_earned])
func verify(label:String):NoBottom.verify(game,check,label)
func settle():
 game._update_ui()
 await process_frame;await process_frame
func capture(label:String):
 if capture_dir=="":return
 await settle();await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png(capture_dir.path_join(label+".png"))==OK,"capture "+label)
func dispose():
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame
func start(kind:String):
 game=TestMain.new();game.startup_kind=kind;root.add_child(game)
 game.set_process(false);game.illustration.set_process(false);game.paused=true
 await settle()
 verify(kind+" startup")
func run():
 root.size=Vector2i(1360,880)
 await start("fresh")
 check(game.fresh_start and not game.compact_ui.has_open_popup(),"fresh launch has no notification popup")
 await capture("01-fresh-start")
 var m=game.model;var checkout=game.Checkout;var register=m.checkout_register();var front=m.workface_cell(register);var slot=checkout._optional_wait(m,register)
 check(not register.is_empty() and slot!=checkout.NONE,"synthetic café has a register and waiting slot")
 check(m.layout_access_issues().is_empty(),"fresh café has structurally clear workfaces")
 m._spawn_customer();check(not m.customers.is_empty(),"synthetic customer template spawns")
 var first=m.customers[0];var next=first.duplicate(true);next.id=int(first.id)+1;m.customers.assign([first,next])
 first.phase="paying";first.paid=false;first.seated=false;first.checkout_ticket=1;first.checkout_register_id=int(register.id);first.checkout_cell=front;first.checkout_reason="";first.route=[];first.x=front.x+.5;first.z=front.y+.5
 next.phase="checkout_wait";next.paid=false;next.seated=false;next.checkout_ticket=2;next.checkout_register_id=int(register.id);next.checkout_cell=slot;next.checkout_reason="";next.route=[];next.x=slot.x+.5;next.z=slot.y+.5
 checkout.advance(m,.05)
 check(next.checkout_reason=="Waiting in line","real queue produces ordinary waiting-in-line state")
 var before=snapshot()
 for frame in 12:refresh()
 check(snapshot()==before,"UI ticks never change queue, furniture or money")
 verify("live queue wait")
 for reason in ["Waiting for a safe place at the register","Waiting seated for the register","Waiting for the cashier","Waiting in line","Waiting for queue space"]:
  next.checkout_reason=reason;refresh()
  check(not game.compact_ui.has_open_popup(),"routine queue wait opens no popup: "+reason)
  verify(reason)
 first.paid=true;first.phase="leaving";first.departure_blocked=false;checkout.advance(m,.05)
 check(next.checkout_reason=="Register front blocked","live front claim retains the original internal checkout reason")
 check(m.layout_access_issues().is_empty(),"temporary queue wait does not change structural access")
 refresh();verify("temporary front claim")
 await capture("02-live-queue-wait")
 first.x+=1.0;checkout.advance(m,.05)
 check(next.phase=="checkout_walk" and next.checkout_reason=="","queue advances after front tile is released")
 next.x=front.x+.5;next.z=front.y+.5;next.checkout_cell=front;checkout.arrived(m,next)
 check(checkout.ready(m,next,int(register.id)),"arrived guest remains ready to pay")
 check(checkout.begin(m,int(next.id),2,int(register.id),19),"cashier starts checkout")
 var coins=m.coins;var earned=m.total_earned;var served=m.served
 check(checkout.commit(m,int(next.id),2,int(register.id),19),"payment succeeds after queue wait")
 check(m.coins==coins+m.MEAL_PAYMENT and m.total_earned==earned+m.MEAL_PAYMENT and m.served==served+1,"payment is credited exactly once")
 check(not checkout.commit(m,int(next.id),2,int(register.id),19) and m.coins==coins+m.MEAL_PAYMENT,"repeated payment cannot duplicate money")
 check(not game.compact_ui.wallet_notice.active.is_empty(),"payment retains the separate wallet notification")
 m.customers.assign([next]);next.paid=false;next.phase="checkout_wait";next.seated=false;next.checkout_cell=checkout.NONE;next.x=slot.x+.5;next.z=slot.y+.5;next.checkout_reason=""
 var blocker={"id":m._next_item_id,"kind":"plant","x":front.x,"z":front.y,"rot":0};m.items.append(blocker);m.revision+=1
 checkout.advance(m,.05);refresh()
 check(next.checkout_reason=="Register front blocked" and not m.layout_access_issues().is_empty(),"real furniture obstruction remains a model/access failure")
 verify("actual register obstruction")
 m.items.erase(blocker);m.items.erase(register);m.revision+=1;checkout.advance(m,.05);refresh()
 check(next.checkout_reason=="Add the included register in Decorate","missing-register state is preserved in checkout")
 verify("missing register")
 m.items.append(register);m.customers.clear();game.service_guests.clear();m.revision+=1
 var staff=game.staff_states[0]
 for reason in ["Waiting for a free beverage","Pass counter full · waiting for the waiter","Sink front blocked · make space in Decorate"]:
  staff.art_block_reason=reason;staff.blocked_target_id=-1;refresh()
  check(not game.compact_ui.has_open_popup(),"staff state opens no popup: "+reason)
  verify(reason)
 staff.art_block_reason=""
 game._toggle_edit();await settle()
 check(game.editing and not game.compact_ui.has_open_popup(),"entering Decorate opens no notification")
 verify("enter Decorate")
 game._choose("plant");game._rotate();game._cancel_selection();game._sell();game._upgrade();refresh()
 check(game.selected_id==-1 and game.selected_kind=="","selection, rotation, cancel and rejected actions remain callable")
 verify("action callbacks")
 m.coins=100000
 check(m.place("plant",5,6),"synthetic sale item places")
 var sale_id=int(m.items[-1].id);game._rebuild_furniture();game.selected_id=sale_id
 var sale_coins=m.coins;var sale_saves=game.save_calls
 game._sell();refresh()
 check(m.get_item(sale_id).is_empty() and m.coins>sale_coins and game.save_calls==sale_saves+1,"sell removes item, refunds and saves exactly once")
 verify("successful sale")
 await capture("03-decorate-actions")
 game._toggle_edit();await settle()
 check(not game.editing and not game.compact_ui.has_open_popup(),"leaving Decorate opens no service notice")
 for frame in 180:refresh()
 verify("after Decorate and repeated UI ticks")
 game.progress_unsaved=true;game.progress_save_error="Synthetic storage full";refresh()
 check(not game.compact_ui.has_open_popup(),"save failure creates no replacement global popup")
 verify("save failure")
 await capture("04-save-failure")
 game.compact_ui.show_help();await settle()
 check(game.compact_ui.help_panel.visible and "Synthetic storage full" in game.compact_ui.help_text.text,"existing Help exposes genuine save failure details")
 verify("existing save help")
 await capture("05-save-help")
 game.compact_ui._close_help();game.settings.show();await settle()
 verify("Settings with save failure")
 game.settings.hide();await dispose()
 await start("loaded")
 check(not game.fresh_start and game.model.coins==42000,"validated synthetic saved café loads intact")
 check(not game.compact_ui.has_open_popup(),"loaded launch has no notification popup")
 await capture("06-loaded-start")
 game._toggle_edit();game._toggle_edit();await settle();verify("loaded Decorate cycle")
 # Startup retry rebuild uses a new validated model, like the real controller.
 var restored=game.Model.new();check(restored.load_save("res://tests/fixtures/startup-retry-v15.json"),"retry model validates")
 game.model=restored;game.startup_notice="Saved café loaded. You can continue playing."
 game._resume_loaded_cafe();await settle()
 check(not game.compact_ui.has_open_popup(),"successful retry resume has no notification popup")
 verify("startup retry resume")
 await dispose()
 await start("recovery")
 check(game.compact_ui.help_panel.visible and "Synthetic startup recovery details" in game.compact_ui.help_text.text,"startup recovery still opens existing Help with diagnostic")
 game.compact_ui._close_help();game._toggle_edit();await settle()
 check(not game.editing,"recovery still prevents editing")
 verify("recovery-guarded action")
 await capture("07-startup-recovery")
 await dispose()
 print("NO_BOTTOM_NOTIFICATIONS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false,"rendered_captures":capture_dir!=""}))
 quit(0 if failures.is_empty() else 1)
