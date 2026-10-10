extends "res://tests/test_existing_wall_actions.gd"
## Shared bounded neighborhood range with an independent frozen-clamp oracle.
const Baseline=preload("res://tests/fixtures/play_camera_0dd4.gd")
var observations=[]
func cutoff_visible(a:Vector2,b:Vector2,view:Rect2)->bool:
 if view.has_point(a) or view.has_point(b):return true
 var corners=[view.position,Vector2(view.end.x,view.position.y),view.end,Vector2(view.position.x,view.end.y)]
 for edge in 4:
  if Geometry2D.segment_intersects_segment(a,b,corners[edge],corners[(edge+1)%4])!=null:return true
 return false
func mode(editing:bool):
 game.editing=editing;game._cancel_selection();game.tray.visible=editing;game.compact_ui._set_tray_reveal(1 if editing else 0);await settle()
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated profile");quit(2);return
 root.size=Vector2i(1189,624);game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await process_frame;game._set_catalog_category("Build");await settle()
 var art=game.illustration;var before=JSON.stringify([game.model.coins,game.model.items,game.model.wall_attachments,game.model.owned_parcels]);var directions=[Vector2(-1,0),Vector2(1,0),Vector2(0,-1),Vector2(0,1),Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]
 for view in [Vector2i(640,360),Vector2i(960,540),Vector2i(1152,648),Vector2i(1280,720),Vector2i(1189,624),Vector2i(1360,880),Vector2i(390,844),Vector2i(344,680),Vector2i(844,390),Vector2i(566,360)]:
  root.size=view;await mode(false);art.update_projection();var limits=art.camera_zoom_limits()
  for zoom in [limits.x,clampf(1.15,limits.x,limits.y),limits.y]:
   var play=[]
   for editing in [false,true]:
    await mode(editing);art.zoom=zoom;art.pan_offset=Vector2.ZERO;art.update_projection()
    for direction in directions:
     var delta=direction*1000000;var base=art.origin-art.pan_offset;var size=art.get_viewport_rect().size
     var lower=Baseline.clamp_pan(Vector2(-1e9,-1e9),base,art.tile,game.model.visible_land_width(),game.model.visible_land_depth(),size,art.camera_play_rect().position.y,art.camera_safe_rect(),art.CameraLandmarks.inspection_bounds(art.tile))
     var upper=Baseline.clamp_pan(Vector2(1e9,1e9),base,art.tile,game.model.visible_land_width(),game.model.visible_land_depth(),size,art.camera_play_rect().position.y,art.camera_safe_rect(),art.CameraLandmarks.inspection_bounds(art.tile))
     var slack=minf(art.camera_safe_rect().size.x*.15,160.0)
     var requested=art.pan_offset+delta
     var expected=Vector2(clampf(requested.x,lower.x-slack,upper.x+slack),clampf(requested.y,lower.y,upper.y))
     game.interaction._pan_by(delta)
     check(art.pan_offset.distance_to(expected)<.1,"current clamp matches explicit bounded neighborhood camera policy")
     var state={"origin":art.origin,"pan":art.pan_offset,"tile":art.tile,"zoom":art.zoom}
     if not editing:play.append(state)
     else:
      var original=play[directions.find(direction)]
      check(art.pan_offset.distance_to(original.pan)<.1 and art.origin.distance_to(original.origin)<.1 and art.tile.distance_to(original.tile)<.001 and is_equal_approx(art.zoom,original.zoom),"Decorate extrema exactly reuse Play range at matched zoom/viewport")
     var cuts=false;var viewport=Rect2(Vector2.ZERO,size)
     for z in [art.ExteriorExtent.RENDER_STREET_Z_MIN,art.ExteriorExtent.RENDER_STREET_Z_MAX]:cuts=cuts or cutoff_visible(art.iso(art.Neighborhood.ROAD_LEFT,z),art.iso(art.Neighborhood.ROAD_RIGHT,z),viewport)
     check(not cuts,"original-range extrema never reveal road asset cutoffs")
     observations.append({"viewport":str(view),"editing":editing,"zoom":zoom,"direction":str(direction),"origin":str(art.origin),"pan":str(art.pan_offset),"cutoff_visible":cuts})
    art.queue_redraw();await process_frame
   # A mode switch also preserves the current inspected point, not just limits.
   var origin=art.origin;var pan=art.pan_offset;await mode(false);art.update_projection()
   check(art.origin.distance_to(origin)<.1 and art.pan_offset.distance_to(pan)<.1,"Done retains camera at original shared range")
 check(JSON.stringify([game.model.coins,game.model.items,game.model.wall_attachments,game.model.owned_parcels])==before,"camera range restores without wallet/layout/ownership mutations")
 var output=OS.get_environment("OUTPUT")
 if output!="":FileAccess.open(output+"/shared-play-camera.json",FileAccess.WRITE).store_string(JSON.stringify(observations,"  "))
 print("DECORATE_CAMERA_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"baseline":"0dd4db11 clamp plus explicit horizontal inspection allowance","viewports":10,"matched_zoom_levels":3,"directions":8,"player_save_used":false,"native_render_verified":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
