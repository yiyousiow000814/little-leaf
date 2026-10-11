extends "res://tests/test_existing_wall_actions.gd"
func run():
 if not "saveguard" in OS.get_user_data_dir():quit(2);return
 game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await settle()
 var art=game.illustration;var region=art.ExteriorExtent.CAMERA_WORLD_BOUNDS
 check(region.size==Vector2(64,64),"camera target is a64 by64world square")
 check(region.size.x>=2*31.65 and region.size.y>=2*26.7,"square exceeds twice both original authored target dimensions")
 check(art.ExteriorExtent.STREET_Z_MIN==-84 and art.ExteriorExtent.STREET_Z_MAX==84 and art.ExteriorExtent.PAVEMENT_Z_MIN==-82 and art.ExteriorExtent.PAVEMENT_Z_MAX==82,"simulation travel/spawn extents are unchanged")
 var signature=""
 var states=0
 for expanded in [false,true]:
  game.model.owned_parcels.assign(game.model.PARCEL_IDS if expanded else []);game.model._sync_floor_bounds()
  for detail in [false,true]:
   game.wall_detail=detail
   for insets in [Vector4.ZERO,Vector4(8,20,8,16)]:
    game.set_meta("hud_safe_insets",insets)
    for view in [Vector2i(640,360),Vector2i(960,540),Vector2i(1152,648),Vector2i(1280,720),Vector2i(1360,880),Vector2i(390,844),Vector2i(344,680),Vector2i(844,390)]:
     signature=JSON.stringify([game.model.coins,game.model.items,game.model.owned_parcels])
     root.size=view;game.editing=false;game.tray.hide();game.compact_ui._set_tray_reveal(0);await settle()
     var camera_saves=game.saves
     art.zoom=art.camera_zoom_limits().x;art.update_projection()
     check(art.zoom<(.35 if view.x<650 else .70),"manual zoom-out goes beyond shipped minimum")
     var bounds=art.CameraLandmarks.inspection_bounds(art.tile)
     var safe=art.camera_safe_rect(false)
     game.interaction._pan_by(safe.get_center()-(art.origin+bounds.get_center()))
     check(safe.grow(1).encloses(Rect2(art.origin+bounds.position,bounds.size)),"entire neighborhood target fits below HUD at minimum zoom")
     var start=art.pan_offset
     game.interaction._pan_by(Vector2(1e6,0));var right=art.pan_offset.x
     game.interaction._pan_by(Vector2(-2e6,0));var left=art.pan_offset.x
     check(right-left>=minf(art.camera_safe_rect().size.x*.3,320.0)-.1,"zoomed-out horizontal inspection cannot center-lock")
     art.pan_offset=start;art.update_projection();var before=art.origin;var before_zoom=art.zoom
     check(game.saves==camera_saves,"zoom and pan do not request saves")
     game._toggle_edit();await settle();art.update_projection()
     camera_saves=game.saves
     check(art.origin.distance_to(before)<.1 and is_equal_approx(art.zoom,before_zoom),"Decorate preserves minimum zoom and camera position")
     for point in [region.position,Vector2(region.end.x,region.position.y),region.end,Vector2(region.position.x,region.end.y)]:
      game.interaction._pan_by(art.camera_safe_rect().get_center()-art.iso(point.x,point.y))
      check(art.camera_safe_rect().grow(-8).has_point(art.iso(point.x,point.y)),"all four world-square corners are reachable through finite clamp")
     check(game.saves==camera_saves,"corner inspection does not request saves")
     game._toggle_edit();await settle()
     states+=1
     check(JSON.stringify([game.model.coins,game.model.items,game.model.owned_parcels])==signature,"camera and render coverage leave player model unchanged")
 print("SQUARE_NEIGHBORHOOD_CAMERA_RESULT ",JSON.stringify({"checks":checks,"states":states,"failures":failures,"world_square":str(region),"player_save_used":false,"render_verified":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
