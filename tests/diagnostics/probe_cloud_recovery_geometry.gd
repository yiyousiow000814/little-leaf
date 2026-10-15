extends SceneTree
## QA-only geometry probe: exact observed browser snapshot, production UI/fonts.
const Fixture=preload("res://tests/persistence/test_cloud_recovery_ui.gd")
func _initialize():run.call_deferred()
func run():
 var args=OS.get_cmdline_user_args()
 if args.size()!=2:quit(2);return
 var input=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
 if not input is Dictionary:quit(2);return
 var active_play=input.get("playControl",{}).get("action","")=="pause"
 if active_play and (str(input.snapshot.get("status",""))!="active" or bool(input.snapshot.get("ownershipPaused",true))):quit(2);return
 root.size=Vector2i(int(input.viewport.width),int(input.viewport.height))
 var game=Fixture.TestMain.new();root.add_child(game);game.set_process(false);game.paused=not active_play;await process_frame
 var controller=Fixture.Controller.new(game);game.web_save=controller
 controller.startup_error="" if active_play else "Synthetic geometry only"
 controller.bridge.value=input.snapshot;game.save_recovery_blocked=not active_play
 if active_play:game.model.coins=int(input.playControl.coins)
 # Replay the observed callback through the actual native controller so its
 # protected-progress message participates in layout. No copied pixel offsets.
 var callback=input.get("nativeCallback",{})
 if callback is Dictionary and callback.get("method","") in ["preserveOwnerRuntime","preserveRuntime"]:
  var receipt=callback.get("result",{})
  if receipt is Dictionary and receipt.get("ok",false) and receipt.get("durable",false):
   controller.profile_id=str(receipt.get("profileId",""));controller.revision=int(receipt.get("revision",0))-1;controller.recovery_busy=true
   controller._on_runtime_preserved([JSON.stringify(receipt)],controller._recovery_generation,callback.method=="preserveOwnerRuntime")
 if str(input.get("recoveryMessage",""))!="":controller.recovery_message=str(input.recoveryMessage)
 if active_play:game.compact_ui.help_panel.hide()
 else:game.compact_ui.show_help()
 game._update_ui()
 for frame in 18:await process_frame
 var ui=game.compact_ui;var buttons={}
 for key in ([] if active_play else ["local","cloud","switch","done"]):
  var button=ui.help_choose_local if key=="local" else ui.help_choose_cloud if key=="cloud" else ui.help_switch_device if key=="switch" else ui.help_done
  if button.visible:
   var rect=button.get_global_rect();buttons[key]=[rect.position.x,rect.position.y,rect.size.x,rect.size.y]
 if active_play and game.pause_button.is_visible_in_tree() and not game.pause_button.disabled:
  var rect=game.pause_button.get_global_rect();buttons["pause"]=[rect.position.x,rect.position.y,rect.size.x,rect.size.y]
 var file=FileAccess.open(args[1],FileAccess.WRITE)
 var result={"buttons":buttons,"text":ui.help_text.text,"heading":ui.help_heading.text,"viewport":input.viewport,"snapshot":input.snapshot,"synthetic_only":true}
 if active_play:result["play_control"]={"action":"pause","label":game.pause_button.text,"synthetic_geometry_only":true}
 file.store_string(JSON.stringify(result));file.close()
 game.queue_free();await process_frame;quit()
