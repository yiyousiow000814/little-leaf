extends SceneTree
## Dedicated mobile layout contracts; generated café and input only, no player saves.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var checks=0
var failures=[]
var expected_save_callbacks=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func settle():
 game._update_ui()
 for frame in 6:await process_frame
func click(button:Control):
 var center=button.get_global_rect().get_center()
 var motion=InputEventMouseMotion.new();motion.position=center;motion.global_position=center;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=center;event.global_position=center;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
 await settle()
func check_wallet_notices(bounds:Rect2,label:String):
 var ui=game.compact_ui;var hud=ui.hud;var notice=ui.wallet_notice
 for show_notice in [ui.show_earnings,ui.show_wage_payment,ui.show_wages_due]:
  show_notice.call(50);await settle()
  for reduced in [false,true]:
   game.set_meta("hud_reduce_motion",reduced)
   for elapsed in [0.0,.16]:
    notice.elapsed=elapsed;notice.sync_position()
    var rect=notice.panel.get_global_rect();var phase=label+" "+notice.text.text+" reduced=%s elapsed=%s"%[reduced,elapsed]
    check(bounds.encloses(rect),phase+" notice inside safe bounds")
    for control in [game.pause_button,game.business_button,game.edit_button,ui.staff_access,ui.settings_button]:
     check(not rect.intersects(control.get_global_rect()),phase+" notice clears "+control.accessibility_name)
    if not hud.layout_host.get_meta("unified_wrapped",false):
     var lift=0.0 if reduced else 4.0*(1.0-clampf(elapsed/.16,0.0,1.0))
     check(is_equal_approx(rect.position.y,hud.wallet.get_global_rect().end.y+6+lift),phase+" one-row wallet anchor unchanged")
  notice.tick(notice.HOLD)
  check(notice.active.is_empty() and not notice.panel.visible,label+" notice expires normally")
 game.remove_meta("hud_reduce_motion")
func run():
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true;await process_frame
 var ui=game.compact_ui;var hud=ui.hud
 for view in [Vector2i(344,680),Vector2i(390,844),Vector2i(549,700),Vector2i(550,700),Vector2i(566,360),Vector2i(640,480),Vector2i(699,600),Vector2i(700,600),Vector2i(844,390),Vector2i(960,540),Vector2i(1360,880)]:
  root.size=view
  for inset in [Vector4.ZERO,Vector4(8,20,8,16)]:
   game.set_meta("hud_safe_insets",inset);ui._hide_popups();game.settings.hide();game.editing=false;await settle()
   var label="%s %s"%[str(view),str(inset)];var bounds=Rect2(inset.x,inset.y,view.x-inset.x-inset.z,view.y-inset.y-inset.w)
   if ui.viewport_too_small:continue
   var mobile=bool(hud.layout_host.get_meta("mobile_layout"))
   if mobile:
    check(not hud.rail_art.visible,label+" no oversized phone rail")
    check(hud.layout_host.size.y<=92,label+" phone toolbar height")
    check(game.top_text.get_theme_font_size("font_size")==18,label+" readable phone amount")
    check(hud.mobile_coin.visible and not hud.wallet_art.visible,label+" dedicated coin status")
   else:
    check(hud.rail_art.visible and hud.wallet_art.visible,label+" desktop painted rail restored")
    check(not hud.mobile_coin.visible,label+" desktop coin restored")
   for editing in [false,true]:
    game.editing=editing;await settle()
    var controls=[hud.wallet,game.business_button,game.pause_button,game.edit_button,ui.staff_access,ui.settings_button]
    if editing:controls.append(hud.edit_cancel)
    for i in controls.size():
     check(controls[i].size.x>=43.9 and controls[i].size.y>=43.9,label+" 44px "+controls[i].accessibility_name)
     check(bounds.encloses(controls[i].get_global_rect()),label+" safe bounds "+controls[i].accessibility_name)
     for j in range(i+1,controls.size()):check(not controls[i].get_global_rect().intersects(controls[j].get_global_rect()),label+" separate targets %d/%d"%[i,j])
   game.editing=false;await settle()
   await check_wallet_notices(bounds,label)
   ui.show_wage_payment(50);await settle()
   var paused=game.paused;await click(game.pause_button);check(paused!=game.paused,label+" pause works")
   ui.wallet_notice.tick(ui.wallet_notice.HOLD)
   await click(game.edit_button);check(game.editing,label+" decorate opens")
   game.selected_kind="plant";await settle();await click(hud.edit_cancel);check(game.selected_kind=="",label+" cancel works")
   await click(game.edit_button);expected_save_callbacks+=1;check(not game.editing,label+" done works")
   await click(ui.staff_access);check(ui.staff_panel.panel.visible,label+" staff opens");ui._hide_popups();await settle()
   await click(ui.settings_button);check(game.settings.visible,label+" settings opens");game.settings.hide();await settle()
   var open=game.model.operating_open;await click(game.business_button);expected_save_callbacks+=1;check(game.model.operating_open!=open,label+" open status keeps its action")
   if view==Vector2i(844,390) and inset==Vector4.ZERO:
    var was_paused=game.paused;var point=game.pause_button.get_global_rect().get_center()
    var press=InputEventMouseButton.new();press.position=point;press.global_position=point;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;root.push_input(press,true)
    await create_timer(.55).timeout
    check(hud.action_help.panel.visible,label+" wide phone landscape long press reveals label")
    var release=InputEventMouseButton.new();release.position=point;release.global_position=point;release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;root.push_input(release,true);await settle()
    check(game.paused==was_paused,label+" long press does not trigger pause")
    hud.action_help.hide()
 # An active notice follows wrap changes; Settings defers the same queued events.
 var notice=ui.wallet_notice
 ui.show_wage_payment(50);ui.show_earnings(20);ui.show_wages_due(10)
 for view in [Vector2i(390,844),Vector2i(566,700),Vector2i(390,844)]:
  root.size=view;await settle();notice.sync_position()
  check(not notice.panel.get_global_rect().intersects(game.pause_button.get_global_rect()),str(view)+" active notice follows resize")
 game.settings.show();var remaining=notice.remaining;notice.tick(1.0)
 check(not notice.panel.visible and notice.remaining==remaining and notice.pending.size()==2,"Settings defers visible notice and preserves queue")
 game.settings.hide();notice.tick(0.0);check(notice.panel.visible,"notice returns after Settings closes")
 for kind in ["wages","earned","due"]:
  check(notice.active.kind==kind,"wallet queue preserves "+kind);notice.tick(notice.HOLD)
 check(notice.active.is_empty() and not notice.panel.visible,"queued notices expire normally")
 check(game.saves==expected_save_callbacks,"only Done and service toggle invoke zero-I/O save callbacks")
 check(game.save_writes_suppressed,"player persistence remains disabled in synthetic harness")
 print("MOBILE_TOOLBAR_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"save_callbacks":game.saves,"expected_save_callbacks":expected_save_callbacks}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
