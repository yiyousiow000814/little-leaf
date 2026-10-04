extends SceneTree
## Engine-only failure coverage. This script never opens the game scene.
const WebSave=preload("res://scripts/cafe_web_save.gd")
const Main=preload("res://scripts/main.gd")
class FakeModel extends RefCounted:
 var last_error=""
 var last_event=""
 var service_snapshot={}
 var coins=1200
 var save_ok=true
 var empty_payload=false
 var writes=0
 func save(path:String)->bool:
  writes+=1
  if not save_ok:last_error="Synthetic storage unavailable";return false
  var file=FileAccess.open(path,FileAccess.WRITE)
  file.store_string("" if empty_payload else "{\"synthetic\":true}");file.close()
  return true
class NoDiskModel extends RefCounted:
 var last_error="Synthetic disk full"
 var last_event=""
 var service_snapshot={}
 var save_ok=false
 var calls=0
 func save(_path:String)->bool:
  calls+=1
  return save_ok
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
 var notices=[]
 var followup_saves=0
 func _notify(words):notices.append(words)
 func _update_people():pass
 func _service_save_snapshot():return {}
 func _update_ui():pass
 func _save():followup_saves+=1
class NativeHarness extends Main:
 var notices=[]
 func _notify(words:String):notices.append(words)
 func _update_people():pass
 func _service_save_snapshot()->Dictionary:return {}
var failures=[]
var checks=0
func _init():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func make_save(game):
 var save=WebSave.new(game);save.ready=true;save.profile_id="synthetic";save.api=FakeApi.new()
 return save
func ack(save,extra:Dictionary={}):
 var record={"ok":true,"profileId":"synthetic","revision":save.revision+1,"durable":true,"creditedCoins":0}
 record.merge(extra,true);save._on_commit([JSON.stringify(record)])
func dispose_main(game):
 for orphan in [game.world,game.furnishings,game.people,game.camera,game.ui]:orphan.free()
 game.free()
func run():
 var game=FakeGame.new();root.add_child(game)
 var save=make_save(game)
 # Failed staging must remain visible without an API write or transient toast.
 game.model.empty_payload=true
 check(not save.request_save() and not save.pending and save.api.writes==0,"empty validated staging never submits")
 check(game.progress_unsaved and game.progress_save_error=="Could not read the validated save" and game.notices.is_empty(),"empty staging retains an actionable error")
 game.model.empty_payload=false
 save.request_save();ack(save)
 # A previous failure must survive an acknowledgement for an older generation.
 save.request_save();save._on_commit([JSON.stringify({"ok":false,"code":"QUOTA","error":"Synthetic storage full"})])
 save.request_save();save.request_save();ack(save)
 check(game.progress_unsaved and game.progress_save_error=="Synthetic storage full","older success does not hide error while newer changes are unsaved")
 await process_frame
 check(game.followup_saves==1,"older success schedules the queued generation")
 save.request_save();ack(save)
 check(not game.progress_unsaved and game.progress_save_error=="" and game.notices.is_empty(),"latest durable acknowledgement clears error silently")
 # Malformed and empty callbacks stay retryable errors.
 for arguments in [[],["not json"],["[]"]]:
  save.request_save();save._on_commit(arguments)
  check(game.progress_unsaved and game.progress_save_error!="" and not save.pending and save.ready,"malformed callback remains a retryable visible failure")
  save.request_save();ack(save)
 # Wrong acknowledgements must fail closed, preserve unsaved state and stop writes.
 for extra in [{"profileId":"different"},{"revision":0},{"revision":99},{"durable":false},{"creditedCoins":1},{"creditedCoins":0.5},{"creditedCoins":"0"},{"creditedCoins":-1}]:
  game.save_recovery_blocked=false;game.save_writes_suppressed=false;game.paused=false
  save=make_save(game);save.request_save();ack(save,extra)
  check(not save.ready and game.save_recovery_blocked and game.paused and game.progress_unsaved and game.progress_save_error!="","invalid acknowledgement remains fail-closed: "+str(extra))
  var prior_writes=save.api.writes;var prior_generation=save.generation
  check(not save.request_save() and save.api.writes==prior_writes and save.generation==prior_generation,"blocked acknowledgement cannot trigger another write")
  check(game.notices.is_empty(),"blocked failure uses the persistent warning without toast spam")
 # A credited wallet changed in flight must not be overwritten by compensation.
 game.save_recovery_blocked=false;game.save_writes_suppressed=false;game.paused=false
 save=make_save(game);save.api.credit=100;save.request_save();game.model.coins+=1;ack(save,{"creditedCoins":100})
 check(game.model.coins==1201 and game.progress_unsaved and game.save_recovery_blocked and not save.ready,"wallet mismatch preserves wallet and fails closed")
 check(not save._credit_hold and not game.get_viewport().gui_disable_input,"credit failure releases input hold")
 # Native feedback semantics with a zero-I/O save model, not the player profile.
 var native=NativeHarness.new();native.model=NoDiskModel.new()
 check(not native._save() and native.progress_unsaved and native.progress_save_error=="Synthetic disk full","native save failure records unsaved state")
 var warning=native._unsaved_progress_message()
 check("Keep the game open; saving will retry" in warning and native.notices.is_empty(),"native failure remains actionable without a transient toast")
 check(not native._save() and native._unsaved_progress_message()==warning,"repeated native failures retain the same warning")
 native.model.save_ok=true
 check(native._save() and not native.progress_unsaved and native.progress_save_error=="" and native._unsaved_progress_message()=="" and native.notices.is_empty(),"native success clears persistent error silently")
 native.save_recovery_blocked=true
 var native_calls=native.model.calls
 check(native._save() and native.model.calls==native_calls,"existing native recovery guard still suppresses disk writes")
 dispose_main(native)
 game.queue_free();await process_frame
 print("AUTOSAVE_ADVERSARIAL_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
