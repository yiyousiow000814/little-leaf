extends SceneTree
## Synthetic queue + real UI loop. Never reads or writes a player's save.
class TestMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():return true
var game
var checks=0
var failures=[]
var baseline=false
var observations={}
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func paint_status():
 game.toast_lifetime=0.0;game._process(.02);game.compact_ui.status_notice.sync_position()
func snapshot():return JSON.stringify([game.model.items,game.model.customers,game.model.coins,game.model.served,game.model.total_earned])
func run():
 baseline="--expect-baseline" in OS.get_cmdline_user_args()
 root.size=Vector2i(960,640);game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await process_frame
 var m=game.model;var checkout=game.Checkout;var register=m.checkout_register();var front=m.workface_cell(register);var slot=checkout._optional_wait(m,register)
 check(not register.is_empty() and slot!=checkout.NONE,"synthetic café has a register and waiting slot")
 check(m.layout_access_issues().is_empty(),"synthetic layout has no blocked workfaces")
 m._spawn_customer();check(not m.customers.is_empty(),"synthetic customer template spawns")
 var first=m.customers[0];var next=first.duplicate(true);next.id=int(first.id)+1;m.customers.assign([first,next])
 first.phase="paying";first.paid=false;first.seated=false;first.checkout_ticket=1;first.checkout_register_id=int(register.id);first.checkout_cell=front;first.checkout_reason="";first.route=[];first.x=front.x+.5;first.z=front.y+.5
 next.phase="checkout_wait";next.paid=false;next.seated=false;next.checkout_ticket=2;next.checkout_register_id=int(register.id);next.checkout_cell=slot;next.checkout_reason="";next.route=[];next.x=slot.x+.5;next.z=slot.y+.5
 checkout.advance(m,.05)
 check(next.checkout_reason=="Waiting in line","real queue routine produces waiting-in-line state")
 observations["line_reason"]=next.checkout_reason
 var before=snapshot();paint_status()
 observations["line_notice"]=game.status_text.text if game.status_text.visible else ""
 check(game.status_text.visible==baseline,"ordinary queue status stays out of global notice")
 for frame in range(12):paint_status()
 check(game.status_text.visible==baseline,"repeated process/UI ticks do not replay ordinary queue state")
 check(snapshot()==before,"status rendering never changes queue, furniture or money")
 for reason in ["Waiting for a safe place at the register","Waiting seated for the register","Waiting for the cashier","Waiting in line","Waiting for queue space"]:
  next.checkout_reason=reason;paint_status()
  check(game.status_text.visible==baseline,"routine queue state stays quiet: "+reason)
 # The previous payer still owns the front tile until walking 0.8 tiles away.
 first.paid=true;first.phase="leaving";first.departure_blocked=false
 checkout.advance(m,.05)
 observations["claimed_front_reason"]=next.checkout_reason
 check(next.checkout_reason==("Register front blocked" if baseline else "Waiting for queue space"),"occupied queue destination is temporary waiting, not an access failure")
 check(m.layout_access_issues().is_empty(),"claimed destination still has structurally clear access")
 paint_status();observations["claimed_front_notice"]=game.status_text.text if game.status_text.visible else ""
 check(game.status_text.visible==baseline,"temporary front claim does not become a persistent Front blocked notice")
 check(not baseline or game.status_text.text=="Front blocked","baseline reproduces exact screenshot wording")
 # Once the previous payer leaves, the same queue advances normally.
 first.x+=1.0;checkout.advance(m,.05)
 check(next.phase=="checkout_walk" and next.checkout_reason=="","queue progresses after destination is released")
 next.x=front.x+.5;next.z=front.y+.5;next.checkout_cell=front;checkout.arrived(m,next)
 check(checkout.ready(m,next,int(register.id)),"arrived guest remains ready for payment")
 check(checkout.begin(m,int(next.id),2,int(register.id),19),"cashier begins the unchanged checkout flow")
 var coins=m.coins;var earned=m.total_earned;var served=m.served
 check(checkout.commit(m,int(next.id),2,int(register.id),19),"payment completes after the queue wait")
 check(m.coins==coins+m.MEAL_PAYMENT and m.total_earned==earned+m.MEAL_PAYMENT and m.served==served+1,"payment is credited exactly once")
 check(not checkout.commit(m,int(next.id),2,int(register.id),19) and m.coins==coins+m.MEAL_PAYMENT,"repeated payment cannot duplicate money")
 # Real missing/blocked register conditions must remain actionable.
 m.customers.assign([next]);next.paid=false;next.phase="checkout_wait";next.seated=false;next.checkout_cell=checkout.NONE;next.x=slot.x+.5;next.z=slot.y+.5;next.checkout_reason=""
 var blocker={"id":m._next_item_id,"kind":"plant","x":front.x,"z":front.y,"rot":0};m.items.append(blocker);m.revision+=1
 checkout.advance(m,.05);paint_status()
 check(next.checkout_reason=="Register front blocked" and game.status_text.visible,"real furniture obstruction is still reported")
 m.items.erase(blocker);m.items.erase(register);m.revision+=1;checkout.advance(m,.05);paint_status()
 check(game.status_text.visible and game._service_warning()=="Add the included register in Decorate","missing register warning is preserved")
 m.items.append(register);next.checkout_reason="Waiting for a clear chair exit";paint_status()
 check(game.status_text.visible and game._service_warning()=="Waiting for a clear chair exit","failed static chair-egress routing is still reported")
 m.customers.clear();game.service_guests.clear();m.revision+=1
 var staff=game.staff_states[0]
 for reason in ["Waiting for a free beverage","Pass counter full · waiting for the waiter"]:
  staff.art_block_reason=reason;staff.blocked_target_id=-1;paint_status()
  check(game.status_text.visible==baseline,"ordinary staff resource wait stays quiet: "+reason)
 staff.art_block_reason="Sink front blocked · make space in Decorate";staff.blocked_target_id=-1;paint_status()
 check(game.status_text.visible,"real staff access warning is preserved")
 staff.art_block_reason="";game._notify("Item sold");game._process(.02);game.compact_ui.status_notice.sync_position()
 check(game.status_text.visible and game.status_text.text=="Item sold","explicit action feedback still appears")
 game._process(3.1);game.compact_ui.status_notice.sync_position();check(not game.status_text.visible,"action toast expires without routine state replacing it")
 game.progress_unsaved=true;game.progress_save_error="Synthetic storage full";game.compact_ui.status_notice.sync_position()
 check(game.compact_ui.status_notice.issue_label.visible and game.compact_ui.status_notice.panel.visible,"unsaved-progress warning keeps priority")
 print("SERVICE_STATUS_NOISE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"baseline":baseline,"observations":observations,"player_save_used":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
