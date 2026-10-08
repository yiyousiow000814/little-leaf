extends "res://tests/test_existing_wall_actions.gd"
## Every visible build edge can reach the unobstructed work area while panning.
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated profile");quit(2);return
 root.size=Vector2i(1164,624);game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await process_frame;game._toggle_edit();game._set_catalog_category("Build");game.compact_ui._set_tray_reveal(1);await settle()
 var art=game.illustration;var tool=game.build_tools
 var before=JSON.stringify([game.model.coins,game.model.items,game.model.wall_attachments])
 for view in [Vector2i(1164,624),Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390),Vector2i(566,360)]:
  root.size=view;await settle();tool.choose("door")
  for zoom in [art.camera_zoom_limits().x,1.15,2.0,art.camera_zoom_limits().y]:
   art.zoom=zoom;art.update_projection();var expected_zoom=art.zoom
   var width=float(game.model.visible_land_width());var depth=float(game.model.visible_land_depth())
   for target in [Vector3(.5,0,70),Vector3(11.5,0,70),Vector3(0,8.5,70),Vector3(width-.5,depth-.5,0),Vector3(.5,depth-.5,0),Vector3(width-.5,.5,0)]:
    var point=art.iso(target.x,target.y,target.z);var center=art.camera_safe_rect().get_center()
    game.interaction._pan_by(center-point)
    point=art.iso(target.x,target.y,target.z)
    check(point.distance_to(center)<1.0,str(view)+" zoom "+str(zoom)+" build edge reaches clear work-area center "+str(target))
    check(not game.interaction._over_ui(point),"target is clear of real HUD/shop controls")
    check(is_equal_approx(art.zoom,expected_zoom),"pan never changes zoom")
  # Actual pointer drags while a door preview is selected work on both axes.
  for delta in [Vector2(60,0),Vector2(-60,0),Vector2(0,30),Vector2(0,-30)]:
   var start=art.camera_safe_rect().get_center();var old=art.origin
   var press=InputEventMouseButton.new();press.position=start;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;root.push_input(press,true)
   var move=InputEventMouseMotion.new();move.position=start+delta;move.relative=delta;move.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(move,true)
   press=press.duplicate();press.position=start+delta;press.pressed=false;root.push_input(press,true)
   check(art.origin.distance_to(old+delta)<1.0,"selected Door drag follows pointer in direction "+str(delta))
 check(JSON.stringify([game.model.coins,game.model.items,game.model.wall_attachments])==before,"camera work leaves wallet/layout/openings unchanged")
 print("DECORATE_CAMERA_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false,"native_render_verified":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
