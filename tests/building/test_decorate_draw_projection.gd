extends "res://tests/building/test_existing_wall_actions.gd"
## Inspect the live production draw boundary, not only the final input origin.
class ObservedArt extends "res://scripts/rendering/illustrated_cafe.gd":
 var parcel_draws=0
 var projection_refreshes=0
 var inside_parcel=false
 var changed_origins=0
 func update_projection(clamp_camera:bool=true):
  if inside_parcel:projection_refreshes+=1
  super.update_projection(clamp_camera)
 func _parcel_ground(hovered:String):
  var before=origin
  inside_parcel=true
  super._parcel_ground(hovered)
  inside_parcel=false
  if origin!=before:changed_origins+=1
  parcel_draws+=1
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated profile");quit(2);return
 root.size=Vector2i(1360,880);game=TestMain.new();root.add_child(game)
 game.set_process(false);game.paused=true
 if game.cafe_intro!=null:game.cafe_intro.finish()
 var old=game.illustration;game.remove_child(old);old.free()
 var art=ObservedArt.new();art.game=game;game.illustration=art;game.add_child(art);art.set_process(false)
 game._toggle_edit();game.compact_ui._set_tray_reveal(1)
 var wallet=game.model.coins
 for retained in [true,false]:
  art.use_retained_presentation=retained
  for pan in [Vector2(110,45),Vector2(-80,-30),Vector2.ZERO]:
   art.pan_offset=pan;art.update_projection()
   var motion=InputEventMouseMotion.new();motion.position=Vector2(750,180);motion.global_position=motion.position;root.push_input(motion,true)
   await settle()
   var before=art.origin;art.hit_parcel(Vector2(750,180))
   check(art.origin.distance_to(before)<.1,"external parcel picking retains global input projection")
 check(art.parcel_draws>0,"observed production parcel draw runs")
 check(art.projection_refreshes==0,"parcel drawing never refreshes input projection")
 check(art.changed_origins==0,"parcel drawing preserves the shared world origin")
 check(game.model.coins==wallet,"camera query cannot change wallet")
 print("DECORATE_DRAW_PROJECTION_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"draws":art.parcel_draws,"player_save_used":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
