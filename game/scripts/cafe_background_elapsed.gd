extends RefCounted
## Open-page account intervals only. No save timestamp import or offline income.
const STEP=1.0/60.0
const CHUNK_SECONDS=0.25
var game_ref:WeakRef
var game:
	get:return game_ref.get_ref()
var phase="idle"
var token=""
var generation=0
var callback
var bridge
var candidate_model
var candidate_payload=""
var held_input=false
var held_unhandled=false
var held_gui=false
var input_held=false
var last_seconds=0.0
var last_discarded=0.0
var last_error=""
var replay_remaining=0.0
var holding:bool:
	get:return phase!="idle"

func _init(owner):game_ref=weakref(owner)

func hidden_changed(hidden:bool):
	if hidden:
		if holding:return
		if game.paused or game.editing or game.save_recovery_blocked or game.cafe_intro!=null and game.cafe_intro.active:return
		var recovery=game.web_save.recovery_snapshot()
		if (not bool(recovery.get("serverOwnership",false)) and recovery.get("backgroundOwnership","")!="local-lock") or recovery.get("status","")!="active":return
		bridge=game.web_save._recovery_bridge()
		if bridge==null or not JavaScriptBridge.eval("typeof window.LittleLeafVault.beginBackground === 'function'"):return
		generation+=1;phase="waiting-save";last_seconds=0.0;last_discarded=0.0;last_error=""
		_hold_input();save_finished()
	elif phase=="armed":_seal()
	elif holding:stop()

func save_finished():
	if phase!="waiting-save" or game.web_save.pending:return
	if not game.browser_hidden or game.paused or game.save_recovery_blocked:stop();return
	phase="arming"
	callback=JavaScriptBridge.create_callback(_on_arm.bind(generation))
	bridge.beginBackground(game.web_save.revision,game.web_save.profile_id,callback)

func _result(args:Array)->Dictionary:
	var value=JSON.parse_string(str(args[0])) if not args.is_empty() else null
	return value if value is Dictionary else {}

func _on_arm(args:Array,expected:int):
	if expected!=generation or phase!="arming":return
	var value=_result(args)
	if not bool(value.get("ok",false)) or not game.browser_hidden:
		last_error=str(value.get("code","ELAPSED_CHANGED"));stop();return
	token=str(value.token);phase="armed"

func _seal():
	phase="sealing"
	callback=JavaScriptBridge.create_callback(_on_seal.bind(generation))
	bridge.finishBackground(token,callback)

func _on_seal(args:Array,expected:int):
	if expected!=generation or phase!="sealing":return
	var value=_result(args)
	game.web_save.check_runtime_recovery()
	var seconds=float(value.get("seconds",-1.0))
	if not bool(value.get("ok",false)) or not is_finite(seconds) or seconds<0.0 or game.paused or game.save_recovery_blocked:
		last_error=str(value.get("code","ELAPSED_CHANGED"));stop();return
	last_seconds=seconds;last_discarded=float(value.get("discardedSeconds",0.0))
	phase="replaying";replay_remaining=seconds
	_replay_chunk(generation)

func _replay_chunk(expected:int):
	if expected!=generation or phase!="replaying":return
	if game.paused or game.save_recovery_blocked:stop();return
	# Limit work per turn, not guest income. The private snapshot is restored
	# between chunks, so the public model cannot earn or save speculative progress.
	var chunk=minf(CHUNK_SECONDS,replay_remaining)
	candidate_payload=_trial_payload(chunk,candidate_payload)
	if candidate_payload=="":last_error="ELAPSED_SNAPSHOT";stop();return
	replay_remaining-=chunk
	if replay_remaining>0.000000001:
		game.get_tree().process_frame.connect(_replay_chunk.bind(expected),CONNECT_ONE_SHOT)
		return
	phase="committing"
	callback=JavaScriptBridge.create_callback(_on_commit.bind(generation))
	bridge.commitBackground(candidate_payload,token,callback)

func _trial_payload(seconds:float,continuation:String="")->String:
	if not is_finite(seconds) or seconds<0.0 or seconds>60.0:return ""
	# Replay into a private model with no earnings/audio/save signal bindings.
	# Existing model and runtime are restored before the asynchronous cloud CAS.
	var original=game.model
	if continuation=="":
		original.service_snapshot=game._service_save_snapshot()
		if not original.save(game.web_save.STAGING_FILE):return ""
	else:
		var file=FileAccess.open(game.web_save.STAGING_FILE,FileAccess.WRITE)
		if file==null:return ""
		file.store_string(continuation);file.close()
	candidate_model=game.Model.new()
	if not candidate_model.load_save(game.web_save.STAGING_FILE):return ""
	game.model=candidate_model;game._restore_service_runtime()
	game._background_trial=true
	var remaining=seconds
	while remaining>0.000000001:
		var delta=minf(STEP,remaining)
		game._advance_business(delta);remaining-=delta
	candidate_model.service_snapshot=game._service_save_snapshot()
	var valid=candidate_model.save(game.web_save.STAGING_FILE)
	var payload=FileAccess.get_file_as_string(game.web_save.STAGING_FILE) if valid else ""
	game.model=original;game._restore_service_runtime()
	game._background_trial=false
	return payload

func _on_commit(args:Array,expected:int):
	if expected!=generation or phase!="committing":return
	var value=_result(args)
	if bool(value.get("ok",false)) and (bool(value.get("cloudConfirmed",false)) or bool(value.get("authorityConfirmed",false))) and int(value.get("revision",-1))==game.web_save.revision+1 and str(value.get("profileId",""))==game.web_save.profile_id:
		# Local campaign settlement may change the verified payload. Consume the
		# whole durable snapshot instead of adding a second wallet credit.
		if value.get("payload") is String and value.payload!=candidate_payload:
			var file=FileAccess.open(game.web_save.STAGING_FILE,FileAccess.WRITE)
			if file==null:game.paused=true;game.save_recovery_blocked=true;game.save_writes_suppressed=true;stop();return
			file.store_string(value.payload);file.close()
			var confirmed=game.Model.new()
			if not confirmed.load_save(game.web_save.STAGING_FILE):game.paused=true;game.save_recovery_blocked=true;game.save_writes_suppressed=true;stop();return
			candidate_model=confirmed;candidate_payload=value.payload
		game.model=candidate_model;game._connect_model_events();game._restore_service_runtime()
		game.web_save.revision=int(value.revision)
		game.web_save._confirmed_payload=candidate_payload
		game.progress_unsaved=not bool(value.get("durable",false))
		if game.progress_unsaved:game.paused=true;game.save_recovery_blocked=true;game.save_writes_suppressed=true
	else:
		last_error=str(value.get("code","ELAPSED_COMMIT"))
		game.paused=true;game.save_recovery_blocked=true;game.save_writes_suppressed=true
	phase="settled"
	stop();game.web_save.check_runtime_recovery();game._update_ui()

func _hold_input():
	held_input=game.is_processing_input();held_unhandled=game.is_processing_unhandled_input();held_gui=game.get_viewport().gui_disable_input
	input_held=true;game.set_process_input(false);game.set_process_unhandled_input(false);game.get_viewport().gui_disable_input=true

func stop():
	# A dispatched transaction can already have committed on the server. Its
	# receipt must reconcile through reload before the old model may write again.
	if phase=="committing" and game!=null:
		game.paused=true;game.save_recovery_blocked=true;game.save_writes_suppressed=true
	generation+=1
	if bridge!=null:bridge.cancelBackground()
	phase="idle";token="";candidate_model=null;candidate_payload="";replay_remaining=0.0
	if input_held and game!=null:
		game.set_process_input(held_input);game.set_process_unhandled_input(held_unhandled);game.get_viewport().gui_disable_input=held_gui
	input_held=false
	if game!=null:game._resume_frame=Engine.get_process_frames()+1
