extends SceneTree
const WebSave=preload("res://scripts/cafe_web_save.gd")
class FakeModel extends RefCounted:
 var coins=1000
 var last_error=""
 var last_event=""
class FakeGame extends Node:
 var model=FakeModel.new()
 var paused=false
 var progress_unsaved=true
 var progress_save_error=""
 var startup_notice=""
 var save_recovery_blocked=false
 var save_writes_suppressed=false
 var followups=0
 func _save():followups+=1
 func _update_ui():pass
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label)
func _initialize():call_deferred("run")
func run():
 var game=FakeGame.new();root.add_child(game)
 var save=WebSave.new(game);save.ready=true;save.profile_id="synthetic";save.revision=4
 var snapshot={"ok":true,"profileId":"synthetic","revision":5,"paid":[{"id":"old","revision":1,"coins":1000}],"deferred":[]}
 save.queued=true;save.generation=2;save.inflight_generation=1
 save._on_commit([JSON.stringify({"ok":true,"profileId":"synthetic","revision":5,"durable":true,"creditedCoins":0,"inbox":snapshot})])
 check(bool(save.inbox_snapshot.get("ok",false)) and int(save.inbox_snapshot.get("revision",-1))==5 and save.inbox_snapshot.get("paid",[]).size()==1 and save.inbox_snapshot.paid[0].id=="old","queued-save early return occurs after snapshot refresh")
 check(game.progress_unsaved,"queued presentation refresh cannot clear newer unsaved state")
 await process_frame
 check(game.followups==1,"queued progress save still schedules normally")
 snapshot.paid[0].coins=900
 check(save.inbox_snapshot.paid[0].coins==1000,"cache is an independent presentation copy")
 var previous=save.inbox_snapshot.duplicate(true)
 save._on_commit([JSON.stringify({"ok":false,"code":"QUOTA","error":"synthetic","inbox":{"ok":true,"paid":[{"coins":9999}]}})])
 check(save.inbox_snapshot==previous,"failed commit cannot refresh paid history")
 save._on_commit([JSON.stringify({"ok":true,"profileId":"synthetic","revision":6,"durable":false,"creditedCoins":0,"inbox":{"ok":true,"paid":[{"coins":9999}]}})])
 check(save.inbox_snapshot==previous,"non-durable acknowledgement cannot refresh paid history")
 save.ready=true;game.save_recovery_blocked=false
 save._on_commit([JSON.stringify({"ok":true,"profileId":"other","revision":6,"durable":true,"creditedCoins":0,"inbox":{"ok":true}})])
 check(save.inbox_snapshot==previous,"wrong-profile acknowledgement cannot refresh history")
 save._refresh_inbox({"inbox":{"ok":true,"profileId":"other","revision":5,"paid":[],"deferred":[]}})
 check(not save.inbox_snapshot.ok,"snapshot identity mismatch is unavailable")
 save._refresh_inbox({"inbox":{"ok":true,"profileId":"synthetic","revision":4,"paid":[],"deferred":[]}})
 check(not save.inbox_snapshot.ok,"snapshot revision mismatch is unavailable")
 print("INBOX_SAVE_CACHE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
