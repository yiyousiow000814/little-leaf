extends SceneTree
## Actual GUI input and ordinary service ticks, entirely generated profiles.
const Main=preload("res://scripts/main.gd")
const State=preload("res://scripts/cafe_tutorial_state.gd")
const Model=preload("res://scripts/cafe_model.gd")
class LoadedMain extends "res://scripts/main.gd":
 static var fixture="user://synthetic-tutorial.json"
 func _load_startup():
  save_writes_suppressed=true
  if not model.load_save(fixture):push_error(model.last_error)
var game
var checks=0
var failures=[]
var phases=[]
var times={}
var captures=[]
var layouts=[]
var web_layout={"viewport":[1360,880],"stages":{},"meal_payment":Model.MEAL_PAYMENT}
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func settle():
 game._update_ui();game.illustration.update_projection();game.illustration.queue_redraw();game.tutorial.sync()
 for frame in 6:await process_frame
 game.tutorial.sync()
func click(button:Control,touch=false):
 var center=button.get_global_rect().get_center()
 var motion=InputEventMouseMotion.new();motion.position=center;motion.global_position=center;root.push_input(motion,true)
 for pressed in [true,false]:
  if touch:
   var event=InputEventScreenTouch.new();event.position=center;event.index=0;event.pressed=pressed;Input.parse_input_event(event);Input.flush_buffered_events()
  else:
   var event=InputEventMouseButton.new();event.position=center;event.global_position=center;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
  await process_frame
 await settle()
func mouse_button(point:Vector2,pressed:bool):
 var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
 await process_frame
func mouse_move(point:Vector2,held:bool):
 var event=InputEventMouseMotion.new();event.position=point;event.global_position=point;event.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0;root.push_input(event,true)
 await process_frame
func touch_at(point:Vector2,pressed:bool):
 var event=InputEventScreenTouch.new();event.position=point;event.index=0;event.pressed=pressed;Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
func check_card_releases():
 var pan=game.illustration.pan_offset
 var world=Vector2(root.size.x*.5,300);var card=game.tutorial.copy.get_global_rect().get_center()
 await mouse_move(world,false);await mouse_button(world,true);await mouse_move(world+Vector2(32,8),true)
 check(game.interaction._left_down,"world pan captures actual mouse press")
 await mouse_button(card,false)
 check(not game.interaction._left_down and not game.interaction._middle_down and not game.interaction.drag_active,"release over tutorial cancels world pan immediately")
 await touch_at(world,true)
 check(game.camera_gestures.touches.has(0),"ordinary touch is tracked before guide overlap")
 var drag=InputEventScreenDrag.new();drag.index=0;drag.position=card;drag.relative=card-world;Input.parse_input_event(drag);Input.flush_buffered_events();await process_frame
 await touch_at(card,false)
 check(game.camera_gestures.touches.is_empty() and game.camera_gestures.world_touches.is_empty() and not game.camera_gestures.pinching and not game.interaction._left_down,"release over tutorial clears touch ownership without another motion")
 game.illustration.pan_offset=pan;game.illustration.update_projection();game.interaction.pan_offset=game.illustration.pan_offset;await settle()
func check_drag_release():
 root.size=Vector2i(1360,880);await settle()
 var before=game.model.items.duplicate(true);var coins=game.model.coins
 var item=game.model.items.filter(func(value):return value.kind=="table")[0]
 var point=game.illustration.iso(float(item.x)+.5,float(item.z)+.5)-Vector2(0,20*game.illustration.ui_scale*game.illustration.zoom)
 await mouse_move(point,false);await mouse_button(point,true);await mouse_move(point+Vector2(24,0),true)
 check(game.interaction.drag_active,"actual furniture drag starts outside guide")
 await mouse_button(game.tutorial.copy.get_global_rect().get_center(),false)
 check(not game.interaction.drag_active and not game.interaction._left_down and game.model.items==before and game.model.coins==coins,"furniture released over guide cancels without move or charge")
 var key=InputEventKey.new();key.keycode=KEY_ESCAPE;key.pressed=true;root.push_input(key,true);await settle()
func capture(name:String):
 var path=OS.get_environment("LL_TUTORIAL_CAPTURE")
 if path=="" or DisplayServer.get_name()=="headless":return
 await process_frame;await RenderingServer.frame_post_draw
 var filename=path.path_join(name+".png");root.get_texture().get_image().save_png(filename);captures.append(filename)
func snapshot():
 game.model.service_snapshot=game._service_save_snapshot()
 check(game.model.save("user://synthetic-tutorial.json"),"tutorial state saves with full real service: "+game.model.last_error)
 return JSON.parse_string(FileAccess.get_file_as_string("user://synthetic-tutorial.json"))
func reload_state(expected_status:String,expected_step:int):
 var data=snapshot();var restored=Model.new()
 check(restored.load_save("user://synthetic-tutorial.json"),"generated tutorial save reloads")
 check(restored.tutorial_state==game.model.tutorial_state,"tutorial metadata roundtrip exact")
 check(restored.tutorial_state.status==expected_status and restored.tutorial_state.step==expected_step,"interrupted step/status preserved")
 check(restored.coins==game.model.coins and restored.served==game.model.served and restored.items==game.model.items,"reload preserves economy and layout")
 return data
func close_game():
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame
func load_game(path:String):
 await close_game();LoadedMain.fixture=path;game=LoadedMain.new();root.add_child(game)
 game.set_process(false);game.illustration.set_process(false);game.tutorial.set_process(false);await settle()
func geometry(label:String):
 var guide=game.tutorial;var inset=game.compact_ui.hud._safe_insets();var bounds=Rect2(inset.x,inset.y,root.size.x-inset.x-inset.z,root.size.y-inset.y-inset.w);var panel=guide.panel.get_global_rect()
 check(bounds.encloses(panel),label+" tutorial fits viewport")
 var content=guide.content_rect()
 for control in [guide.copy,guide.progress,guide.skip_button if guide.skip_button.visible else guide.finish_button]:
  check(content.encloses(control.get_global_rect()),label+" text/action inside actual opaque padded interior")
 check(guide.copy.get_theme_font_size("font_size")>=16,label+" cue remains readable16px")
 check(panel.size.y<=95,label+" compact hint height")
 check(not panel.intersects(game.compact_ui.hud.layout_host.get_global_rect()),label+" toolbar unobscured")
 if guide.target_control!=null:
  check(not panel.intersects(guide.target_control.get_global_rect()),label+" real action target unobscured")
  check(guide.target_rect.encloses(guide.target_control.get_global_rect()),label+" highlight tracks actual control")
 layouts.append({"label":label,"panel":str(panel),"target":str(guide.target_rect),"tray":str(game.compact_ui.shop_ui.browse_rect())})
 if game.editing:check(not panel.intersects(game.compact_ui.shop_ui.browse_rect()),label+" catalogue controls unobscured")
 var live_action=guide.skip_button if guide.skip_button.visible else guide.finish_button
 check(live_action.size.x>=44 and live_action.size.y>=44,label+" visible dismiss target at least44 by44")
# Coordinate-only receipt for the fresh exported-Web gate. The browser uses
# its own empty origin, ordinary clock, and real controls, never this save.
func web_geometry(name:String,action:Control=null):
 var previous_size=root.size
 root.size=Vector2i(1360,880);await settle()
 var bounds=game.tutorial.panel.get_global_rect()
 var stage={"guide":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"text":game.tutorial.copy.text,"step":game.tutorial.step()}
 if action!=null:
  var center=action.get_global_rect().get_center()
  stage["point"]=[center.x,center.y]
  check(action.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(root.size)).has_point(center),"Web "+name+" action is a visible real control")
 check(game.tutorial.panel.is_visible_in_tree(),"Web "+name+" guide is visible")
 web_layout.stages[name]=stage
 root.size=previous_size;await settle()
func run():
 check(OS.get_user_data_dir().begins_with(OS.get_environment("XDG_DATA_HOME")),"isolated generated profile")
 root.size=Vector2i(390,844)
 game=Main.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.tutorial.set_process(false)
 await settle()
 var guide=game.tutorial
 check(game.fresh_start and guide.active() and guide.step()==State.OPEN,"genuine fresh startup enrolls")
 check(not game.model.operating_open and not game.paused,"first guide explicitly waits for Open")
 check(game.model.served==0 and game.model.total_earned==0,"tutorial grants no starter payment")
 var original_items=game.model.items.duplicate(true);var initial_coins=game.model.coins
 web_layout["initial_coins"]=initial_coins
 await web_geometry("open",game.business_button)
 for view in [Vector2i(344,680),Vector2i(390,844),Vector2i(566,360),Vector2i(640,480),Vector2i(844,390),Vector2i(1360,880)]:
  root.size=view;await settle();geometry("open "+str(view));await capture("open-%dx%d"%[view.x,view.y])
 root.size=Vector2i(390,844);await settle()
 await check_card_releases()
 reload_state("active",State.OPEN)
 for frame in 20:game._process(.1);guide.sync()
 check(guide.step()==State.OPEN and game.model.customers.is_empty(),"time alone cannot advance Open")
 # Unrelated controls work; no modal input trap.
 await click(game.pause_button);check(game.paused and guide.step()==State.OPEN,"pause remains usable without advancing")
 await click(game.pause_button)
 await click(game.business_button,true)
 check(game.model.operating_open and guide.step()==State.STAFF,"real touch on Open advances")
 await web_geometry("staff",game.compact_ui.staff_access)
 await capture("02-meet-team-mobile")
 await click(game.compact_ui.staff_access,true)
 check(game.compact_ui.staff_panel.panel.visible and guide.step()==State.STAFF_DONE,"real Staff tap advances")
 await web_geometry("staff_done",game.compact_ui.staff_panel.done_button)
 for view in [Vector2i(344,680),Vector2i(390,844),Vector2i(566,360),Vector2i(844,390),Vector2i(1360,880)]:
  root.size=view;await settle();geometry("staff "+str(view));await capture("staff-%dx%d"%[view.x,view.y])
 root.size=Vector2i(390,844);await settle()
 await click(game.compact_ui.staff_panel.done_button,true)
 check(not game.compact_ui.staff_panel.panel.visible and guide.step()==State.DECORATE,"Staff Done introduces Decorate before any waiting")
 await web_geometry("decorate",game.edit_button)
 await capture("03-try-decorate-mobile")
 await click(game.edit_button,true)
 check(game.editing and guide.step()==State.DONE,"real Decorate tap advances")
 await web_geometry("return",game.edit_button)
 await check_drag_release()
 for view in [Vector2i(344,680),Vector2i(390,844),Vector2i(566,360),Vector2i(844,390),Vector2i(1360,880)]:
  root.size=view;await settle();geometry("decorate "+str(view));await capture("decorate-%dx%d"%[view.x,view.y])
 root.size=Vector2i(390,844);await settle()
 await click(game.edit_button,true)
 check(not game.editing and guide.step()==State.ORDER,"real Done exits Decorate and starts guest observation")
 await web_geometry("order")
 reload_state("active",State.ORDER)
 await load_game("user://synthetic-tutorial.json");guide=game.tutorial
 check(not game.fresh_start and guide.active() and guide.step()==State.ORDER and game.model.operating_open,"actual scene reload resumes interrupted order step")
 await click(game.pause_button)
 check(game.paused and guide.target_control==game.pause_button and guide.step()==State.ORDER,"paused interruption offers real Resume")
 await click(game.pause_button)
 await click(game.business_button)
 check(not game.model.operating_open and guide.target_control==game.business_button and guide.step()==State.ORDER,"closing admissions offers real Reopen without advancing")
 await click(game.business_button)
 await click(game.edit_button)
 check(game.editing and guide.target_control==game.edit_button,"early Decorate interruption offers real Done")
 await click(game.edit_button)
 # No spawn calls, guest phase writes, service timer rewinds or payment seeds.
 var seconds=0.0
 for frame in range(3000):
  game._process(.1);guide.sync();seconds+=.1
  if not game.model.customers.is_empty():
   if not times.has("first_guest_created"):times.first_guest_created=seconds
   var phase=str(game.model.customers[0].phase)
   if phase not in phases:
    phases.append(phase);times[phase]=seconds
    if phase in ["ordering","eating","checkout_walk","paying"]:await settle();await capture("real-"+phase+"-mobile")
  if guide.step()==State.PAYMENT and not times.has("tutorial_payment"):
   times.tutorial_payment=seconds;await settle();geometry("real order/payment "+str(root.size));await capture("03-real-order-mobile")
   var guest=game.model.customers[0];var anchor=game.illustration._render_position("guest_%s"%guest.id,Vector2(guest.x,guest.z));var feet=game.illustration.iso(anchor.x,anchor.y)
   check(guide.target_rect.get_center().y<feet.y-10 and guide.target_rect.end.y<=feet.y+10,"guest highlight follows rendered upper body instead of the floor")
  if game.model.served>0:break
  if frame%100==0:await process_frame
 await settle()
 check(game.model.served>0 and guide.step()==State.COMPLETE,"ordinary guest journey and actual checkout advance payment")
 check("ordering" in phases and "eating" in phases and "paying" in phases,"real order, meal and checkout phases witnessed")
 check(game.model.total_earned==game.model.MEAL_PAYMENT*game.model.served,"only real meal payments credited")
 check(game.model.items==original_items,"onboarding never edits or purchases furniture")
 times.first_payment=seconds;geometry("real payment completion "+str(root.size));await capture("04-first-payment-mobile")
 await web_geometry("complete",guide.finish_button)
 var balance=game.model.coins
 await click(guide.finish_button,true)
 check(not guide.active() and not guide.panel.visible and not guide.pointer.visible,"Keep playing dismisses guide fully")
 check(game.model.coins==balance,"tutorial completion has no hidden reward")
 reload_state("completed",State.COMPLETE)
 # Replay is ordinary Help UI; completed/old saves never enroll automatically.
 game.compact_ui.show_help();await settle()
 check(not guide.panel.visible and guide.help_entry.text=="Replay tutorial","Help offers replay without overlay collision")
 await click(guide.help_entry,true)
 check(guide.active() and guide.step()==State.STAFF,"replay honors already-open café")
 check(int(game.model.tutorial_state.baseline_served)==game.model.served,"replay waits for a new real payment")
 await click(guide.skip_button,true)
 check(not guide.active() and game.model.operating_open,"skip leaves normal open play")
 reload_state("skipped",State.STAFF)
 game.compact_ui.show_help();await settle();await click(guide.help_entry,true)
 check(guide.active() and guide.step()==State.STAFF,"Help resumes skipped progress")
 await click(guide.skip_button)
 # Missing or malformed optional metadata cannot damage an existing cafe.
 var saved=snapshot();saved.erase("tutorial")
 var f=FileAccess.open("user://synthetic-old-cafe.json",FileAccess.WRITE);f.store_string(JSON.stringify(saved));f.close()
 var old=Model.new();check(old.load_save("user://synthetic-old-cafe.json") and old.tutorial_state.is_empty(),"old save loads with no forced tutorial")
 saved.tutorial={"format":1,"status":"active","step":999,"baseline_served":0}
 f=FileAccess.open("user://synthetic-old-cafe.json",FileAccess.WRITE);f.store_string(JSON.stringify(saved));f.close()
 check(old.load_save("user://synthetic-old-cafe.json") and old.tutorial_state.is_empty(),"invalid optional tutorial fails open without corrupting valid café")
 check(State.read({"format":1,"status":"active","step":0.5,"baseline_served":0}).is_empty(),"fractional metadata rejected")
 # Repeated skip cannot turn an open cafe closed or pay a second reward.
 guide.skip();guide.skip();check(game.model.operating_open and game.model.coins==balance,"repeated dismissal is idempotent")
 var final_coins=game.model.coins
 await load_game("user://synthetic-tutorial.json");guide=game.tutorial
 check(not guide.active() and not guide.panel.visible and guide.help_entry.text=="Resume tutorial","actual reload keeps skipped guide dismissed")
 await load_game("user://synthetic-old-cafe.json");guide=game.tutorial
 check(not game.fresh_start and not guide.active() and game.model.operating_open,"existing player scene is not auto-enrolled or closed")
 await close_game();game=Main.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.tutorial.set_process(false);await settle();guide=game.tutorial
 check(guide.skip_button.text=="Skip & open","first-step skip discloses Open action")
 await click(guide.skip_button,true)
 check(not guide.active() and game.model.operating_open and not game.paused,"first-step Skip opens normal play explicitly")
 check(game.model.coins==initial_coins and game.model.served==0,"first-step Skip creates no customer or reward")
 var skip_seconds=0.0
 for frame in range(1000):
  game._process(.1);skip_seconds+=.1
  if not game.model.customers.is_empty() and str(game.model.customers[0].phase)=="ordering":break
  if frame%100==0:await process_frame
 check(not game.model.customers.is_empty() and str(game.model.customers[0].phase)=="ordering","Skip reaches a naturally arriving seated guest without tutorial intervention")
 times.skip_first_seated_guest=skip_seconds
 var result={"checks":checks,"failures":failures,"phases":phases,"times":times,"initial_coins":initial_coins,"final_coins":final_coins,"captures":captures,"layouts":layouts,"web_layout":web_layout,"player_save_used":false}
 var output=OS.get_environment("LL_UI_RESULT")
 if output!="":
  var result_file=FileAccess.open(output,FileAccess.WRITE);result_file.store_string(JSON.stringify(result,"\t"));result_file.close()
 print("INTERACTIVE_TUTORIAL_RESULT ",JSON.stringify(result))
 await close_game();quit(0 if failures.is_empty() else 1)
