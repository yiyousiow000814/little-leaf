extends SceneTree
const WebSave=preload("res://scripts/cafe_web_save.gd")
const Main=preload("res://scripts/main.gd")
class FakeModel extends RefCounted:
 var last_error=""
 var last_event=""
 var service_snapshot={}
 var coins=1200
 var save_ok=true
 func save(path:String)->bool:
  if not save_ok:last_error="Storage unavailable";return false
  FileAccess.open(path,FileAccess.WRITE).store_string("{\"synthetic\":true}")
  return true
class FakeApi extends RefCounted:
 var credit=0
 var writes=0
 func creditForSave(_payload):return credit
 func save(_payload,_revision,_profile,_callback):writes+=1
class FakeGame extends Node:
 var model=FakeModel.new()
 var save_timer=0.0
 var save_recovery_blocked=false
 var save_writes_suppressed=false
 var progress_unsaved=false
 var progress_save_error=""
 var startup_notice=""
 var paused=false
 var web_lifecycle=null
 var followup_saves=0
 func _update_people():pass
 func _service_save_snapshot():return {}
 func _update_ui():pass
 func _save():followup_saves+=1
var failures=[]
var checks=0
func _init():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func controller(game):
 var save=WebSave.new(game);save.api=FakeApi.new();save.ready=true;save.profile_id="synthetic"
 return save
func acknowledge(save,extra:Dictionary={}):
 var result={"ok":true,"profileId":"synthetic","revision":save.revision+1,"durable":true,"creditedCoins":0}
 result.merge(extra,true);save._on_commit([JSON.stringify(result)])
func run():
 var game=FakeGame.new();root.add_child(game)
 var save=controller(game)
 check(not save.request_save() and save.pending and game.progress_unsaved,"submitted save stays pending, never premature success")
 save.request_save()
 check(save.queued and save.api.writes==1,"edits coalesce behind in-flight write")
 acknowledge(save)
 check(game.progress_unsaved,"older durable acknowledgement cannot clear newer edits")
 await process_frame
 check(game.followup_saves==1,"newer generation schedules next save")
 save.request_save();acknowledge(save)
 check(not game.progress_unsaved and game.progress_save_error=="","latest durable save clears state silently")
 save.request_save();save._on_commit([JSON.stringify({"ok":false,"error":"Browser storage is full","code":"QUOTA"})])
 check(game.progress_unsaved and game.progress_save_error=="Browser storage is full" and save.ready,"transient failure retains edits and permits retries")
 save.request_save()
 check(game.progress_save_error=="Browser storage is full","retry keeps existing warning while pending")
 save._on_commit([JSON.stringify({"ok":false,"error":"Browser storage is full","code":"QUOTA"})])
 check(game.progress_unsaved and game.progress_save_error=="Browser storage is full","repeated failure retains the same recoverable error")
 save.request_save();acknowledge(save)
 check(not game.progress_unsaved and game.progress_save_error=="","successful retry clears warning only after durability")
 game.model.save_ok=false
 save.request_save()
 check(game.progress_save_error=="Storage unavailable" and not save.pending,"native validation/staging failure retains the same recoverable error")
 game.model.save_ok=true
 # Loaded-save conflicts remain fail-closed; this patch does not turn them into startup retries.
 for code in ["REVISION_CONFLICT","CORRUPT_AUTHORITY","NOT_READY"]:
  game.save_recovery_blocked=false;game.save_writes_suppressed=false
  save=controller(game);save.request_save();save._on_commit([JSON.stringify({"ok":false,"code":code,"error":"Original progress preserved"})])
  check(not save.ready and game.save_recovery_blocked and game.save_writes_suppressed and game.paused,"fail-closed unchanged for "+code)
  check(game.progress_unsaved and game.progress_save_error!="","hard failure retains diagnostic for "+code)
 game.save_recovery_blocked=false;game.save_writes_suppressed=false
 save=controller(game);save.request_save();acknowledge(save,{"durable":false})
 check(not save.ready and game.save_recovery_blocked and game.progress_unsaved,"non-durable acknowledgement cannot clear failure")
 game.save_recovery_blocked=false;game.save_writes_suppressed=false
 save=controller(game);save.api.credit=100;save.request_save();acknowledge(save,{"creditedCoins":100})
 check(game.model.coins==1300 and not game.progress_unsaved and save.revision==1,"durable compensation credits the exact amount only after commit")
 save.request_save();acknowledge(save,{"creditedCoins":100,"campaignDeferred":["future"]})
 check(game.model.coins==1400 and save.revision==2,"second independent durable compensation credits exactly its receipt")
 save.api.credit=0;save.request_save();acknowledge(save,{"campaignDeferred":["future"]})
 check(game.model.coins==1400 and not game.progress_unsaved and save.ready,"deferred compensation does not invent wallet credit or block a durable save")
 save.request_save();acknowledge(save,{"campaignDeferred":["future"]})
 check(game.model.coins==1400 and save.revision==4,"repeated deferred compensation leaves wallet unchanged")
 var committed_revision=save.revision
 save._on_commit([JSON.stringify({"ok":true,"profileId":"synthetic","revision":committed_revision,"durable":true,"creditedCoins":100})])
 check(game.model.coins==1400 and game.save_recovery_blocked and not save.ready,"replayed receipt cannot duplicate compensation")
 var scene=Main.new()
 scene.progress_unsaved=true
 check(scene._unsaved_progress_message()=="","routine in-flight save has no error detail")
 scene.progress_save_error="Disk full"
 check("Keep the game open; saving will retry" in scene._unsaved_progress_message(),"native failure has an actionable next step")
 scene.web_save=save
 check("Keep this page open; saving will retry" in scene._unsaved_progress_message(),"browser failure has an actionable next step")
 scene.save_recovery_blocked=true
 check("Quick help" in scene._unsaved_progress_message() and not "will retry" in scene._unsaved_progress_message(),"blocked failure never promises automatic retry")
 scene.web_save=null
 for orphan in [scene.world,scene.furnishings,scene.people,scene.camera,scene.ui]:orphan.free()
 scene.free()
 print("AUTOSAVE_FEEDBACK_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
