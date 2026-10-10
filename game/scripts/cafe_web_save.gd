extends RefCounted
## Web progress uses only the independent IndexedDB authority. These staging
## files live in unmounted MEMFS /tmp; never put them beneath user:// or /userfs.
const SaveLog=preload("res://scripts/cafe_save_log.gd")
const MinimalStart=preload("res://scripts/minimal_start.gd")
const STAGING_FILE="/tmp/little_leaf_vault_staging.json"
var game_ref:WeakRef
var game:
	get:return game_ref.get_ref()
var api
var profile_id=""
var revision=0
var ready=false
var pending=false
var queued=false
var generation=0
var inflight_generation=0
var _confirmed_payload=""
var _inflight_payload=""
var _callback
var startup_error=""
var platform_managed=false
var _platform_dirty_snapshot=0
var retrying=false
var _retry_callback
var _recovery_callback
var _recovery_generation=0
var recovery_busy=false
var recovery_action=""
var recovery_message=""
var _choice_candidate
var _choice_receipt:Dictionary={}
var _runtime_preserved=false
var runtime_snapshot_failed=false
var _owner_snapshot_preserved=false
var _owner_pause_seen=false
var _takeover_finish_attempted=false
var _account_pause_seen=false
var update_busy=false
var update_message=""
var _update_api
var _update_callback
var _update_generation=0
var _update_old_paused=false
var _update_expected_version=""
var _update_phase=""
var _update_input_held=false
var _update_held_input=false
var _update_held_unhandled=false
var _update_held_gui=false
var _update_held_viewport:WeakRef
var _recovery_api
var _credit_hold=false
var _held_paused=false
var _held_input=false
var _held_unhandled=false
var _held_gui_disabled=false
var _held_viewport:WeakRef
var _credit_base_coins=0
var _credit_expected=0
# Read-only presentation cache, separate from model serialization.
var inbox_snapshot:Dictionary={"ok":false}

func _init(owner):game_ref=weakref(owner)

func _write_stage(payload:String)->bool:
	DirAccess.make_dir_recursive_absolute("/tmp")
	var file=FileAccess.open(STAGING_FILE,FileAccess.WRITE)
	if file==null:return false
	file.store_string(payload);file.flush()
	var error=file.get_error();file.close()
	return error==OK

func _log(event:String,code:String="",source:String=""):
	SaveLog.record(event,{"layer":"controller","profileId":profile_id,"revision":revision,"code":code,"source":source})

func load_startup():
	_log("boot_requested")
	api=JavaScriptBridge.get_interface("__littleLeafVault")
	if api==null:
		_block_startup("Browser save support is missing; reload the full game package","BRIDGE_MISSING");return
	var result=JSON.parse_string(str(api.bootJson))
	if not result is Dictionary or not bool(result.get("ok",false)):
		_block_startup(str(result.get("error","Browser save storage could not be opened")) if result is Dictionary else "Browser save startup did not finish",str(result.get("code","STORAGE_ERROR")) if result is Dictionary else "INVALID_ACK");return
	_accept_boot(result)

func _accept_boot(result:Dictionary)->bool:
	# Validate in isolation. A failed retry cannot replace the displayed model.
	var candidate=game.Model.new()
	var source=str(result.source)
	var requires_repair=false
	var notice=""
	if source=="fresh":
		MinimalStart.apply(candidate)
	else:
		if not result.get("payload") is String or not _write_stage(str(result.payload)):
			_block_startup("Could not prepare the saved café for validation");return false
		# Preserve the existing narrow legacy import exception. A normal
		# authority record must always pass strict save validation.
		if not candidate.load_save(STAGING_FILE):
			if source!="legacy-v13" or not candidate.load_save(STAGING_FILE,true):
				_block_startup(candidate.last_error);return false
			requires_repair=true
		if requires_repair:notice="Café paused for repair · Use Decorate to open a route for trapped staff, then save · Original progress is unchanged"
	game.model=candidate
	game.fresh_start=source=="fresh"
	game.startup_save_source="isolated-browser-authority" if source=="authority" else "read-only-v13-import" if source=="legacy-v13" else ""
	game.startup_notice=notice
	game.paused=requires_repair
	game.save_writes_suppressed=false;game.save_recovery_blocked=false
	startup_error="";ready=true
	_confirmed_payload="";_inflight_payload=""
	profile_id=str(result.profileId);revision=int(result.revision)
	_refresh_inbox(result)
	_log("read_accepted","",source)
	_callback=JavaScriptBridge.create_callback(_on_commit)
	return true

func _recovery_bridge():
	if _recovery_api!=null:return _recovery_api
	if not OS.has_feature("web"):return null
	if not JavaScriptBridge.eval("typeof window.LittleLeafVault === 'object' && window.LittleLeafVault !== null && typeof window.LittleLeafVault.recoverySnapshot === 'function'"):return null
	_recovery_api=JavaScriptBridge.get_interface("LittleLeafVault")
	return _recovery_api

func recovery_snapshot()->Dictionary:
	var bridge=_recovery_bridge()
	if bridge==null:return {}
	var value=JSON.parse_string(str(bridge.recoverySnapshot()))
	if not value is Dictionary:return {}
	value["busy"]=recovery_busy or retrying or pending or bool(value.get("busy",false))
	value["operation"]=recovery_action
	value["canSwitch"]=startup_error!="" or _owner_snapshot_preserved
	value["available"]=bool(value.get("available",false)) and not bool(value.get("ownershipPaused",false)) and game.save_recovery_blocked and (startup_error!="" or _runtime_preserved)
	return value

func _make_recovery_callback(handler:Callable):
	return JavaScriptBridge.create_callback(handler)

func check_runtime_recovery():
	# Cloud/ownership events freeze the live native model before any switch.
	if game==null or recovery_busy or update_busy:return
	var bridge=_recovery_bridge()
	if bridge==null:return
	var value=JSON.parse_string(str(bridge.recoverySnapshot()))
	if not value is Dictionary:return
	if bool(value.get("accountChanged",false)):
		game.paused=true;game.save_recovery_blocked=true;game.save_writes_suppressed=true
		if not _account_pause_seen:
			_account_pause_seen=true;recovery_message="Your account changed. Current progress is still open on this page. Keep this page open.";game.compact_ui.show_help()
		return
	var owner_paused=bool(value.get("serverOwnership",false)) and bool(value.get("ownershipPaused",false))
	# Reconnection can restore this same server owner. Reconcile before resuming.
	if bool(value.get("serverOwnership",false)) and value.get("status","")=="active" and _owner_pause_seen and not _takeover_finish_attempted and (startup_error!="" or _owner_snapshot_preserved):
		_takeover_finish_attempted=true;_begin_takeover("finish");return
	if owner_paused:
		game.paused=true;game.save_recovery_blocked=true;game.save_writes_suppressed=true
		if pending:return
		if not _owner_pause_seen:
			_owner_pause_seen=true;game.compact_ui.show_help()
		if value.get("status","")=="takeover-ready" and not bool(value.get("canForceTakeover",false)) and not _takeover_finish_attempted and (startup_error!="" or _owner_snapshot_preserved):
			_takeover_finish_attempted=true;_begin_takeover("finish");return
		if startup_error!="" or _owner_snapshot_preserved or runtime_snapshot_failed:return
	elif startup_error!="" or _runtime_preserved or runtime_snapshot_failed or not (bool(value.get("choicesAvailable",false)) or bool(value.get("needsRuntimeSnapshot",false))):return
	game.paused=true;game.save_recovery_blocked=true;game.save_writes_suppressed=true
	if pending:return
	if game.web_lifecycle!=null:game.web_lifecycle.cancel_pending()
	game._update_people();game.model.service_snapshot=game._service_save_snapshot()
	if not game.model.save(STAGING_FILE):
		runtime_snapshot_failed=true
		recovery_message="Could not protect current progress. Keep this page open.";return
	var payload=FileAccess.get_file_as_string(STAGING_FILE)
	if payload=="":
		runtime_snapshot_failed=true;return
	recovery_busy=true;recovery_action="protect";_recovery_generation+=1
	_recovery_callback=_make_recovery_callback(_on_runtime_preserved.bind(_recovery_generation,owner_paused))
	if owner_paused:bridge.preserveOwnerRuntime(payload,revision,profile_id,_recovery_callback)
	else:bridge.preserveRuntime(payload,revision,profile_id,_recovery_callback)

func _on_runtime_preserved(arguments:Array,request_generation:int,owner_paused:bool=false):
	if request_generation!=_recovery_generation or not recovery_busy:return
	recovery_busy=false;recovery_action=""
	if game==null or not game.is_inside_tree():return
	var result=JSON.parse_string(str(arguments[0])) if arguments.size()>0 else null
	_runtime_preserved=result is Dictionary and bool(result.get("ok",false)) and bool(result.get("durable",false)) and result.get("profileId",null)==profile_id and int(result.get("revision",-1))==revision+1
	runtime_snapshot_failed=not _runtime_preserved
	if owner_paused:_owner_snapshot_preserved=_runtime_preserved
	if _runtime_preserved:revision=int(result.get("revision",revision))
	recovery_message=("Current progress is protected on this device." if owner_paused else "Choose the café you want to keep.") if _runtime_preserved else "Could not protect current progress. Keep this page open and try again."
	game.compact_ui.show_help()

func switch_to_this_device():
	var snapshot=recovery_snapshot()
	if not bool(snapshot.get("serverOwnership",false)) or bool(snapshot.get("busy",false)):return
	if startup_error=="" and not _owner_snapshot_preserved:return
	if bool(snapshot.get("canForceTakeover",false)):_begin_takeover("force")
	elif bool(snapshot.get("canRequestTakeover",false)):_begin_takeover("request")

func _begin_takeover(action:String):
	if action!="finish":_takeover_finish_attempted=false
	recovery_busy=true;recovery_action="switch";recovery_message="";_recovery_generation+=1
	_recovery_callback=_make_recovery_callback(_on_takeover.bind(_recovery_generation))
	var bridge=_recovery_bridge()
	if action=="force":bridge.forceTakeover(_recovery_callback)
	elif action=="finish":bridge.finishTakeover(_recovery_callback)
	else:bridge.requestTakeover(_recovery_callback)

func _on_takeover(arguments:Array,request_generation:int):
	if request_generation!=_recovery_generation or not recovery_busy:return
	if game==null or not game.is_inside_tree():return
	var result=JSON.parse_string(str(arguments[0])) if arguments.size()>0 else null
	if not result is Dictionary or not bool(result.get("ok",false)):
		_choice_failure(result);return
	if not result.has("source"):
		recovery_busy=false;recovery_action="";game.compact_ui._sync_help_content();return
	var candidate=game.Model.new()
	if result.get("source","")=="fresh":MinimalStart.apply(candidate)
	elif result.get("source","")!="authority" or not result.get("payload") is String or not _write_stage(result.payload) or not candidate.load_save(STAGING_FILE):
		_choice_failure(null);return
	if str(result.get("profileId",""))=="" or int(result.get("revision",-1))<0:
		_choice_failure(null);return
	_choice_candidate=candidate
	_finish_selected_candidate(result,"You can continue on this device.")

func choose_save(choice:String):
	var snapshot=recovery_snapshot()
	if choice not in ["local","cloud"] or bool(snapshot.get("busy",false)) or not bool(snapshot.get("available",false)):return
	recovery_busy=true;recovery_action=choice;recovery_message="";_recovery_generation+=1
	_choice_candidate=null;_choice_receipt={}
	_recovery_callback=_make_recovery_callback(_on_choice_prepared.bind(_recovery_generation))
	_recovery_bridge().prepareChoice(choice,str(snapshot.get("expectedLocalDigest","")),str(snapshot.get("expectedCloudDigest","")),_recovery_callback)
	game.compact_ui._sync_help_content()

func _choice_failure(result):
	recovery_busy=false;recovery_action="";_choice_candidate=null;_choice_receipt={}
	if result is Dictionary and result.get("code","")=="RECOVERY_CANCELLED":recovery_message="Choose either save when you are ready."
	else:recovery_message=str(result.get("error","Could not validate this save. Both saves are preserved.")) if result is Dictionary else "Could not validate this save. Both saves are preserved."
	game.compact_ui._sync_help_content()

func _on_choice_prepared(arguments:Array,request_generation:int):
	if request_generation!=_recovery_generation or not recovery_busy or _choice_candidate!=null:return
	if game==null or not game.is_inside_tree():return
	var result=JSON.parse_string(str(arguments[0])) if arguments.size()>0 else null
	if not result is Dictionary or not bool(result.get("ok",false)):
		_choice_failure(result);return
	if result.get("source","")!="authority" or str(result.get("profileId",""))=="" or int(result.get("revision",0))<1 or str(result.get("selectionToken",""))=="" or not result.get("payload") is String:
		_choice_failure(null);return
	var candidate=game.Model.new()
	if not _write_stage(result.payload) or not candidate.load_save(STAGING_FILE):
		_choice_failure(null);return
	# No active model or storage replacement before strict native validation.
	_choice_candidate=candidate;_choice_receipt=result.duplicate(true)
	_recovery_callback=_make_recovery_callback(_on_choice_confirmed.bind(request_generation))
	_recovery_bridge().confirmChoice(str(result.selectionToken),_recovery_callback)

func _on_choice_confirmed(arguments:Array,request_generation:int):
	if request_generation!=_recovery_generation or not recovery_busy or _choice_candidate==null:return
	if game==null or not game.is_inside_tree():return
	var result=JSON.parse_string(str(arguments[0])) if arguments.size()>0 else null
	if not result is Dictionary or not bool(result.get("ok",false)):
		_choice_failure(result);return
	if result.get("source","")!="authority" or result.get("payload",null)!=_choice_receipt.payload or result.get("profileId",null)!=_choice_receipt.profileId or int(result.get("revision",-1))!=int(_choice_receipt.revision):
		_choice_failure(null);return
	_finish_selected_candidate(result)

func _finish_selected_candidate(result:Dictionary,message:String="Your selected café is ready. The other save is protected on this device."):
	_release_update_input()
	game.model=_choice_candidate;profile_id=str(result.profileId);revision=int(result.revision)
	recovery_busy=false;recovery_action="";_choice_candidate=null;_choice_receipt={};_runtime_preserved=false
	_owner_snapshot_preserved=false;_owner_pause_seen=false;_takeover_finish_attempted=false;runtime_snapshot_failed=false
	ready=true;startup_error="";game.paused=false;game.save_recovery_blocked=false;game.save_writes_suppressed=false
	game.progress_unsaved=false;game.progress_save_error="";game.startup_notice="";game.fresh_start=result.get("source","")=="fresh"
	game.startup_save_source="isolated-browser-authority" if not game.fresh_start else ""
	_confirmed_payload="";_inflight_payload="";queued=false
	_callback=_make_recovery_callback(_on_commit);_refresh_inbox(result)
	recovery_message=message
	game._resume_loaded_cafe()

func _hold_update_input():
	if _update_input_held:return
	_update_input_held=true;_update_held_input=game.is_processing_input();_update_held_unhandled=game.is_processing_unhandled_input()
	var viewport=game.get_viewport();_update_held_viewport=weakref(viewport);_update_held_gui=viewport.gui_disable_input
	game.set_process_input(false);game.set_process_unhandled_input(false);viewport.gui_disable_input=true

func _release_update_input(restore_world:bool=true):
	if not _update_input_held:return
	var viewport=_update_held_viewport.get_ref() if _update_held_viewport!=null else null
	if is_instance_valid(viewport):viewport.gui_disable_input=_update_held_gui
	if restore_world:
		if game!=null:game.set_process_input(_update_held_input);game.set_process_unhandled_input(_update_held_unhandled)
		_update_input_held=false;_update_held_viewport=null

func _update_bridge():
	if _update_api!=null:return _update_api
	if not OS.has_feature("web"):return null
	if not JavaScriptBridge.eval("typeof window.LittleLeafUpdate === 'object' && typeof window.LittleLeafUpdate.reloadForUpdate === 'function'"):return null
	_update_api=JavaScriptBridge.get_interface("LittleLeafUpdate")
	return _update_api

func save_and_update(version:String):
	var bridge=_update_bridge()
	if bridge==null or update_busy or pending or recovery_busy or not ready or game.save_recovery_blocked:return
	var snapshot=JSON.parse_string(str(bridge.snapshot()))
	if not snapshot is Dictionary or not bool(snapshot.get("available",false)) or str(snapshot.get("version",""))!=version:return
	_update_old_paused=game.paused;game.paused=true;_hold_update_input()
	if game.web_lifecycle!=null:game.web_lifecycle.cancel_pending()
	game._update_people();game.model.service_snapshot=game._service_save_snapshot()
	if not game.model.save(STAGING_FILE):
		game.paused=_update_old_paused;_release_update_input();update_message="Could not validate current progress. Update postponed.";return
	var payload=FileAccess.get_file_as_string(STAGING_FILE)
	if payload=="":
		game.paused=_update_old_paused;_release_update_input();update_message="Could not prepare current progress. Update postponed.";return
	update_busy=true;_update_phase="save";update_message="";_update_generation+=1;_update_expected_version=version
	game.save_recovery_blocked=true;game.save_writes_suppressed=true
	_update_callback=_make_recovery_callback(_on_update_saved.bind(_update_generation))
	_recovery_bridge().saveForUpdate(payload,revision,profile_id,_update_callback)

func _on_update_saved(arguments:Array,request_generation:int):
	if request_generation!=_update_generation or not update_busy or _update_phase!="save":return
	if game==null or not game.is_inside_tree():return
	var result=JSON.parse_string(str(arguments[0])) if arguments.size()>0 else null
	if result is Dictionary and bool(result.get("durable",false)) and result.get("profileId",null)==profile_id and int(result.get("revision",-1))==revision+1:
		revision=int(result.revision)
	else:
		_update_failed("Could not verify the save. Update postponed.");return
	if not bool(result.get("ok",false)) or not bool(result.get("cloudConfirmed",false)) or str(result.get("updateToken",""))=="":
		_update_failed("Your progress is on this device. Cloud confirmation is still needed before updating.");return
	_update_phase="reload"
	_update_callback=_make_recovery_callback(_on_update_reload.bind(request_generation))
	_update_bridge().reloadForUpdate(_update_expected_version,profile_id,revision,str(result.updateToken),_update_callback)

func _on_update_reload(arguments:Array,request_generation:int):
	if request_generation!=_update_generation or not update_busy:return
	if game==null or not game.is_inside_tree():return
	var result=JSON.parse_string(str(arguments[0])) if arguments.size()>0 else null
	# A successful reload destroys this runtime. No callback may resume play early.
	if not result is Dictionary or not bool(result.get("ok",false)):_update_failed("The update is postponed. Your current café is still open.")

func _update_failed(reason:String):
	update_busy=false;_update_phase="";_update_generation+=1;update_message=reason
	var bridge=_recovery_bridge()
	var state=JSON.parse_string(str(bridge.recoverySnapshot())) if bridge!=null else null
	# Only a verified current owner with no conflict may resume the frozen model.
	if state is Dictionary and bool(state.get("serverOwnership",false)) and state.get("status","")=="active" and not bool(state.get("choicesAvailable",false)) and not bool(state.get("accountChanged",false)):
		game.save_recovery_blocked=false;game.save_writes_suppressed=false;game.paused=_update_old_paused
		_release_update_input()
	else:
		# Recovery GUI remains usable, but world input stays held until validated resume.
		_release_update_input(false)
	game.compact_ui.sync()

func retry_startup():
	if runtime_snapshot_failed:
		runtime_snapshot_failed=false;check_runtime_recovery();return
	# A failed save of an already loaded café may have unsaved edits. Never
	# reload those edits through the startup retry or bypass revision guards.
	if retrying or recovery_busy or startup_error=="" or pending:return
	_log("retry_requested")
	retrying=true
	_retry_callback=JavaScriptBridge.create_callback(_on_retry)
	var vault=JavaScriptBridge.get_interface("LittleLeafVault")
	if vault==null:
		retrying=false;game.compact_ui.show_help();return
	vault.retry(_retry_callback)
	game.compact_ui.show_help()

func _on_retry(arguments:Array):
	retrying=false
	if game==null or not game.is_inside_tree():return
	var result=JSON.parse_string(str(arguments[0])) if arguments.size()>0 else null
	if not result is Dictionary or not bool(result.get("ok",false)):
		_log("read_failure",str(result.get("code","STORAGE_ERROR")) if result is Dictionary else "INVALID_ACK")
		startup_error=str(result.get("error","Browser save storage could not be opened")) if result is Dictionary else "Invalid browser save response"
		game.startup_notice="Saved café could not be opened · "+startup_error+" · Original progress is unchanged"
		game.compact_ui.show_help();return
	api=JavaScriptBridge.get_interface("__littleLeafVault")
	if _accept_boot(result):game._resume_loaded_cafe()
	else:game.compact_ui.show_help()

func _block_startup(reason:String,code:String="VALIDATION_FAILED"):
	_log("read_failure",code)
	startup_error=reason;ready=false
	game.save_writes_suppressed=true;game.save_recovery_blocked=true;game.paused=true
	game.startup_notice="Saved café could not be opened · "+reason+" · Original progress is unchanged"
	MinimalStart.apply(game.model)

func request_save(skip_unchanged:bool=false)->bool:
	_log("save_requested")
	game.save_timer=0.0
	if game.background_elapsed!=null and game.background_elapsed.holding and game.background_elapsed.phase!="waiting-save":
		_log("save_skipped","ELAPSED_RECONCILING");return false
	if not ready or game.save_recovery_blocked or game.save_writes_suppressed:
		_log("save_skipped","NOT_READY" if not ready else "RECOVERY_BLOCKED" if game.save_recovery_blocked else "WRITES_SUPPRESSED");return false
	generation+=1
	game.progress_unsaved=true
	if pending:
		_log("save_queued")
		queued=true;return false
	game._update_people()
	game.model.service_snapshot=game._service_save_snapshot()
	# The native codec's complete save validation runs before any IDB write.
	if not game.model.save(STAGING_FILE):
		_log("save_failure","VALIDATION_FAILED")
		game.progress_save_error=game.model.last_error
		return false
	var dirty_generation=game.get("platform_dirty_generation")
	if dirty_generation!=null:_platform_dirty_snapshot=int(dirty_generation)
	_log("save_validated")
	var payload=FileAccess.get_file_as_string(STAGING_FILE)
	if payload=="":
		_log("save_failure","STAGING_FAILED")
		game.progress_save_error="Could not read the validated save"
		return false
	# Keep an existing failure visible while the retry is in flight. Clearing it
	# here makes every automatic retry flash the same warning again.
	_credit_expected=int(api.creditForSave(payload))
	# Only periodic saves may deduplicate, after the complete native validation.
	# Explicit saves/hide saves, errors, edits and compensation still commit.
	if skip_unchanged and not platform_managed and _credit_expected==0 and payload==_confirmed_payload and game.progress_save_error=="":
		game.progress_unsaved=false
		_log("save_skipped")
		return true
	pending=true;queued=false;inflight_generation=generation
	_inflight_payload=payload
	if _credit_expected>0:_hold_for_credit()
	game.model.last_event="Saving café progress"
	_log("save_submitted")
	api.save(payload,revision,profile_id,_callback)
	# A submitted asynchronous write is never reported as durable success.
	return false

func _hold_for_credit():
	# Freeze only while a grant-bearing transaction is pending. No wallet
	# credit is visible/spendable before its receipt and payload commit.
	if game.web_lifecycle!=null:game.web_lifecycle.cancel_pending()
	_credit_hold=true;_credit_base_coins=game.model.coins
	_held_paused=game.paused;_held_input=game.is_processing_input();_held_unhandled=game.is_processing_unhandled_input()
	var viewport=game.get_viewport();_held_viewport=weakref(viewport);_held_gui_disabled=viewport.gui_disable_input
	game.paused=true;game.set_process_input(false);game.set_process_unhandled_input(false);viewport.gui_disable_input=true

func _release_credit_hold():
	if not _credit_hold:return
	_credit_hold=false
	var viewport=_held_viewport.get_ref() if _held_viewport!=null else null
	if is_instance_valid(viewport):viewport.gui_disable_input=_held_gui_disabled
	if game!=null:
		game.paused=_held_paused;game.set_process_input(_held_input);game.set_process_unhandled_input(_held_unhandled)
	_held_viewport=null

func stop():
	_recovery_generation+=1;_update_generation+=1;update_busy=false;recovery_busy=false;recovery_action=""
	var update_bridge=_update_bridge()
	if update_bridge!=null:update_bridge.close()
	_release_update_input();_release_credit_hold();ready=false

func _on_commit(arguments:Array):
	_release_credit_hold()
	if game==null or not game.is_inside_tree():return
	var result=JSON.parse_string(str(arguments[0])) if arguments.size()>0 else null
	pending=false
	if not result is Dictionary or not bool(result.get("ok",false)):
		game.progress_unsaved=true;queued=false
		var reason=str(result.get("error","Browser save failed")) if result is Dictionary else "Invalid browser save acknowledgement"
		var code=str(result.get("code","")) if result is Dictionary else ""
		_log("save_failure",code if code!="" else "INVALID_ACK")
		if code in ["REVISION_CONFLICT","CORRUPT_AUTHORITY","NOT_READY"]:
			ready=false;game.save_recovery_blocked=true;game.save_writes_suppressed=true;game.paused=true
			game.startup_notice="Unsaved changes · "+reason
		game.progress_save_error=reason
		return
	var platform_ack=bool(result.get("platformAccepted",false)) and str(api.storageKind)=="crazygames-data" and result.get("cloudConfirmed",true)==false
	if str(result.get("profileId",""))!=profile_id or int(result.get("revision",-1))!=revision+1 or not (bool(result.get("durable",false)) or platform_ack):
		ready=false;game.progress_unsaved=true;game.save_recovery_blocked=true;game.paused=true
		_log("save_failure","INVALID_REVISION_ACK")
		game.progress_save_error="Invalid browser save revision; reload to recover"
		game.startup_notice="Unsaved changes · "+game.progress_save_error
		return
	var credit=result.get("creditedCoins",0)
	if not (credit is int or credit is float) or not is_finite(float(credit)) or floor(float(credit))!=float(credit) or int(credit)!=_credit_expected or int(credit)<0 or int(credit)>1000000000:
		ready=false;game.progress_unsaved=true;game.save_recovery_blocked=true;game.paused=true
		_log("save_failure","INVALID_CREDIT_ACK")
		game.progress_save_error="Invalid compensation acknowledgement; reload to recover"
		game.startup_notice="Unsaved changes · "+game.progress_save_error;return
	if int(credit)>0:
		if game.model.coins!=_credit_base_coins or game.model.coins>1000000000-int(credit):
			ready=false;game.progress_unsaved=true;game.save_recovery_blocked=true;game.paused=true
			_log("save_failure","CREDIT_SYNC_REQUIRED")
			game.progress_save_error="Compensation was saved; reload to synchronize the wallet"
			game.startup_notice=game.progress_save_error;return
		game.model.coins+=int(credit)
		game._update_ui()
	_credit_expected=0
	revision=int(result.revision)
	_refresh_inbox(result)
	platform_managed=platform_ack
	_confirmed_payload=_inflight_payload
	_inflight_payload=""
	if platform_ack and game.get("platform_dirty_generation")!=null:
		game.platform_autosave_dirty=int(game.platform_dirty_generation)!=_platform_dirty_snapshot
	_log("platform_controller_accepted" if platform_ack else "save_accepted")
	if queued or generation!=inflight_generation:
		queued=false
		# Never clear a newer edit's unsaved marker from an older completion.
		game.call_deferred("_save");return
	game.progress_unsaved=bool(game.get("platform_autosave_dirty")) if platform_ack else false;game.progress_save_error="";game.model.last_error="";game.model.last_event="Progress submitted to CrazyGames" if platform_ack else "Café progress saved"
	game._update_ui()
	if game.background_elapsed!=null:game.background_elapsed.save_finished()

func _refresh_inbox(result:Dictionary):
	# Accept only a snapshot paired with this accepted boot/durable revision.
	# Missing presentation support must never affect the authoritative save.
	var snapshot=result.get("inbox",null)
	if not snapshot is Dictionary or not bool(snapshot.get("ok",false)) or str(snapshot.get("profileId",""))!=profile_id or int(snapshot.get("revision",-1))!=revision:
		inbox_snapshot={"ok":false};return
	if not snapshot.get("paid") is Array or not snapshot.get("deferred") is Array:
		inbox_snapshot={"ok":false};return
	inbox_snapshot=snapshot.duplicate(true)
