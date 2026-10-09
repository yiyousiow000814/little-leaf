extends SceneTree
## Same generated conflict fixture renders pinned baseline and proposed recovery UI.
const WebSave=preload("res://scripts/cafe_web_save.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
class Bridge extends RefCounted:
 var value={"available":true,"busy":false,"canExport":true,"cloudRevision":8,"pendingRevision":6,"expectedCloudDigest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","reason":""}
 func recoverySnapshot():return JSON.stringify(value)
class Controller extends WebSave:
 var bridge=Bridge.new()
 func _recovery_bridge():return bridge
var game
var output=""
var frames=[]
func _initialize():run.call_deferred()
func settle():
 game._update_ui();game.illustration.queue_redraw()
 for frame in 16:await process_frame
 await RenderingServer.frame_post_draw
func shot(label:String):
 var file=label+".png";var img=root.get_texture().get_image();assert(img.save_png(output+"/"+file)==OK)
 frames.append({"file":file,"width":img.get_width(),"height":img.get_height(),"panel":str(game.compact_ui.help_panel.get_global_rect())})
func run():
 output=OS.get_environment("RECOVERY_CAPTURE_OUTPUT");assert(output!="" and DisplayServer.get_name()!="headless")
 seed(8246);root.size=Vector2i(390,844)
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true;await process_frame
 var ui=game.compact_ui;var controller=Controller.new(game);game.web_save=controller
 controller.startup_error="Another device has newer progress. Pending progress is preserved."
 game.save_recovery_blocked=true;game.startup_notice="Saved café could not be opened. Another device has newer progress. Pending progress is preserved on this device; do not overwrite it. Original progress is unchanged."
 for view in [Vector2i(390,844),Vector2i(344,680),Vector2i(844,390),Vector2i(566,360),Vector2i(1360,880)]:
  root.size=view;game.set_meta("hud_safe_insets",Vector4(8,20,8,16) if view==Vector2i(844,390) else Vector4.ZERO)
  var prefix="%dx%d"%[view.x,view.y]
  for state in ["retry","cloud","loading","changed"]:
   controller.bridge.value.available=state!="retry";controller.bridge.value.canExport=state!="retry";controller.retrying=state=="loading"
   controller.bridge.value.reason="The cloud café changed. Review the updated recovery details and confirm again." if state=="changed" else ""
   ui.show_help();await settle();shot(prefix+"-"+state+"-top")
   ui.help_scroll.scroll_vertical=100000;await settle();shot(prefix+"-"+state+"-bottom")
 assert(game.saves==0 and game.save_writes_suppressed)
 FileAccess.open(output+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify({"generated_profile":true,"renderer":RenderingServer.get_video_adapter_name(),"save_writes":game.saves,"frames":frames},"  "))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit()
