extends SceneTree
## Render actual save controller and existing Help with deterministic synthetic acks.
## FakeApi replaces only browser transport and never touches IndexedDB.
const WebSave=preload("res://scripts/cafe_web_save.gd")
const NoBottom=preload("res://tests/no_bottom_notifications.gd")
class FakeApi extends RefCounted:
 func creditForSave(_payload):return 0
 func save(_payload,_revision,_profile,_callback):pass
var game
var save
var capture_dir=""
var failures=[]
var snapshots=[]
func _init():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--capture-dir="):capture_dir=arg.trim_prefix("--capture-dir=")
 call_deferred("run")
func check(ok:bool,label:String):
 if not ok:failures.append(label);printerr("FAIL ",label)
func capture(name:String):
 game._update_ui()
 for i in range(3):await process_frame
 await RenderingServer.frame_post_draw
 NoBottom.verify(game,check,name)
 snapshots.append({"name":name,"save_detail":game._unsaved_progress_message(),"help_visible":game.compact_ui.help_panel.visible,"error":game.progress_save_error,"unsaved":game.progress_unsaved})
 check(root.get_texture().get_image().save_png(capture_dir.path_join(name+".png"))==OK,"capture "+name)
func success():save._on_commit([JSON.stringify({"ok":true,"profileId":"synthetic-render","revision":save.revision+1,"durable":true,"creditedCoins":0})])
func run():
 root.size=Vector2i(1360,880)
 game=load("res://main.tscn").instantiate();root.add_child(game)
 await process_frame;await process_frame
 game.set_process(false);game.paused=true
 save=WebSave.new(game);save.ready=true;save.profile_id="synthetic-render";save.api=FakeApi.new();game.web_save=save;game.save_writes_suppressed=false
 save.request_save();await capture("01-pending")
 check(save.pending and game.progress_unsaved and game._unsaved_progress_message()=="","pending write stays unsaved with no false error")
 success();await capture("02-success")
 check(not game.progress_unsaved and not game.compact_ui.has_open_popup(),"durable success stays quiet")
 save.request_save();save._on_commit([JSON.stringify({"ok":false,"code":"QUOTA","error":"Browser storage is full"})])
 await capture("03-failure")
 var warning=game._unsaved_progress_message()
 check("Keep this page open; saving will retry" in warning and not game.compact_ui.has_open_popup(),"real failure retains actionable detail without a global popup")
 game.compact_ui.show_help();await capture("04-failure-help")
 check(warning in game.compact_ui.help_text.text,"existing Help shows save failure")
 game.compact_ui._close_help();save.request_save();await capture("05-retrying")
 check(game._unsaved_progress_message()==warning,"retry retains stable failure detail")
 success();await capture("06-recovered")
 check(game._unsaved_progress_message()=="","durable retry clears error")
 for size in [Vector2i(960,540),Vector2i(390,844)]:
  root.size=size
  save.request_save();save._on_commit([JSON.stringify({"ok":false,"code":"QUOTA","error":"Browser storage is full"})])
  await capture("07-failure-%dx%d"%[size.x,size.y])
  game.compact_ui.show_help();await capture("08-help-%dx%d"%[size.x,size.y])
  check(Rect2(Vector2.ZERO,Vector2(size)).encloses(game.compact_ui.help_panel.get_global_rect()),"existing Help fits viewport "+str(size))
  game.compact_ui._close_help();success()
 var result={"failures":failures,"snapshots":snapshots,"player_save_used":false}
 FileAccess.open(capture_dir.path_join("capture-results.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("AUTOSAVE_CAPTURE_RESULT ",JSON.stringify(result))
 game.save_writes_suppressed=true;game.web_save=null;save.stop();save=null
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame
 quit(0 if failures.is_empty() else 1)
