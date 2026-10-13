extends SceneTree
## Production controls, generated restaurant and disposable preferences only.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
class CloudApi extends RefCounted:
 var reloads=0
 var sign_outs=0
 func snapshot():return JSON.stringify({"status":"Not saved","canSave":true,"reload":true,"reason":"Synthetic account controls only.\nNo account is connected.\nNo network is used.\nNo player progress is loaded.\nActions are counted stubs."})
 func reload():reloads+=1
 func signOut():sign_outs+=1
var game
var checks=0
var failures=[]
var drag_records=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func settle():
 game._update_ui()
 for frame in 8:await process_frame
func click(button:Control):
 for record in game.compact_ui.themed_popups:
  if record.scroll.is_ancestor_of(button):record.scroll.ensure_control_visible(button)
 await settle()
 var point=button.get_global_rect().get_center()
 var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
  await process_frame
 await settle()
func escape():
 for pressed in [true,false]:
  var event=InputEventKey.new();event.keycode=KEY_ESCAPE;event.pressed=pressed;root.push_input(event,true)
 await settle()
func touch(button:Control):
 var point=button.get_global_rect().get_center()
 for pressed in [true,false]:
  var event=InputEventScreenTouch.new();event.position=point;event.index=0;event.pressed=pressed;Input.parse_input_event(event);Input.flush_buffered_events()
  await process_frame
 await settle()
func check_close(panel:Control,button:Button,label:String):
 var bounds=panel.get_global_rect();var close=button.get_global_rect()
 check(bounds.encloses(close) and close.position.y<bounds.position.y+80 and close.end.x>bounds.end.x-80,label+" X stays inside upper-right corner")
 check(close.size.x>=44 and close.size.y>=44 and button.accessibility_name=="Close "+label,label+" accessible close target")
func settings_scroll()->ScrollContainer:
 for record in game.compact_ui.themed_popups:
  if record.panel==game.settings:return record.scroll
 return null
func touch_drag(button:BaseButton):
 var scroll=settings_scroll();scroll.ensure_control_visible(button);await settle()
 var middle=scroll.get_global_rect().get_center().y
 scroll.scroll_vertical+=roundi(button.get_global_rect().get_center().y-middle);await settle()
 var point=button.get_global_rect().get_center();var start_scroll=scroll.scroll_vertical
 var direction=1.0 if start_scroll>12 else -1.0
 var press=InputEventScreenTouch.new();press.position=point;press.index=0;press.pressed=true
 Input.parse_input_event(press);Input.flush_buffered_events();await process_frame
 for step in 4:
  var previous=point;point+=Vector2(0,direction*16)
  var drag=InputEventScreenDrag.new();drag.index=0;drag.position=point;drag.relative=point-previous
  Input.parse_input_event(drag);Input.flush_buffered_events();await process_frame
 # Let native drag velocity settle before releasing, without custom input logic.
 for frame in 16:await process_frame
 var release=InputEventScreenTouch.new();release.position=point;release.index=0;release.pressed=false
 Input.parse_input_event(release);Input.flush_buffered_events();await settle()
 drag_records.append({"button":button.text,"start_scroll":start_scroll,"end_scroll":scroll.scroll_vertical,"viewport":str(root.get_visible_rect().size)})
 return absf(scroll.scroll_vertical-start_scroll)>1
func check_settings_drag():
 var ui=game.compact_ui;var controls=game.settings_controls
 root.size=Vector2i(844,360);ui._hide_popups();game.settings.show();await settle()
 var api=CloudApi.new();var account=controls.cloud_settings.build(api)
 controls.preference_storage_note.get_parent().add_child(account);ui.hud.theme_panel_contents(account);await settle()
 var buttons=[ui.settings_inbox,controls.cloud_settings.save_button,controls.cloud_settings.reload_button,account.get_child(0).get_child(2),controls.frame_rate_choice]
 var old_emulation=Input.emulate_touch_from_mouse;Input.emulate_touch_from_mouse=true
 for button in buttons:
  ui._hide_popups();game.settings.show();await settle()
  var activations=[0];var spy=func():activations[0]+=1
  button.pressed.connect(spy)
  check(await touch_drag(button),"Button-origin touch drag scrolls Settings: "+button.text)
  check(activations[0]==0 and game.settings.visible and game.saves==0 and api.reloads==0 and api.sign_outs==0,"Drag cancels action: "+button.text)
  if button is OptionButton:check(not button.get_popup().visible,"Drag never opens frame-rate popup")
  button.pressed.disconnect(spy)
 ui._hide_popups();game.settings.show();await settle()
 var save_button=controls.cloud_settings.save_button
 settings_scroll().ensure_control_visible(save_button);await settle();await touch(save_button)
 check(game.saves==1 and game.save_writes_suppressed,"One normal Save tap reaches the counted stub exactly once")
 var toggle:Button=controls.audio_rows.SFX.toggle;settings_scroll().ensure_control_visible(toggle);await settle()
 var initial=controls.sfx_enabled;toggle.grab_focus()
 for pressed in [true,false]:
  var key=InputEventKey.new();key.keycode=KEY_SPACE;key.pressed=pressed;root.push_input(key,true);await process_frame
 await settle();check(controls.sfx_enabled!=initial,"Settings toggle retains keyboard activation on release")
 controls.set_audio_enabled("SFX",initial);toggle.disabled=true;await touch(toggle)
 check(controls.sfx_enabled==initial,"Disabled Settings toggle never activates");toggle.disabled=false
 check(api.reloads==0 and api.sign_outs==0,"Synthetic account Reload and Sign out never activated during drag")
 var close=controls.close_button.get_global_rect();settings_scroll().scroll_vertical=100000;await settle()
 check(controls.close_button.get_global_rect().is_equal_approx(close),"Settings X remains fixed after button-origin drags")
 Input.emulate_touch_from_mouse=old_emulation
 check(Input.emulate_touch_from_mouse==old_emulation,"Fixture restores touch emulation")
func run():
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true;await process_frame
 var ui=game.compact_ui;var controls=game.settings_controls
 for view in [Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390),Vector2i(566,360)]:
  root.size=view;game.settings.show();await settle()
  var body=controls.preference_storage_note.get_parent();var buttons=[]
  for node in body.get_children():
   if node is Button:buttons.append(node.text)
  check(buttons==["Inbox","Updates","Help"],"Exact Settings menu order "+str(view))
  var panel=game.settings.get_global_rect();var close=controls.close_button.get_global_rect()
  check(panel.encloses(close) and close.position.y<panel.position.y+80 and close.end.x>panel.end.x-80,"X inside upper-right corner "+str(view))
  check(close.size.x>=44 and close.size.y>=44 and controls.close_button.accessibility_name=="Close Settings","Accessible close target "+str(view))
  for record in ui.themed_popups:
   if record.panel==game.settings:record.scroll.scroll_vertical=100000
  await settle();check(controls.close_button.get_global_rect().is_equal_approx(close),"Close remains fixed while Settings scrolls "+str(view))
  await click(ui.settings_inbox);check(ui.inbox.panel.visible and not game.settings.visible,"Inbox opens "+str(view));ui._hide_popups();game.settings.show();await settle()
  await click(ui.settings_updates);check(ui.update_notes.panel.visible and not game.settings.visible and not ui.help_panel.visible,"Updates opens directly "+str(view))
  check(ui.update_notes.back_button.text=="Back to Settings","Updates return target "+str(view));await click(ui.update_notes.back_button)
  check(game.settings.visible and not ui.update_notes.panel.visible,"Updates returns to Settings "+str(view))
  await click(ui.settings_updates);check_close(ui.update_notes.panel,ui.update_notes.close_button,"Updates")
  var updates_close=ui.update_notes.close_button.get_global_rect();ui.update_notes.scroll.scroll_vertical=100000;await settle()
  check(ui.update_notes.close_button.get_global_rect().is_equal_approx(updates_close),"Updates X remains fixed while notes scroll "+str(view))
  await click(ui.update_notes.close_button)
  check(game.settings.visible and not ui.update_notes.panel.visible and root.gui_get_focus_owner()==ui.settings_updates,"Updates X returns focus to Settings entry "+str(view))
  await click(ui.settings_help);check(ui.help_panel.visible and not game.settings.visible,"Help opens "+str(view))
  check_close(ui.help_panel,ui.help_close,"Help")
  check(ui.help_scroll.size.y>=99,"Help keeps readable instructions after adding Log "+str(view))
  check(ui.help_log.get_parent()==ui.help_footer and ui.help_log.is_visible_in_tree(),"Log lives in Help "+str(view))
  await click(ui.help_log);check(ui.save_log_panel.panel.visible and not ui.help_panel.visible,"Log opens from Help "+str(view))
  await click(ui.save_log_panel.back_button);check(ui.help_panel.visible and not ui.save_log_panel.panel.visible,"Log returns to Help "+str(view))
  var help_actions=[]
  for button in ui.help_footer.get_children():
   if button is Button and button.visible:help_actions.append(button.text)
  check(help_actions==["Show whole café","Log","Back to Settings"],"Quick Help footer excludes Updates and preserves its actions "+str(view))
  var help_close=ui.help_close.get_global_rect();ui.help_scroll.scroll_vertical=100000;await settle()
  check(ui.help_close.get_global_rect().is_equal_approx(help_close),"Help X remains fixed while instructions scroll "+str(view))
  ui.help_scroll.grab_focus();var tab=InputEventKey.new();tab.keycode=KEY_TAB;tab.shift_pressed=true
  check(ui._help_tab(tab) and root.gui_get_focus_owner()==ui.help_close,"Help X is in keyboard Tab order "+str(view))
  await click(ui.help_close)
  check(game.settings.visible and not ui.help_panel.visible and root.gui_get_focus_owner()==ui.settings_help,"Help X returns focus to Settings entry "+str(view))
  await click(ui.settings_help)
  await click(ui.help_done);check(game.settings.visible and not ui.help_panel.visible,"Help returns to Settings "+str(view))
  await click(controls.close_button);check(not game.settings.visible,"X dismisses Settings "+str(view))
  game.settings.show();await settle();await escape();check(not game.settings.visible and not ui.has_open_popup(),"Escape dismisses Settings "+str(view))
  game.settings.show();await settle();await click(ui.settings_help);await click(ui.help_log);await escape();check(not ui.has_open_popup() and not game.settings.visible,"Escape dismisses nested Log "+str(view))
  check(game.saves==0 and game.save_writes_suppressed,"Navigation never saves restaurant "+str(view))
 root.size=Vector2i(390,844);ui.show_help();await settle();await touch(ui.help_close)
 check(not ui.help_panel.visible and not game.settings.visible,"Touch X dismisses standalone Help without opening Settings")
 game.settings.show();await settle();await click(ui.settings_updates);await touch(ui.update_notes.close_button)
 check(game.settings.visible and not ui.update_notes.panel.visible and root.gui_get_focus_owner()==ui.settings_updates,"Touch Updates X returns to Settings entry")
 check(game.saves==0 and game.save_writes_suppressed,"New X controls never save restaurant")
 await check_settings_drag()
 print("SETTINGS_NAVIGATION_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"button_drags":drag_records,"player_save_used":false,"counted_save_taps":game.saves}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
