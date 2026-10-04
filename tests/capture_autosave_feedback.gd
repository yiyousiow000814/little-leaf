extends SceneTree
## Render the actual save controller/UI with deterministic asynchronous acks.
## FakeApi replaces only the browser transport; it never touches IndexedDB.
const WebSave=preload("res://scripts/cafe_web_save.gd")
class FakeApi extends RefCounted:
 func creditForSave(_payload):return 0
 func save(_payload,_revision,_profile,_callback):pass
var game
var save
var capture_dir=""
var baseline=false
var failures=[]
var snapshots=[]
func _init():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--capture-dir="):capture_dir=arg.trim_prefix("--capture-dir=")
 baseline="--expect-baseline" in OS.get_cmdline_user_args()
 call_deferred("run")
func check(ok:bool,label:String):
 if not ok:failures.append(label);printerr("FAIL ",label)
func capture(name:String):
 game._update_ui()
 for i in range(3):await process_frame
 await RenderingServer.frame_post_draw
 var notice=game.compact_ui.status_notice
 snapshots.append({"name":name,"warning":game._unsaved_progress_message(),"notice_visible":notice.panel.visible,"status":game.status_text.text,"error":game.progress_save_error,"unsaved":game.progress_unsaved})
 check(root.get_texture().get_image().save_png(capture_dir.path_join(name+".png"))==OK,"capture "+name)
func success():
 save._on_commit([JSON.stringify({"ok":true,"profileId":"synthetic-render","revision":save.revision+1,"durable":true,"creditedCoins":0})])
func run():
 root.size=Vector2i(1360,880)
 game=load("res://main.tscn").instantiate();root.add_child(game)
 await process_frame;await process_frame
 game.set_process(false);game.paused=true
 if game.compact_ui.has_method("dismiss_starter_hint"):game.compact_ui.dismiss_starter_hint()
 game._dismiss_edit_feedback()
 save=WebSave.new(game);save.ready=true;save.profile_id="synthetic-render";save.api=FakeApi.new();game.web_save=save
 game.save_writes_suppressed=false
 save.request_save();await capture("01-pending")
 check(save.pending and game.progress_unsaved,"pending write remains unsaved")
 check((game._unsaved_progress_message()!="")==baseline,"pending background feedback matches expected before/after")
 success();await capture("02-success")
 check(not game.progress_unsaved,"durable acknowledgement clears latest unsaved state")
 check((game.status_text.visible and "Saved" in game.status_text.text)==baseline,"success feedback matches expected before/after")
 save.request_save();save._on_commit([JSON.stringify({"ok":false,"code":"QUOTA","error":"Browser storage is full"})])
 await capture("03-failure")
 var warning=game._unsaved_progress_message()
 check("Unsaved changes" in warning,"real failure remains visible")
 if not baseline:check("Keep this page open; saving will retry" in warning,"failure provides actionable next step")
 save.request_save();await capture("04-retrying")
 if not baseline:check(game._unsaved_progress_message()==warning,"retry leaves one stable warning instead of flashing it again")
 success()
 if baseline:game._dismiss_edit_feedback()
 await capture("05-recovered")
 check(game._unsaved_progress_message()=="","successful retry clears failure")
 for size in [Vector2i(960,540),Vector2i(390,844)]:
  root.size=size
  save.request_save();save._on_commit([JSON.stringify({"ok":false,"code":"QUOTA","error":"Browser storage is full"})])
  await capture("06-failure-%dx%d"%[size.x,size.y])
  var panel=game.compact_ui.status_notice.panel
  check(Rect2(Vector2.ZERO,Vector2(size)).encloses(panel.get_global_rect()),"failure fits viewport "+str(size))
  success()
 var result={"baseline":baseline,"failures":failures,"snapshots":snapshots}
 FileAccess.open(capture_dir.path_join("capture-results.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("AUTOSAVE_CAPTURE_RESULT ",JSON.stringify(result))
 game.save_writes_suppressed=true;game.web_save=null;save.stop();save=null
 game.queue_free();await process_frame;await process_frame
 quit(0 if failures.is_empty() else 1)
