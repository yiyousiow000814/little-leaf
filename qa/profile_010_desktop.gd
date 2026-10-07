extends SceneTree
## Desktop render baseline only; does not measure physical phone heat.
class TestMain extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():return true
var samples=[]
func _initialize():run.call_deferred()
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("PROFILE SAVEGUARD FAILED");quit(2);return
 root.size=Vector2i(1360,880);Engine.max_fps=60
 var game=TestMain.new();root.add_child(game);game.paused=true;game.model.operating_open=false
 await process_frame
 game.illustration.zoom=1.0;game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection(false)
 for frame in 90:await process_frame
 for frame in 300:
  await process_frame
  samples.append({"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)})
 var result={"mode":"desktop closed-cafe 60fps synthetic baseline","phase":OS.get_environment("PHASE"),"viewport":"1360x880","renderer":RenderingServer.get_video_adapter_name(),"samples":samples,"player_save_used":false,"physical_phone_temperature_measured":false,"thermal_improvement_established":false}
 FileAccess.open(OS.get_environment("OUTPUT").path_join("desktop-profile.json"),FileAccess.WRITE).store_string(JSON.stringify(result))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit()
