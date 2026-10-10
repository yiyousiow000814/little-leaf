extends RefCounted
## No wall-clock debt or save migration. Current cloud fences prove no hidden
## interval: force takeover may happen before the lease expires.
const MAX_CALLBACK_SECONDS = 0.25

static func local_callbacks_allowed(recovery:Dictionary,local_marker:bool=false,bridge_present:bool=true)->bool:
	# An adapter marker only identifies a bridge-free local vault. It cannot
	# override a contradictory or missing observation from an existing bridge.
	if recovery.is_empty():return local_marker and not bridge_present
	return typeof(recovery.get("serverOwnership"))==TYPE_BOOL and recovery.serverOwnership==false and not bool(recovery.get("accountChanged",false)) and not bool(recovery.get("ownershipPaused",false)) and not bool(recovery.get("choicesAvailable",false)) and not bool(recovery.get("available",false)) and not bool(recovery.get("busy",false))

static func frame_delta(delta:float,hidden:bool,local_callbacks:bool)->float:
	if hidden and (not local_callbacks or not is_finite(delta) or delta<0.0 or delta>MAX_CALLBACK_SECONDS):return 0.0
	return delta

static func catch_up_seconds()->float:
	# Deliberately empty proof set under session schema 1. Renewal, active status,
	# and old-save timestamps are never promoted into historical authority.
	return 0.0
