extends SceneTree
## Real controls and dispatched input; synthetic café only, no player saves.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var checks=0
var failures=[]
var geometry=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func settle():
 game._update_ui()
 for frame in 8:await process_frame
func key(code:int,shift=false):
 var event=InputEventKey.new();event.keycode=code;event.pressed=true;event.shift_pressed=shift;root.push_input(event,true)
 event=InputEventKey.new();event.keycode=code;event.pressed=false;root.push_input(event,true)
 await settle()
func click(point:Vector2,touch=false):
 var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;Input.parse_input_event(motion);Input.flush_buffered_events();await process_frame
 for pressed in [true,false]:
  if touch:
   var event=InputEventScreenTouch.new();event.position=point;event.index=0;event.pressed=pressed;Input.parse_input_event(event)
  else:
   var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;Input.parse_input_event(event)
  Input.flush_buffered_events();await process_frame
 await settle()
func question_buttons(node:Node)->Array:
 var found=[]
 if node is Button and node.text=="?":found.append(node)
 for child in node.get_children():found.append_array(question_buttons(child))
 return found
func run():
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame
 var ui=game.compact_ui;var hud=ui.hud
 check(ui.settings_help.text=="Help & Updates","Settings capitalizes Updates")
 check(question_buttons(game.ui).is_empty(),"removed catalogue question-mark control is not instantiated")
 check(ui.update_badges.size()==3,"only Settings, Inbox and Settings Help keep unread badges")
 var cases=[Vector2i(960,540),Vector2i(1360,880),Vector2i(390,844),Vector2i(566,360),Vector2i(640,480),Vector2i(344,680),Vector2i(369,700),Vector2i(370,700),Vector2i(565,700),Vector2i(566,700),Vector2i(849,599),Vector2i(850,599),Vector2i(960,599),Vector2i(960,600),Vector2i(606,400)]
 for view in cases:
  root.size=view
  for safe in [false,true]:
   var inset=Vector4(8,20,8,16) if safe else Vector4.ZERO
   game.set_meta("hud_safe_insets",inset);game.editing=false;game.settings.hide();ui._hide_popups();await settle()
   var label="%s safe=%s"%[str(view),str(safe)]
   if ui.viewport_too_small:
    check(ui.viewport_too_small,label+" unsupported viewport guarded");continue
   var safe_rect=Rect2(inset.x,inset.y,view.x-inset.x-inset.z,view.y-inset.y-inset.w)
   check(safe_rect.encloses(hud.layout_host.get_global_rect()),label+" toolbar inside safe bounds")
   check(hud.wallet.size.y>=43.9,label+" wallet balance touch target")
   check(hud.wallet.get_global_rect().encloses(game.top_text.get_global_rect()),label+" balance text stays inside wallet")
   for editing in [false,true]:
    game.editing=editing;await settle()
    check(question_buttons(ui.shop_ui.root).is_empty(),label+" no rightmost catalogue help control after layout")
    if editing and view.x==1360 and not safe:
     check(absf(ui.shop_ui.category_scroll.position.x-32)<.1 and absf(ui.shop_ui.category_scroll.size.x-(ui.shop_ui.root.size.x-64))<.1,label+" category strip reclaims removed help space")
    var controls=[game.business_button,game.pause_button,game.edit_button,ui.staff_access,ui.settings_button]
    if editing:controls.append(hud.edit_cancel)
    for i in controls.size():
     check(controls[i].size.x>=43.9 and controls[i].size.y>=43.9,label+" target remains44")
     check(safe_rect.encloses(controls[i].get_global_rect()),label+" control inside safe bounds "+controls[i].accessibility_name+" "+str(controls[i].get_global_rect()))
     for j in range(i+1,controls.size()):check(not controls[i].get_global_rect().intersects(controls[j].get_global_rect()),label+" targets separate %d/%d: %s / %s"%[i,j,controls[i].get_global_rect(),controls[j].get_global_rect()])
   game.editing=false;await settle()
   ui.show_help();await settle()
   var panel=ui.help_panel.get_global_rect();var footer=ui.help_footer.get_global_rect();var modal=ui.help_modal
   check(safe_rect.encloses(panel),label+" Help inside safe bounds")
   check(panel.encloses(footer),label+" fixed footer inside panel")
   check(ui.help_scroll.size.y>=99,label+" readable body viewport")
   if ui.help_modal:
    check(ui.help_scrim.visible,label+" short-screen scrim visible")
    check(hud.layout_host.mouse_behavior_recursive==Control.MOUSE_BEHAVIOR_DISABLED and hud.layout_host.focus_behavior_recursive==Control.FOCUS_BEHAVIOR_DISABLED,label+" obscured toolbar disabled")
   else:
    check(panel.position.y-hud.layout_host.get_global_rect().end.y>=8 and panel.position.y-hud.layout_host.get_global_rect().end.y<=12,label+" Help docked below toolbar")
   if not hud.layout_host.get_meta("mobile_layout",false):
    var source=hud.rail_art.art.get_size();var cap=minf(hud.rail_art.size.x*.22,hud.rail_art.size.y*1.2)
    var wood_right=hud.rail_art.get_global_rect().end.x-hud.RAIL_WOOD_RIGHT_INSET*cap/(source.y*1.2)
    check(absf(panel.end.x-hud.PANEL_WOOD_RIGHT_INSET-wood_right)<1,label+" wooden frame right edges align help=%s rail=%s"%[panel.end.x-hud.PANEL_WOOD_RIGHT_INSET,wood_right])
   else:
    check(absf(panel.end.x-(view.x-inset.z-8))<1,label+" mobile help aligns to safe right margin")
   for button in [ui.help_overview,ui.help_notes,ui.help_done,ui.help_retry]:
    check(button.get_theme_font_size("font_size")==14 and button.get_theme_font("font")==hud.font_bold,label+" Help buttons use14px Nunito800")
    check(button.custom_minimum_size.y>=44,label+" footer touch target")
   ui.help_scroll.scroll_vertical=100000;await settle()
   check(ui.help_footer.get_global_rect().is_equal_approx(footer),label+" footer stays fixed while text scrolls")
   check(ui.help_scroll.get_v_scroll_bar().value+ui.help_scroll.get_v_scroll_bar().page>=ui.help_scroll.get_v_scroll_bar().max_value-1,label+" text end reachable")
   ui.help_scroll.grab_focus()
   for step in 6:
    await key(KEY_TAB)
    check(ui.help_panel.is_ancestor_of(root.gui_get_focus_owner()),label+" keyboard focus stays in Help")
   await key(KEY_TAB,true);check(ui.help_panel.is_ancestor_of(root.gui_get_focus_owner()),label+" reverse focus stays in Help")
   await key(KEY_F1);check(ui.help_panel.visible and ui.help_scroll.scroll_vertical==0,label+" repeated open resets instructions")
   ui.help_overview.grab_focus();await key(KEY_ENTER)
   check(ui.help_panel.visible,label+" keyboard overview retains Help")
   await key(KEY_ESCAPE);check(not ui.help_panel.visible and not ui.help_scrim.visible,label+" Escape dismisses Help and scrim")
   check(hud.layout_host.mouse_behavior_recursive==Control.MOUSE_BEHAVIOR_INHERITED,label+" toolbar restored")
   game.settings.show();await settle()
   for record in ui.themed_popups:
    if record.panel==game.settings:record.scroll.ensure_control_visible(ui.settings_help)
   await settle()
   await click(ui.settings_help.get_global_rect().get_center(),safe)
   check(ui.help_done.text=="Back to Settings",label+" Settings return label")
   await click(ui.help_done.get_global_rect().get_center(),safe)
   check(game.settings.visible and not ui.help_panel.visible,label+" mouse/touch Back to Settings")
   game.settings.hide();ui.show_help();await settle()
   await click(ui.help_notes.get_global_rect().get_center())
   check(ui.update_notes.panel.visible and not ui.help_panel.visible,label+" Update Notes opens")
   ui.update_notes._back_to_help();await settle()
   check(ui.help_panel.visible and not ui.update_notes.panel.visible,label+" Update Notes returns")
   game.editing=true;game.selected_kind="plant";await settle()
   var old_coins=game.model.coins;var old_pan=game.illustration.pan_offset;var old_paused=game.paused
   await click(Vector2(inset.x+2,view.y-inset.w-2),safe)
   check(not ui.help_panel.visible,label+" outside mouse/touch dismisses")
   check(game.model.coins==old_coins and game.illustration.pan_offset==old_pan and game.paused==old_paused,label+" dismissal cannot reach world or toolbar")
   check(ui.dismissed_mouse_buttons.is_empty() and ui.dismissed_touches.is_empty(),label+" dismissal sequence released")
   game.selected_kind="";game.editing=false
   geometry.append({"view":str(view),"safe":safe,"toolbar_height":hud.layout_host.size.y,"help":str(panel),"body_height":ui.help_scroll.size.y,"modal":modal})
 # Resize an already-open panel across docking/modal and wrapping boundaries.
 game.remove_meta("hud_safe_insets")
 ui.show_help()
 for view in [Vector2i(566,360),Vector2i(960,540),Vector2i(390,844),Vector2i(960,599),Vector2i(960,600),Vector2i(566,360),Vector2i(1360,880)]:
  root.size=view;await settle()
  check(ui.help_panel.visible and Rect2(Vector2.ZERO,Vector2(view)).encloses(ui.help_panel.get_global_rect()),str(view)+" open Help survives resize")
  check(ui.help_modal==(view.y==360),str(view)+" resize restores modal state")
  check(ui.help_scrim.visible==ui.help_modal,str(view)+" resize restores backdrop")
  check((hud.layout_host.mouse_behavior_recursive==Control.MOUSE_BEHAVIOR_DISABLED)==ui.help_modal,str(view)+" resize restores toolbar input")
 await key(KEY_ESCAPE)
 check(game.saves==0,"no save writes")
 print("TOOLBAR_HELP_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"geometry":geometry}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
