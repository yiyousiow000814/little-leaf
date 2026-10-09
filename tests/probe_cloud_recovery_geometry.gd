extends SceneTree
## QA-only geometry probe: exact observed browser snapshot, production UI/fonts.
const Fixture=preload("res://tests/test_cloud_recovery_ui.gd")
func _initialize():run.call_deferred()
func run():
 var args=OS.get_cmdline_user_args()
 if args.size()!=2:quit(2);return
 var input=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
 if not input is Dictionary:quit(2);return
 root.size=Vector2i(int(input.viewport.width),int(input.viewport.height))
 var game=Fixture.TestMain.new();root.add_child(game);game.set_process(false);game.paused=true;await process_frame
 var controller=Fixture.Controller.new(game);game.web_save=controller
 controller.startup_error="Synthetic geometry only";controller.recovery_message=str(input.get("recoveryMessage",""))
 controller.bridge.value=input.snapshot;game.save_recovery_blocked=true
 game.compact_ui.show_help();game._update_ui()
 for frame in 18:await process_frame
 var ui=game.compact_ui;var buttons={}
 for key in ["local","cloud","switch","done"]:
  var button=ui.help_choose_local if key=="local" else ui.help_choose_cloud if key=="cloud" else ui.help_switch_device if key=="switch" else ui.help_done
  if button.visible:
   var rect=button.get_global_rect();buttons[key]=[rect.position.x,rect.position.y,rect.size.x,rect.size.y]
 var file=FileAccess.open(args[1],FileAccess.WRITE)
 file.store_string(JSON.stringify({"buttons":buttons,"text":ui.help_text.text,"heading":ui.help_heading.text,"viewport":input.viewport,"snapshot":input.snapshot,"synthetic_only":true}));file.close()
 game.queue_free();await process_frame;quit()
