extends SceneTree
const NoBottom=preload("res://tests/no_bottom_notifications.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var staff
var checks=0
var failures=[]
var records=[]
var baseline=false
var captures=OS.get_environment("OUTPUT")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():
 baseline="--baseline-staff" in OS.get_cmdline_user_args();run.call_deferred()
func rect(c:Control)->Dictionary:
 var r=c.get_global_rect();return {"x":r.position.x,"y":r.position.y,"w":r.size.x,"h":r.size.y}
func snapshot():return JSON.stringify([game.model.coins,game.model.items,game.model.duty_targets,game.model.duty_counts,game.model.payroll_accrued,game.saves])
func settle():
 game._update_ui();staff._fit()
 for i in 8:await process_frame
func click_at(point:Vector2):
 for pressed in [true,false]:
  var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;root.push_input(e,true)
 await settle()
func key(code):
 for pressed in [true,false]:
  var e=InputEventKey.new();e.keycode=code;e.pressed=pressed;root.push_input(e,true)
 await settle()
func capture(label:String):
 if captures=="":return
 await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png(captures.path_join(label+".png"))==OK,"captured "+label)
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated test profiles");quit(2);return
 root.size=Vector2i(1360,880);game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame;staff=game.compact_ui.staff_panel
 for view in [Vector2i(1360,880),Vector2i(390,844),Vector2i(344,844),Vector2i(566,360),Vector2i(844,390)]:
  root.size=view;staff.show();await settle()
  var label=str(view);var view_rect=Rect2(Vector2.ZERO,Vector2(view));var before=snapshot()
  check(staff.panel.visible,label+" Staff opens")
  check(view_rect.grow(.5).encloses(staff.panel.get_global_rect()),label+" Staff stays on screen")
  check(staff.done_button.size.x>=44 and staff.done_button.size.y>=44,label+" Done retains44px target")
  if not baseline:
   check(staff.done_button.get_parent()==staff.title.get_parent(),label+" Done is in header")
   check(not NoBottom.has_property(staff,"help_button") and not NoBottom.has_property(staff,"details") and not staff.has_method("_toggle_details"),label+" obsolete Staff help controls are removed")
   check(staff.done_button.get_global_rect().position.y<=staff.title.get_global_rect().end.y,label+" Done is top aligned")
   check(staff.scroll.get_global_rect().position.y>staff.done_button.get_global_rect().end.y,label+" scrolling role area starts below header")
   check(staff.done_button not in staff.layout_box.get_children(),label+" no bottom Done row remains")
  records.append({"viewport":str(view),"panel":rect(staff.panel),"scroll":rect(staff.scroll),"done":rect(staff.done_button),"baseline":baseline})
  staff.scroll.scroll_vertical=100000;await settle();await capture("staff-%dx%d-bottom"%[view.x,view.y])
  check(staff.scroll.get_v_scroll_bar().value>=staff.scroll.get_v_scroll_bar().max_value-staff.scroll.get_v_scroll_bar().page-1,label+" last role card reachable")
  await click_at(staff.done_button.get_global_rect().get_center());check(not staff.panel.visible,label+" pointer Done closes")
  check(snapshot()==before,label+" Done does not change roster wallet or saves")
  staff.show();await settle();staff.done_button.grab_focus();await key(KEY_ENTER);check(not staff.panel.visible,label+" keyboard Enter on Done closes")
  staff.show();await settle();await key(KEY_ESCAPE);check(not staff.panel.visible,label+" Escape closes")
  staff.show();await settle();await click_at(Vector2(2,view.y-2));check(not staff.panel.visible,label+" outside click closes")
  check(snapshot()==before,label+" all dismissals stay nonmutating")
 game.compact_ui.show_help();await settle();check(game.compact_ui.help_panel.visible,"existing general Help is retained")
 var report={"checks":checks,"failures":failures,"records":records,"player_save_used":false};print("STAFF_HEADER_DONE_RESULT ",JSON.stringify(report))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
