extends RefCounted
## No wall-clock debt or save migration. Current cloud fences prove no hidden
## interval: force takeover may happen before the lease expires.
const MAX_CALLBACK_SECONDS = 0.25

static func local_callbacks_allowed(recovery:Dictionary,local_marker:bool=false,bridge_present:bool=true)->bool:
	# An adapter marker only identifies a bridge-free local vault. It cannot
	# override a contradictory or missing observation from an existing bridge.
	if recovery.is_empty():return local_marker and not bridge_present
	if bool(recovery.get("accountChanged",false)) or bool(recovery.get("ownershipPaused",false)) or bool(recovery.get("choicesAvailable",false)) or bool(recovery.get("available",false)) or bool(recovery.get("busy",false)):return false
	if typeof(recovery.get("serverOwnership"))!=TYPE_BOOL:return false
	if not recovery.serverOwnership:return true
	# Like foreground callbacks, these are speculative until a current-fence
	# snapshot commit. Cached active status never proves a historical interval.
	return recovery.get("status","")=="active" and typeof(recovery.get("ownershipPaused"))==TYPE_BOOL and recovery.ownershipPaused==false

static func frame_delta(delta:float,hidden:bool,local_callbacks:bool)->float:
	if hidden and (not local_callbacks or not is_finite(delta) or delta<0.0 or delta>MAX_CALLBACK_SECONDS):return 0.0
	return delta

static func catch_up_seconds()->float:
	# Deliberately empty proof set under session schema 1. Renewal, active status,
	# and old-save timestamps are never promoted into historical authority.
	return 0.0
