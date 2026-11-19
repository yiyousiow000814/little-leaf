extends SceneTree
# No game, model, fixture, timestamps, FPS, or draw counters. Identity only.
func _initialize():
 var identity={"engine":Engine.get_version_info(),"display_server":DisplayServer.get_name(),"window":str(DisplayServer.window_get_size()),"refresh_hz":DisplayServer.screen_get_refresh_rate(),"video_adapter":RenderingServer.get_video_adapter_name(),"video_vendor":RenderingServer.get_video_adapter_vendor(),"video_api":RenderingServer.get_video_adapter_api_version(),"processor":OS.get_processor_name(),"platform":OS.get_name()}
 var path=OS.get_environment("LL_ENVELOPE_FILE")
 if path=="":quit(2);return
 var out=FileAccess.open(path,FileAccess.WRITE)
 if out==null:quit(2);return
 out.store_string(JSON.stringify(identity));out.close();quit()
