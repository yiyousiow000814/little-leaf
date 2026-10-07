extends SceneTree
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var rows=[]
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func signature()->String:
 return JSON.stringify({"coins":game.model.coins,"items":game.model.items,"customers":game.model.customers,"owned":game.model.owned_parcels})
func _initialize():run.call_deferred()
func key(code:int):
 var event=InputEventKey.new();event.pressed=true;event.keycode=code;root.push_input(event,true)
func drag(world:Vector2):
 var safe=game.illustration.camera_safe_rect();var start=safe.get_center()
 var limit=Vector2(maxf(8,safe.size.x*.3),maxf(8,safe.size.y*.3))
 for stroke in range(200):
  var remaining=safe.get_center()-game.illustration.iso(world.x,world.y)
  if remaining.length()<1.0:break
  var part=Vector2(clampf(remaining.x,-limit.x,limit.x),clampf(remaining.y,-limit.y,limit.y))
  var press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_MIDDLE;press.pressed=true;press.position=start;root.push_input(press,true)
  var move=InputEventMouseMotion.new();move.position=start+part;move.relative=part;move.button_mask=MOUSE_BUTTON_MASK_MIDDLE;root.push_input(move,true)
  press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_MIDDLE;press.position=start+part;root.push_input(press,true)
func touch_zoom(start:Vector2):
 for step in range(48):
  if is_equal_approx(game.illustration.zoom,game.illustration.camera_zoom_limits().y):break
  for id in range(2):
   var event=InputEventScreenTouch.new();event.index=id;event.pressed=true;event.position=start+Vector2(-18 if id==0 else 18,0);root.push_input(event,true)
  for id in range(2):
   var event=InputEventScreenDrag.new();event.index=id;event.position=start+Vector2(-22 if id==0 else 22,0);root.push_input(event,true)
  for id in range(2):
   var event=InputEventScreenTouch.new();event.index=id;event.position=start+Vector2(-22 if id==0 else 22,0);root.push_input(event,true)
func touch_pan(world:Vector2):
 var safe=game.illustration.camera_safe_rect();var start=safe.get_center()
 var limit=Vector2(maxf(8,safe.size.x*.3),maxf(8,safe.size.y*.3))
 var remaining=Vector2.ZERO
 var previous=Vector2.INF
 for stroke in range(600):
  remaining=safe.get_center()-game.illustration.iso(world.x,world.y)
  if remaining.length()<1.0 or remaining.distance_to(previous)<.1:break
  previous=remaining
  var part=Vector2(clampf(remaining.x,-limit.x,limit.x),clampf(remaining.y,-limit.y,limit.y))
  if root.size.x<650:
   part=part.limit_length(4 if is_equal_approx(game.illustration.zoom,game.illustration.camera_zoom_limits().y) else 24)
   var separation=Vector2(0,minf(safe.size.y*.25,40)) if is_equal_approx(game.illustration.zoom,game.illustration.camera_zoom_limits().y) else part.normalized()*18
   var order=([0,1] if part.y>=0 else [1,0]) if is_equal_approx(game.illustration.zoom,game.illustration.camera_zoom_limits().y) else [1,0]
   for id in range(2):
    var touch=InputEventScreenTouch.new();touch.index=id;touch.pressed=true;touch.position=start+separation*(-1 if id==0 else 1);root.push_input(touch,true)
   for id in order:
    var motion=InputEventScreenDrag.new();motion.index=id;motion.position=start+separation*(-1 if id==0 else 1)+part;motion.relative=part;root.push_input(motion,true)
   for id in range(2):
    var touch=InputEventScreenTouch.new();touch.index=id;touch.position=start+separation*(-1 if id==0 else 1)+part;root.push_input(touch,true)
  else:
   var press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_MIDDLE;press.pressed=true;press.position=start;root.push_input(press,true)
   var move=InputEventMouseMotion.new();move.position=start+part;move.relative=part;move.button_mask=MOUSE_BUTTON_MASK_MIDDLE;root.push_input(move,true)
   press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_MIDDLE;press.position=start+part;root.push_input(press,true)
func run():
 game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await process_frame
 for view in [Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390),Vector2i(344,680),Vector2i(566,360),Vector2i(960,540)]:
  root.size=view;game.set_meta("hud_safe_insets",Vector4.ZERO);game.editing=false;game.tray.hide();game.compact_ui._hide_popups();game._update_ui()
  for frame in range(6):await process_frame
  if game.compact_ui.viewport_too_small:continue
  for insets in [Vector4.ZERO,Vector4(8,20,8,16)]:
   game.set_meta("hud_safe_insets",insets);game._update_ui()
   for frame in range(6):await process_frame
   if game.compact_ui.viewport_too_small:continue
   var art=game.illustration
   key(KEY_HOME)
   var fit_bounds=art.camera_world_bounds();var fit_zoom=art.camera_fit_zoom()
   check(is_equal_approx(fit_bounds.size.x,(game.model._width_for(game.model.owned_parcels)+game.model._depth_for(game.model.owned_parcels))*39.0),"Fit remains owned cafe only")
   check(is_equal_approx(art.zoom,fit_zoom),"ordinary Home uses cafe Fit")
   var original=signature()
   for close in [false,true]:
    key(KEY_HOME)
    for tick in range(48):key(KEY_PLUS if close else KEY_MINUS)
    for landmark in [["stop",Vector2(-12,8.3)],["door",Vector2(-10.345,10.1)],["stop far corner",Vector2(-13.65,11.3)],["parking",Vector2(6,-6.5)],["parking far corner",Vector2(12,-8.7)]]:
     var safe=art.camera_safe_rect()
     drag(landmark[1])
     check(is_equal_approx(art.zoom,art.camera_zoom_limits().y if close else art.camera_zoom_limits().x),"pan preserves minimum/maximum inspection zoom")
     var at=art.iso(landmark[1].x,landmark[1].y)
     check(safe.grow(-12).has_point(at),str(view)+str(insets)+str(close)+landmark[0]+" ordinary pan reaches landmark")
     check(not game.interaction._over_ui(at),"landmark clears active UI")
     var old_origin=art.origin;var old_pan=art.pan_offset;var old_zoom=art.zoom
     game._toggle_edit()
     for frame in range(6):await process_frame
     art.update_projection()
     check(art.origin.is_equal_approx(old_origin) and art.pan_offset.is_equal_approx(old_pan) and is_equal_approx(art.zoom,old_zoom),"opening Decorate does not jump inspected landmark")
     game._toggle_edit()
     for frame in range(6):await process_frame
     art.update_projection()
     check(art.origin.is_equal_approx(old_origin) and art.pan_offset.is_equal_approx(old_pan) and is_equal_approx(art.zoom,old_zoom),"Done preserves inspected landmark")
     check(signature()==original,"camera inspection preserves model authority")
     rows.append({"viewport":str(view),"close":close,"landmark":landmark[0],"zoom":art.zoom,"scale":art.ui_scale*art.zoom,"at":str(at),"safe":str(safe),"reachable":safe.grow(-12).has_point(at),"over_ui":game.interaction._over_ui(at)})
   if view.x<650:
    for target in [Vector2(-12,8.3),Vector2(-13.65,11.3),Vector2(6,-6.5),Vector2(12,-8.7)]:
     key(KEY_HOME)
     for tick in range(48):key(KEY_MINUS)
     touch_pan(target)
     check(art.camera_safe_rect().grow(-12).has_point(art.iso(target.x,target.y)),str(view)+" two-finger pan reaches environment")
     touch_zoom(art.iso(target.x,target.y))
     check(is_equal_approx(art.zoom,art.camera_zoom_limits().y),"two-finger pinch reaches close limit")
     if not art.camera_safe_rect().grow(-12).has_point(art.iso(target.x,target.y)):touch_pan(target)
     check(art.camera_safe_rect().grow(-12).has_point(art.iso(target.x,target.y)),str(view)+str(target)+str(art.iso(target.x,target.y))+" two-finger close inspection retains environment")
     check(signature()==original,"touch inspection preserves authority")
 if not OS.get_environment("OUTPUT").is_empty():FileAccess.open(OS.get_environment("OUTPUT")+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
 print("ENVIRONMENT_CAMERA_ACCESS_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
