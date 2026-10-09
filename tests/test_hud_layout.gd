extends SceneTree
## Run with Godot 4.6.3 --headless --path . --script tests/test_hud_layout.gd -- --fresh-review --visual-qa
## The same script runs native pointer dispatch when a display is available.
var game
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func settle():
 game._update_ui()
 for index in range(4):await process_frame
func click(button:Control):
 var center=button.get_global_rect().get_center()
 var motion=InputEventMouseMotion.new();motion.position=center;motion.global_position=center;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=center;event.global_position=center;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
 await settle()
func painted_rect(art:TextureRect)->Rect2:
 var source=art.texture.get_size()
 var fitted=source*minf(art.size.x/source.x,art.size.y/source.y)
 return Rect2(art.global_position+(art.size-fitted)*.5,fitted)
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game)
 await process_frame
 game.set_process(false);game.paused=true
 var ui=game.compact_ui;var hud=ui.hud
 var desktop_wallet=Vector2.ZERO
 for view in [Vector2i(1360,880),Vector2i(960,540),Vector2i(850,600),Vector2i(800,600),Vector2i(640,480),Vector2i(606,500),Vector2i(566,360),Vector2i(390,844)]:
  root.size=view
  for editing in [false,true]:
   game.editing=editing;game.settings.hide();ui._hide_popups();await settle()
   var label="%s %s"%[str(view),"edit" if editing else "play"]
   var buttons=[game.business_button,game.pause_button,game.edit_button,ui.staff_access,ui.settings_button]
   if editing:buttons.append(hud.edit_cancel)
   for button in buttons:
    var rect=button.get_global_rect()
    check(rect.size.x>=43.9 and rect.size.y>=43.9,label+" minimum target "+button.accessibility_name)
    check(Rect2(Vector2.ZERO,Vector2(view)).encloses(rect),label+" viewport contains "+button.accessibility_name)
   for a in range(buttons.size()):
    for b in range(a+1,buttons.size()):check(not buttons[a].get_global_rect().intersects(buttons[b].get_global_rect()),label+" distinct targets %d/%d"%[a,b])
   if not hud.layout_host.get_meta("mobile_layout",false):
    var source=hud.rail_art.art.get_size();var cap=minf(hud.rail_art.size.x*.22,hud.rail_art.size.y*1.2)
    var wood_right=hud.rail_art.get_global_rect().end.x-hud.RAIL_WOOD_RIGHT_INSET*cap/(source.y*1.2)
    check(ui.settings_button.get_global_rect().end.x<=wood_right,label+" settings target inside painted rail")
    var staff=painted_rect(hud.action_art.staff)
    var gear=painted_rect(hud.action_art.settings)
    var expected_gap=18.0 if view.x>=850 else 8.0
    check(absf(gear.position.x-staff.end.x-expected_gap)<.1,label+" equal painted staff/settings gap")
    check(absf(staff.get_center().y-gear.get_center().y)<.1,label+" staff/settings optical centerline")
    check(wood_right-gear.end.x>=9,label+" visible gear outer inset")
    if not editing:
     var decorate=painted_rect(hud.action_art.decorate)
     check(absf(staff.position.x-decorate.end.x-expected_gap)<.1,label+" equal painted decorate/staff gap")
     check(absf(decorate.get_center().y-staff.get_center().y)<.1,label+" decorate optical centerline")
    else:
     check(absf(staff.position.x-hud.edit_cancel.get_global_rect().end.x-expected_gap)<.1,label+" cancel/staff painted gap")
     check(hud.edit_cancel.position.x-game.edit_button.get_rect().end.x>=4,label+" visible done/cancel separation")
   else:
    check(not hud.rail_art.visible,label+" mobile uses separated painted controls")
    check(hud.layout_host.size.y<=92,label+" mobile leaves world visible")
   check(game.pause_button.size.x==44,label+" play target does not inflate with viewport height")
   if view.x==1360:desktop_wallet=hud.wallet.size
   if view.x==960:check(hud.wallet.size.x<desktop_wallet.x,label+" short embedded toolbar reduces decorative wallet area")
   if view.x>=800:check(hud.wallet.size.x/game.pause_button.size.x>=4.3,label+" wallet remains prominent beside44px play target")
  game.editing=false;game.settings.hide();await settle()
  var old_pause=game.paused;await click(game.pause_button);check(game.paused!=old_pause,str(view)+" pointer toggles pause")
  await click(game.edit_button);check(game.editing,str(view)+" pointer enters decorate")
  game.selected_kind="plant";await settle();await click(hud.edit_cancel);check(game.selected_kind=="",str(view)+" pointer cancels selection")
  await click(game.edit_button);check(not game.editing,str(view)+" pointer finishes decorate")
  await click(ui.staff_access);check(ui.staff_panel.panel.visible,str(view)+" pointer opens staff")
  ui._hide_popups();await settle()
  await click(ui.settings_button);check(game.settings.visible,str(view)+" pointer opens settings")
  check(Rect2(Vector2.ZERO,Vector2(view)).encloses(game.settings.get_global_rect()),str(view)+" settings popup inside viewport")
  if not game.settings.get_global_rect().intersects(ui.settings_button.get_global_rect()):
   await click(ui.settings_button);check(not game.settings.visible,str(view)+" repeated settings click dismisses")
  else:
   var escape=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;root.push_input(escape,true);await settle()
   check(not game.settings.visible,str(view)+" short viewport settings dismisses with Escape")
  ui.cancel_modal_pointer()
 # Repeated height-only resize must select the same compact/full proportions.
 for height in [540,880,540,880]:
  root.size=Vector2i(960,height);await settle()
  check(hud.wallet.size.x<desktop_wallet.x if height<600 else hud.wallet.size.is_equal_approx(desktop_wallet),"repeated height resize restores the matching wallet hierarchy")
 print("HUD_LAYOUT_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
