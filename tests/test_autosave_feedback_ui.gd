extends SceneTree
## Headless scene/UI-state checks only. No pixels, browser storage or player save.
const WebSave=preload("res://scripts/cafe_web_save.gd")
class FakeApi extends RefCounted:
 func creditForSave(_payload):return 0
 func save(_payload,_revision,_profile,_callback):pass
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _init():call_deferred("run")
func settle(game):
 game._update_ui()
 await process_frame;await process_frame
 game.compact_ui.status_notice.sync_position()
func ack(save):save._on_commit([JSON.stringify({"ok":true,"profileId":"synthetic-ui","revision":save.revision+1,"durable":true,"creditedCoins":0})])
func run():
 root.size=Vector2i(1360,880)
 var game=load("res://main.tscn").instantiate();root.add_child(game)
 game.set_process(false);game.paused=true
 await settle(game)
 var save=WebSave.new(game);save.ready=true;save.profile_id="synthetic-ui";save.api=FakeApi.new();game.web_save=save;game.save_writes_suppressed=false
 game._notify("Decorate action feedback")
 save.request_save();await settle(game)
 check(save.pending and game.progress_unsaved and game._unsaved_progress_message()=="","normal pending save adds no status warning")
 check(game.status_text.text=="Decorate action feedback" and not game.compact_ui.status_notice.issue_label.visible,"pending save preserves meaningful action feedback")
 ack(save);await settle(game)
 check(not game.progress_unsaved and game.status_text.text=="Decorate action feedback","durable success preserves action feedback silently")
 for size in [Vector2i(1360,880),Vector2i(960,540),Vector2i(390,844)]:
  root.size=size;await settle(game)
  save.request_save();save._on_commit([JSON.stringify({"ok":false,"code":"QUOTA","error":"Browser storage is full"})]);await settle(game)
  var row=game.compact_ui.status_notice
  check(row.panel.visible and row.issue_label.visible and "Keep this page open; saving will retry" in row.issue_label.text,"failure warning is visible and actionable "+str(size))
  check(Rect2(Vector2.ZERO,Vector2(size)).encloses(row.panel.get_global_rect()),"failure warning stays within viewport geometry "+str(size))
  var warning=row.issue_label.text
  game.settings.show();await settle(game)
  check(game._unsaved_progress_message()==warning,"opening Settings retains error state "+str(size))
  game.settings.hide();await settle(game)
  check(row.panel.visible and row.issue_label.text==warning,"closing Settings restores persistent failure "+str(size))
  save.request_save();await settle(game)
  check(row.panel.visible and row.issue_label.text==warning,"retry retains warning without flashing "+str(size))
  ack(save);await settle(game)
  check(game._unsaved_progress_message()=="" and not row.issue_label.visible,"durable recovery clears warning "+str(size))
 root.size=Vector2i(1360,880);await settle(game)
 save.request_save();save._on_commit([JSON.stringify({"ok":false,"code":"REVISION_CONFLICT","error":"Original progress preserved"})]);await settle(game)
 check(game.compact_ui.status_notice.panel.visible and "Quick help" in game.compact_ui.status_notice.issue_label.text and not "will retry" in game.compact_ui.status_notice.issue_label.text,"hard failure stays visible and points to help")
 game.compact_ui.show_help();await settle(game)
 check(game.compact_ui.help_panel.visible,"hard failure help can be opened")
 check("Original progress preserved" in game.compact_ui.help_text.text,"help retains exact failure details")
 game.save_writes_suppressed=true;game.web_save=null;save.stop();save=null
 game.queue_free();await process_frame;await process_frame
 print("AUTOSAVE_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"rendered_pixels_verified":false}))
 quit(0 if failures.is_empty() else 1)
