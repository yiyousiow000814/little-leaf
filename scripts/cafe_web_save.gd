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
		if candidate.included_bin_pending:candidate.ensure_basic_bin()
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

func retry_startup():
	# A failed save of an already loaded café may have unsaved edits. Never
	# reload those edits through the startup retry or bypass revision guards.
	if retrying or startup_error=="" or pending:return
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
	_release_credit_hold();ready=false

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

func _refresh_inbox(result:Dictionary):
	# Accept only a snapshot paired with this accepted boot/durable revision.
	# Missing presentation support must never affect the authoritative save.
	var snapshot=result.get("inbox",null)
	if not snapshot is Dictionary or not bool(snapshot.get("ok",false)) or str(snapshot.get("profileId",""))!=profile_id or int(snapshot.get("revision",-1))!=revision:
		inbox_snapshot={"ok":false};return
	if not snapshot.get("paid") is Array or not snapshot.get("deferred") is Array:
		inbox_snapshot={"ok":false};return
	inbox_snapshot=snapshot.duplicate(true)
