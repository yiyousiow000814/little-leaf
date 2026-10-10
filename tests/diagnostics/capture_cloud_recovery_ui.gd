extends SceneTree
## Same generated conflict fixture renders pinned baseline and proposed recovery UI.
const WebSave=preload("res://scripts/cafe_web_save.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
class Bridge extends RefCounted:
 var value={"available":true,"busy":false,"canExport":true,"choicesAvailable":true,"choices":[{"id":"local","coins":42000,"lastSavedLabel":"9 Oct 2026, 04:35","device":"Android phone"},{"id":"cloud","coins":37000,"lastSavedLabel":"9 Oct 2026, 04:32","device":"Unknown device"}],"cloudRevision":8,"pendingRevision":6,"expectedCloudDigest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","reason":""}
 func recoverySnapshot():return JSON.stringify(value)
class UpdatePreview extends RefCounted:
 var value={"available":false,"version":"0.1.11","busy":false,"reason":""}
 func snapshot():return JSON.stringify(value)
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
 var update_preview=UpdatePreview.new()
 var update_notice=ui.get("update_notice")
 if update_notice!=null:update_notice.api=update_preview
 controller.startup_error="Another device has newer progress. Pending progress is preserved."
 game.save_recovery_blocked=true;game.startup_notice="Saved café could not be opened. Another device has newer progress. Pending progress is preserved on this device; do not overwrite it. Original progress is unchanged."
 for view in [Vector2i(390,844),Vector2i(344,680),Vector2i(844,390),Vector2i(566,360),Vector2i(1360,880)]:
  root.size=view;game.set_meta("hud_safe_insets",Vector4(8,20,8,16) if view==Vector2i(844,390) else Vector4.ZERO)
  var prefix="%dx%d"%[view.x,view.y]
  for state in ["retry","cloud","loading","changed","other-device","waiting","handoff-requested","timeout","update","update-saving","update-error"]:
   controller.bridge.value.available=state in ["cloud","loading","changed"];controller.bridge.value.canExport=state!="retry";controller.retrying=state=="loading"
   controller.bridge.value.reason="The cloud café changed. Review the updated recovery details and confirm again." if state=="changed" else ""
   var owner_state=state in ["other-device","waiting","handoff-requested","timeout"]
   controller.bridge.value.serverOwnership=owner_state;controller.bridge.value.ownershipPaused=owner_state
   controller.bridge.value.status="takeover-ready" if state=="timeout" else state
   controller.bridge.value.canRequestTakeover=state in ["other-device","handoff-requested"]
   controller.bridge.value.canForceTakeover=state=="timeout"
   if owner_state:controller.bridge.value.reason="Waiting for the other device to save and pause." if state=="waiting" else "The other device has not confirmed its latest save." if state=="timeout" else "Current progress is protected before switching."
   var update_state=state in ["update","update-saving","update-error"]
   game.save_recovery_blocked=not update_state;controller.ready=update_state
   update_preview.value.available=update_state;update_preview.value.busy=state=="update-saving"
   update_preview.value.reason="Your progress is on this device. Cloud confirmation is still needed before updating." if state=="update-error" else ""
   if update_state:ui.help_panel.hide()
   else:ui.show_help()
   await settle();shot(prefix+"-"+state+"-top")
   ui.help_scroll.scroll_vertical=100000;await settle();shot(prefix+"-"+state+"-bottom")
 assert(game.saves==0 and game.save_writes_suppressed)
 FileAccess.open(output+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify({"generated_profile":true,"server_events_simulated":true,"update_manifest_simulated":true,"renderer":RenderingServer.get_video_adapter_name(),"save_writes":game.saves,"frames":frames},"  "))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit()
