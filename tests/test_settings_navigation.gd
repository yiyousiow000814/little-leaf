extends SceneTree
## Production controls, generated restaurant and disposable preferences only.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var checks=0
var failures=[]
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
  await click(ui.settings_help);check(ui.help_panel.visible and not game.settings.visible,"Help opens "+str(view))
  check(ui.help_scroll.size.y>=99,"Help keeps readable instructions after adding Log "+str(view))
  check(ui.help_log.get_parent()==ui.help_footer and ui.help_log.is_visible_in_tree(),"Log lives in Help "+str(view))
  await click(ui.help_log);check(ui.save_log_panel.panel.visible and not ui.help_panel.visible,"Log opens from Help "+str(view))
  await click(ui.save_log_panel.back_button);check(ui.help_panel.visible and not ui.save_log_panel.panel.visible,"Log returns to Help "+str(view))
  await click(ui.help_done);check(game.settings.visible and not ui.help_panel.visible,"Help returns to Settings "+str(view))
  await click(controls.close_button);check(not game.settings.visible,"X dismisses Settings "+str(view))
  game.settings.show();await settle();await escape();check(not game.settings.visible and not ui.has_open_popup(),"Escape dismisses Settings "+str(view))
  game.settings.show();await settle();await click(ui.settings_help);await click(ui.help_log);await escape();check(not ui.has_open_popup() and not game.settings.visible,"Escape dismisses nested Log "+str(view))
  check(game.saves==0 and game.save_writes_suppressed,"Navigation never saves restaurant "+str(view))
 print("SETTINGS_NAVIGATION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
