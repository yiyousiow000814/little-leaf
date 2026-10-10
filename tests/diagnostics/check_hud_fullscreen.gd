extends SceneTree
## Native window-mode verification only; no browser or device claim.
class TestMain extends "res://scripts/main.gd":
 var save_requests=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():save_requests+=1;return true
var game
var checks=0
var failures=[]
var records=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func settle():
 game._update_ui();game.illustration.queue_redraw()
 await create_timer(.22).timeout
 for frame in 4:await process_frame
func click(button:Control):
 var center=button.get_global_rect().get_center()
 var motion=InputEventMouseMotion.new();motion.position=center;motion.global_position=center;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=center;event.global_position=center;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
 await settle()
func rd(control:Control):
 var r=control.get_global_rect()
 return {"x":r.position.x,"y":r.position.y,"w":r.size.x,"h":r.size.y}
func check_layout(label:String,editing:bool):
 var ui=game.compact_ui;var hud=ui.hud;var view=Vector2(root.size);var roomy=view.x>=850
 var controls=[game.pause_button,game.edit_button,ui.staff_access,ui.settings_button]
 if editing:controls.append(hud.edit_cancel)
 for c in controls:
  var r=c.get_global_rect()
  check(r.size.x>=43.9 and r.size.y>=43.9,label+" minimum hit target "+c.accessibility_name)
  check(Rect2(Vector2.ZERO,view).encloses(r),label+" on-screen target "+c.accessibility_name)
 for a in controls.size():
  for b in range(a+1,controls.size()):check(not controls[a].get_global_rect().intersects(controls[b].get_global_rect()),label+" no overlap %d/%d"%[a,b])
 var expected_staff=Vector2(241.0/320.0,1)*(48.0 if roomy else 44.0)
 var expected_gear=Vector2(1,227.0/320.0)*(56.0 if roomy else 40.0)
 check(hud.action_art.staff.size.is_equal_approx(expected_staff),label+" exact Staff dimensions")
 check(hud.action_art.settings.size.is_equal_approx(expected_gear),label+" exact Settings dimensions")
 var s=hud.action_art.staff.get_global_rect();var g=hud.action_art.settings.get_global_rect();var gap=18.0 if roomy else 8.0
 check(absf(s.get_center().y-g.get_center().y)<.1,label+" staff/settings centerline")
 check(absf(g.position.x-s.end.x-gap)<.1,label+" staff/settings gap")
 if not editing:
  var dw=48.0 if roomy else 40.0
  check(hud.action_art.decorate.size.is_equal_approx(Vector2(dw,dw*273.0/320.0)),label+" exact Decorate dimensions")
  var d=hud.action_art.decorate.get_global_rect()
  check(absf(d.get_center().y-s.get_center().y)<.1,label+" decorate/staff centerline")
  check(absf(s.position.x-d.end.x-gap)<.1,label+" decorate/staff gap")
 else:
  check(game.edit_button.size.is_equal_approx(Vector2(44,44)),label+" unchanged Done target")
  check(hud.action_art.decorate.size.is_equal_approx(Vector2(26,26)),label+" unchanged Done artwork")
 var cap=minf(hud.rail_art.size.x*.22,hud.rail_art.size.y*1.2)
 var wood_right=hud.rail_art.get_global_rect().end.x-hud.RAIL_WOOD_RIGHT_INSET*cap/(hud.rail_art.art.get_height()*1.2)
 check(ui.settings_button.get_global_rect().end.x<=wood_right,label+" target inside wooden rail")
func capture(label:String):
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image();var output=OS.get_environment("OUTPUT")+"/"+label
 image.save_png(output+".png")
 image.get_region(Rect2i(0,0,root.size.x,150 if root.size.x<566 else 116)).save_png(output+"-toolbar.png")
 var hud=game.compact_ui.hud
 records.append({"label":label,"native_mode":DisplayServer.window_get_mode(),"root_mode":root.mode,"window_size":str(DisplayServer.window_get_size()),"viewport_size":str(root.size),"screen_size":str(DisplayServer.screen_get_size()),"decorate_art":rd(hud.action_art.decorate),"staff_art":rd(hud.action_art.staff),"settings_art":rd(hud.action_art.settings),"suppressed_save_requests":game.save_requests})
func run():
 if DisplayServer.get_name()=="headless":printerr("Native display required; refusing headless fullscreen claims");quit(2);return
 seed(8246);game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true;await settle()
 var ui=game.compact_ui;var hud=ui.hud
 var sequence=[
  {"label":"01-windowed-960x540","size":Vector2i(960,540)},
  {"label":"02-fullscreen-from-wide","fullscreen":true},
  {"label":"03-restored-960x540","size":Vector2i(960,540)},
  {"label":"04-portrait-390x844","size":Vector2i(390,844)},
  {"label":"05-landscape-844x390","size":Vector2i(844,390)},
  {"label":"06-fullscreen-from-landscape","fullscreen":true},
  {"label":"07-restored-844x390","size":Vector2i(844,390)},
  {"label":"08-windowed-tall-960x880","size":Vector2i(960,880)},
  {"label":"09-fullscreen-from-tall","fullscreen":true},
  {"label":"10-restored-960x540","size":Vector2i(960,540)}]
 for entry in sequence:
  var full=entry.get("fullscreen",false)
  root.mode=Window.MODE_FULLSCREEN if full else Window.MODE_WINDOWED
  await create_timer(.35).timeout
  if not full:root.size=entry.size
  await settle()
  var expected_mode=DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED
  check(DisplayServer.window_get_mode()==expected_mode,entry.label+" real native mode")
  check(root.size==DisplayServer.window_get_size(),entry.label+" viewport tracks native size")
  check(root.size==DisplayServer.screen_get_size() if full else root.size==entry.size,entry.label+" requested dimensions applied")
  for editing in [false,true]:
   game.editing=editing;game.settings.hide();ui._hide_popups();await settle()
   var label=entry.label+("-edit" if editing else "-play")
   check_layout(label,editing);await capture(label)
  game.editing=false;game.settings.hide();await settle()
  var paused=game.paused;await click(game.pause_button);check(game.paused!=paused,entry.label+" pointer pause")
  await click(game.edit_button);check(game.editing,entry.label+" pointer Decorate")
  game.selected_kind="plant";await settle();await click(hud.edit_cancel);check(game.selected_kind=="",entry.label+" pointer Cancel")
  await click(game.edit_button);check(not game.editing,entry.label+" pointer Done")
  await click(ui.staff_access);check(ui.staff_panel.panel.visible,entry.label+" pointer Staff")
  check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(ui.staff_panel.panel.get_global_rect()),entry.label+" Staff panel on-screen")
  ui._hide_popups();await settle()
  await click(ui.settings_button);check(game.settings.visible,entry.label+" pointer Settings")
  check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(game.settings.get_global_rect()),entry.label+" Settings panel on-screen")
  var escape=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;root.push_input(escape,true);await settle()
  check(not game.settings.visible,entry.label+" Escape dismisses Settings");ui.cancel_modal_pointer()
 check(game.save_writes_suppressed,"save writing remains suppressed")
 check(not FileAccess.file_exists(game.RECENT_SAVE_FILE),"no isolated game save written")
 root.mode=Window.MODE_WINDOWED;root.size=Vector2i(960,540)
 var result={"checks":checks,"failures":failures,"records":records,"limits":["Native Linux fullscreen only; not browser Fullscreen API","Portrait/landscape desktop windows only; not physical mobile","Pointer events dispatched through native Godot input"]}
 FileAccess.open(OS.get_environment("OUTPUT")+"/native-fullscreen-results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("NATIVE_FULLSCREEN_RESULT ",JSON.stringify(result))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
