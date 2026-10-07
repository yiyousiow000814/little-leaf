extends SceneTree
## Real HUD/camera contracts across viewports, insets and owned expansions.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func signature(model)->String:
 return JSON.stringify({"coins":model.coins,"items":model.items,"owned":model.owned_parcels,"floors":model.floor_finishes,"walls":model.built_walls,"customers":model.customers})
func _initialize():run.call_deferred()
func run():
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame
 var art=game.illustration
 for expanded in [false,true]:
  if expanded:
   game.model.coins=50000
   check(game.model.buy_parcel("front_0"),"synthetic front expansion purchased")
   check(game.model.buy_parcel("right_0"),"synthetic right expansion purchased")
  var original=signature(game.model)
  for view in [Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390)]:
   root.size=view
   for insets in [Vector4.ZERO,Vector4(8,20,8,16)]:
    game.set_meta("hud_safe_insets",insets)
    for editing in [false,true]:
     game.editing=editing;game.tray.visible=editing;game.compact_ui._set_tray_reveal(1 if editing else 0)
     game._update_ui()
     for frame in 6:await process_frame
     art.fit_overview()
     var safe=art.camera_fit_rect();var bounds=art.camera_world_bounds()
     var scale=art.ui_scale*art.zoom
     var projected=Rect2(art.origin+bounds.position*scale,bounds.size*scale)
     var label=str(view)+str(insets)+str(editing)+str(expanded)
     check(safe.grow(1.0).encloses(projected),label+" complete intended land/wall bounds fit")
     check(safe.position.y>=game.compact_ui.hud.layout_host.get_global_rect().end.y,label+" fits below visible HUD")
     if editing:
      check(safe.end.y<=game.compact_ui.shop_ui.browse_rect().position.y,label+" sale view clears shop")
     else:
      check(safe.end.y>game.compact_ui.shop_ui.browse_rect().position.y,label+" Play reclaims hidden shop area")
      var owned_width=game.model._width_for(game.model.owned_parcels)
      var owned_depth=game.model._depth_for(game.model.owned_parcels)
      check(is_equal_approx(bounds.size.x,(owned_width+owned_depth)*39.0),label+" includes owned expansions and excludes future sale plots")
     check(signature(game.model)==original,label+" camera does not mutate save state")
 game.editing=false;game.tray.hide();game._update_ui()
 for frame in 6:await process_frame
 art.fit_overview();var play_zoom=art.zoom
 game.editing=true;game.tray.show();game._update_ui()
 for frame in 6:await process_frame
 art.update_projection()
 check(is_equal_approx(art.zoom,play_zoom),"opening Decorate preserves zoom until an explicit Fit")
 var result={"checks":checks,"failures":failures}
 print("FIT_OWNED_CAFE_RESULT ",JSON.stringify(result))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
