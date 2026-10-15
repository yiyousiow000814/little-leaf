extends "res://tests/building/test_existing_wall_actions.gd"
## Real visible control geometry, generated model, no original profile.
class ProjectionProbe extends Node2D:
 var pan_offset=Vector2.ZERO
 var calls=0
 func update_projection():calls+=1
class ProjectionContext extends RefCounted:
 var illustration
 var editing=false
 var selected_kind=""
 var selected_id=-1
 var hover_cell=Vector2i.ZERO
 var tool_text=null
 var floor_calls=0
 var projection_before_pick=false
 func _floor_cell(_point):
  floor_calls+=1
  projection_before_pick=illustration.calls>0
  return Vector2i(1,2)
func check_play_projection_refresh():
 var context=ProjectionContext.new();var probe=ProjectionProbe.new();context.illustration=probe
 var interaction=preload("res://scripts/gameplay/cafe_interaction.gd").new(context)
 probe.pan_offset=Vector2(25,31);var point=Vector2(42,66)
 interaction.preview_active=true;interaction.drag_valid=true;interaction.drag_footprint_valid=true
 interaction.refresh(point)
 check(probe.calls==0,"play refresh skips unused projection calculation")
 check(interaction.pan_offset==probe.pan_offset and interaction.last_pointer==point,"play refresh retains current pan and pointer")
 check(not interaction.preview_active and not interaction.drag_valid and not interaction.drag_footprint_valid,"play refresh clears all placement feedback")
 interaction._sync_projection();check(probe.calls==1,"explicit camera synchronization retains default refresh")
 probe.calls=0;context.editing=true;interaction.refresh(point)
 check(probe.calls==1 and context.floor_calls==1 and context.projection_before_pick,"editing refresh projects before world picking")
 context.editing=false;probe.calls=0;interaction._pan_by(Vector2(3,5))
 check(probe.calls==1 and interaction.pan_offset==Vector2(28,36),"actual pan path still recalculates and synchronizes")
 probe.free()
func buttons(node:Node, result:Array):
 if node is Control and not node.is_visible_in_tree():return
 if node is BaseButton and root.get_visible_rect().encloses(node.get_global_rect()):result.append(node)
 for child in node.get_children():buttons(child,result)
func mouse_button(point:Vector2, button:int, pressed:bool):
 var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=button;event.pressed=pressed
 root.push_input(event,true)
func middle_move(point:Vector2):
 var event=InputEventMouseMotion.new();event.position=point;event.global_position=point;event.button_mask=MOUSE_BUTTON_MASK_MIDDLE
 root.push_input(event,true)
func run():
 if not "saveguard" in OS.get_user_data_dir():quit(2);return
 check_play_projection_refresh()
 game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await settle()
 var art=game.illustration;var states=0;var ui_cases=0
 for view in [Vector2i(960,540),Vector2i(390,844),Vector2i(844,390)]:
  root.size=view
  for full in [false,true]:
   game.model.owned_parcels.assign(game.model.PARCEL_IDS if full else []);game.model._sync_floor_bounds()
   for editing in [false,true]:
    game.interaction.on_focus_lost()
    if game.editing!=editing:game._toggle_edit()
    game.compact_ui._hide_popups();game.compact_ui._set_tray_reveal(1 if editing else 0);await settle()
    art.zoom=clampf(1.2,art.camera_zoom_limits().x,art.camera_zoom_limits().y);art.pan_offset=Vector2.ZERO;art.update_projection()
    var before=JSON.stringify([game.model.items,game.model.coins,game.model.wall_attachments]);var saves=game.saves
    var visible=[];buttons(game.ui,visible);var points=[]
    for button in visible:
     var p=button.get_global_rect().get_center()
     if p.y<130 and points.is_empty():points.append(p)
    if editing:
     for x in [.15,.35,.65,.85]:
      var p=Vector2(view.x*x,view.y-45)
      if game.interaction._over_ui(p):points.append(p);break
    check(points.size()==(2 if editing else 1),"actual HUD/tray regions found")
    for p in points:
     check(game.interaction._over_ui(p),"visible control owns press region")
     var zoom=art.zoom;var pan=art.pan_offset
     mouse_button(p,MOUSE_BUTTON_MIDDLE,true)
     check(not game.interaction._middle_down,"UI middle press never acquires world camera")
     mouse_button(p,MOUSE_BUTTON_WHEEL_UP,true);middle_move(p+Vector2(20,10));mouse_button(p+Vector2(20,10),MOUSE_BUTTON_MIDDLE,false)
     check(is_equal_approx(art.zoom,zoom) and art.pan_offset.distance_to(pan)<.1,"UI wheel and middle motion preserve camera")
     check(not game.interaction._middle_down,"UI release leaves capture clear");ui_cases+=1
    var world=Vector2.INF;var safe=art.camera_safe_rect()
    for y in [.4,.6,.2,.8]:
     for x in [.5,.3,.7]:
      var p=safe.position+safe.size*Vector2(x,y)
      if not world.is_finite() and not game.interaction._over_ui(p):world=p
    check(world.is_finite(),"actual world region found")
    var pan=art.pan_offset
    mouse_button(world,MOUSE_BUTTON_MIDDLE,true);check(game.interaction._middle_down,"world middle press acquires camera")
    middle_move(world+Vector2(12,8))
    check((art.pan_offset-pan).distance_to(Vector2(12,8))<.2,"world middle motion pans by pointer delta")
    middle_move(points[0]);check(game.interaction._middle_down,"world-origin capture survives crossing HUD")
    mouse_button(points[0],MOUSE_BUTTON_MIDDLE,false);check(not game.interaction._middle_down,"release over HUD ends world capture")
    mouse_button(Vector2(-20,-20),MOUSE_BUTTON_MIDDLE,true);check(not game.interaction._middle_down,"outside viewport cannot acquire camera")
    mouse_button(Vector2(-20,-20),MOUSE_BUTTON_MIDDLE,false)
    check(JSON.stringify([game.model.items,game.model.coins,game.model.wall_attachments])==before and game.saves==saves,"input leaves generated model and save count unchanged")
    states+=1
 print("CAMERA_INPUT_OWNERSHIP_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"states":states,"ui_cases":ui_cases,"player_save_used":false,"native_render_verified":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
