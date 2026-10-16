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
    var lift=0.0 if reduced else 4.0*(1.0-clampf(elapsed/.16,0.0,1.0))
    check(is_equal_approx(rect.position.y,hud.wallet.get_global_rect().end.y+6+lift),phase+" notice stays directly below balance")
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
    var controls=[hud.wallet,game.business_button,game.pause_button,game.edit_button,ui.staff_access,ui.music_access,ui.settings_button]
    if editing:controls.append(hud.edit_cancel)
    check(ui.music_access.get_global_rect().encloses(hud.action_art.music.get_global_rect()),label+" Music picture stays within its native target")
    if mobile:
     check(ui.music_access.size.is_equal_approx(Vector2(44,44)),label+" Music uses the same44px cell as its neighbors")
     for name in ["music","decorate","staff","settings"]:
      var icon=hud.action_art[name];var area=icon.get_parent().get_global_rect();var painted=icon.get_global_rect()
      check(area.grow(-4.9).encloses(painted),label+" mobile artwork has internal padding "+name)
     check(game.pause_button.get_global_rect().grow(-4.9).encloses(hud.pause_art.get_global_rect()),label+" Pause glyph has internal padding")
     check(hud.wallet.get_global_rect().grow(-4.9).encloses(hud.mobile_coin.get_global_rect()),label+" wallet coin has internal padding")
     var ordered=[ui.music_access,game.edit_button]
     if editing:ordered.append(hud.edit_cancel)
     ordered.append(ui.staff_access)
     for i in range(ordered.size()-1):
      var left=ordered[i].get_global_rect();var right=ordered[i+1].get_global_rect()
      check(absf(right.position.x-left.end.x-6)<.1 and absf(left.get_center().y-right.get_center().y)<.1,label+" equal tool spacing and vertical center")
    check(not hud.action_captions.music.visible and ui.music_access.accessibility_name=="Music",label+" Music uses artwork with retained accessible name")
    check(ui.staff_access.find_next_valid_focus()==game.pause_button,label+" Tab moves from Staff to Pause")
    check(game.pause_button.find_next_valid_focus()==ui.settings_button,label+" Tab moves from Pause to Settings")
    check(ui.settings_button.find_prev_valid_focus()==game.pause_button,label+" Shift-Tab returns to Pause")
    for i in controls.size():
     check(controls[i].size.x>=43.9 and controls[i].size.y>=43.9,label+" 44px "+controls[i].accessibility_name)
     check(bounds.encloses(controls[i].get_global_rect()),label+" safe bounds "+controls[i].accessibility_name)
     for j in range(i+1,controls.size()):check(not controls[i].get_global_rect().intersects(controls[j].get_global_rect()),label+" separate targets %d/%d"%[i,j])
   game.editing=false;await settle()
   var pause=game.pause_button.get_global_rect();var settings=ui.settings_button.get_global_rect()
   check(pause.end.x<=settings.position.x and is_equal_approx(pause.get_center().y,settings.get_center().y),label+" Pause immediately left of Settings")
   for control in [game.business_button,game.edit_button,ui.staff_access]:
    check(control.get_global_rect().get_center().x<pause.get_center().x or not is_equal_approx(control.get_global_rect().get_center().y,pause.get_center().y),label+" no action between Pause and Settings")
   if mobile:check(is_equal_approx(settings.position.x-pause.end.x,6),label+" mobile Pause Settings gap")
   game.settings_controls.show_stats=true;hud._sync_stats()
   check(bounds.encloses(hud.stats_label.get_global_rect()),label+" FPS remains in safe bounds")
   for control in [game.pause_button,ui.settings_button]:
    check(not hud.stats_label.get_global_rect().intersects(control.get_global_rect()),label+" FPS clears Pause and Settings")
   game.settings_controls.show_stats=false;hud._sync_stats()
   await check_wallet_notices(bounds,label)
   ui.show_wage_payment(50);await settle()
   var paused=game.paused;await click(game.pause_button);check(paused!=game.paused,label+" pause works")
   ui.wallet_notice.tick(ui.wallet_notice.HOLD)
   var wallet=game.model.coins;var layout=game.model.items.duplicate(true);var saves_before=game.saves
   await click(game.edit_button);check(game.editing and game.model.decoration_session_active,label+" decorate opens")
   game.selected_kind="plant";await settle();await click(hud.edit_cancel)
   check(game.selected_kind=="" and not game.editing and not game.model.decoration_session_active,label+" Cancel exits the whole session and clears selection")
   check(game.model.coins==wallet and game.model.items==layout and game.saves==saves_before,label+" Cancel restores baseline without an immediate save")
   await click(game.edit_button);check(game.editing and game.model.decoration_session_active and game.saves==saves_before,label+" Decorate reopens without an immediate save")
   await click(game.edit_button);expected_save_callbacks+=1;check(not game.editing and not game.model.decoration_session_active,label+" Apply finishes the whole session")
   await click(ui.staff_access);check(ui.staff_panel.panel.visible,label+" staff opens");ui._hide_popups();await settle()
   await click(ui.settings_button);check(game.settings.visible,label+" settings opens");game.settings.hide();await settle()
   var open=game.model.operating_open;var dirty_generation=game.platform_dirty_generation;await click(game.business_button);check(game.model.operating_open!=open and game.platform_dirty_generation>dirty_generation,label+" open status keeps its action and marks progress dirty")
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
 # Long exact amounts wrap within the left-hand space instead of covering Done.
 game.set_meta("hud_safe_insets",Vector4(8,20,8,16));game.editing=true
 root.size=Vector2i(360,680);await settle()
 check(not ui.viewport_too_small,"long-notice fixture retains344px usable width")
 game.settings_controls.show_stats=true;hud._sync_stats()
 ui.show_wages_due(1000000000);notice.elapsed=.16
 for frame in 6:
  await process_frame
  check(not notice.panel.get_global_rect().intersects(hud.stats_label.get_global_rect()),"long notice clears FPS during container settling")
 await settle()
 var long_bounds=Rect2(8,20,344,644);var long_rect=notice.panel.get_global_rect()
 check(long_bounds.encloses(long_rect),"long due stays in safe bounds")
 check(notice.text.text=="Wages due 1,000,000,000" and notice.text.get_line_count()>1,"long amount remains complete and wraps")
 for control in [game.pause_button,game.edit_button,hud.edit_cancel,ui.staff_access,ui.settings_button]:
  check(not long_rect.intersects(control.get_global_rect()),"long due clears "+control.accessibility_name)
 check(is_equal_approx(long_rect.position.y,hud.wallet.get_global_rect().end.y+6),"wrapped long due stays below balance")
 root.size=Vector2i(566,700);await settle()
 check(notice.text.autowrap_mode==TextServer.AUTOWRAP_OFF and notice.text.get_line_count()==1,"long notice unwraps after resize")
 root.size=Vector2i(360,680);await settle();ui.show_wages_due(50);await settle()
 check(notice.text.autowrap_mode==TextServer.AUTOWRAP_OFF and notice.panel.size.x<160,"short coalesced amount restores compact notice")
 notice.tick(notice.HOLD);game.editing=false
 game.settings_controls.show_stats=false;hud._sync_stats()
 check(game.saves==expected_save_callbacks,"only Apply invokes an immediate zero-I/O save callback")
 check(game.save_writes_suppressed,"player persistence remains disabled in synthetic harness")
 print("MOBILE_TOOLBAR_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"save_callbacks":game.saves,"expected_save_callbacks":expected_save_callbacks}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
