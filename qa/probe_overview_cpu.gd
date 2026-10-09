extends "res://tests/test_existing_wall_actions.gd"
func run():
 game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true;await settle()
 var art=game.illustration;var records=[]
 for view in [Vector2i(960,540),Vector2i(1360,880),Vector2i(390,844)]:
  root.size=view;await settle()
  for minimum in [false,true]:
   art.zoom=art.camera_zoom_limits().x if minimum else 1.15;art.pan_offset=Vector2.ZERO;art.update_projection()
   var samples=[]
   for frame in range(36):
    art.pan_offset.x+=3.0;art.update_projection()
    var start=Time.get_ticks_usec();art.background_cache.update(art);var elapsed=Time.get_ticks_usec()-start
    if frame>=6:samples.append(elapsed/1000.0)
   samples.sort()
   records.append({"viewport":str(view),"minimum":minimum,"zoom":art.zoom,"scale":art.tile.x/39.0,"background_pan_cpu_ms_p50":samples[15],"background_pan_cpu_ms_p95":samples[28],"commands":art.background_cache.command_count})
 var stroke=[]
 for frame in range(36):
  var start=Time.get_ticks_usec();art.ground_art.prepare_pavement_strokes(.2+frame*.01);var elapsed=Time.get_ticks_usec()-start
  if frame>=6:stroke.append(elapsed/1000.0)
 stroke.sort()
 print("OVERVIEW_CPU_PROBE ",JSON.stringify({"records":records,"stroke_rebuild_cpu_ms_p50":stroke[15],"stroke_rebuild_cpu_ms_p95":stroke[28],"engine":Engine.get_version_info().string,"render_driver":DisplayServer.get_name(),"gpu_frame_time_measured":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit()
