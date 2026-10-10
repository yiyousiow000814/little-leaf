extends RefCounted
## Event-driven local save/freeze handshake. No per-frame work outside binding.
var game
var active=false
var frozen=false
signal background_cleared(receipt)
var old_paused=false
var old_input=false
var old_unhandled=false
var old_gui=false
var callback
var bridge

func _init(owner):
	game=owner
	game.tree_exiting.connect(_dispose,CONNECT_ONE_SHOT)

func _dispose():
	callback=null;bridge=null;game=null;active=false;frozen=false

func begin():
	if active or game.web_save==null:return
	var save=game.web_save
	if not save.ready or save.pending or save.recovery_busy or save.update_busy or game.save_recovery_blocked:return
	if not OS.has_feature("web") or not JavaScriptBridge.eval("typeof window.LittleLeafLocalBinding === 'object'"):return
	active=true
	# Terminal background cancellation can restore old input state, so it precedes our hold.
	var background=game.get("background_elapsed")
	if background!=null:
		if not background.has_method("cancel_for_binding"):
			active=false;game.progress_save_error="Background progress must finish before binding.";return
		background.cancel_for_binding(_on_background_cleared)
		_hold_input()
		var terminal=await background_cleared
		if not is_instance_valid(game):return
		if not bool(terminal.get("ok",false)) or not bool(terminal.get("backgroundCleared",false)):
			game.progress_save_error="Background progress needs reconciliation before binding. Keep this page open."
			# The background controller owns uncertain recovery; do not resume play.
			return
	else:
		_hold_input()
	if not save.ready or save.pending or save.recovery_busy or save.update_busy or game.save_recovery_blocked:
		finish();return
	save.request_save()
	var deadline=Time.get_ticks_msec()+15000
	while save.pending and Time.get_ticks_msec()<deadline:
		await game.get_tree().process_frame
	if save.pending:
		# Unknown durable outcome: keep input frozen rather than claiming cancellation.
		game.progress_save_error="Binding postponed while this device save finishes. Keep this page open."
		while save.pending and is_instance_valid(game):await game.get_tree().process_frame
	if not is_instance_valid(game):return
	if game.progress_unsaved or not save.ready or game.save_recovery_blocked:
		finish();return
	bridge=JavaScriptBridge.get_interface("LittleLeafLocalBinding")
	callback=JavaScriptBridge.create_callback(_on_return)
	bridge.open(callback)

func _hold_input():
	old_paused=game.paused;old_input=game.is_processing_input();old_unhandled=game.is_processing_unhandled_input()
	old_gui=game.get_viewport().gui_disable_input
	frozen=true
	game.paused=true;game.set_process_input(false);game.set_process_unhandled_input(false);game.get_viewport().gui_disable_input=true
	if game.web_lifecycle!=null:game.web_lifecycle.cancel_pending()

func _on_return(_arguments:Array):finish()

func _on_background_cleared(receipt:Dictionary):
	# Also handles a synchronous no-claim receipt without missing the signal wait.
	call_deferred("_emit_background_cleared",receipt)

func _emit_background_cleared(receipt:Dictionary):background_cleared.emit(receipt)

func finish():
	if not active:return
	active=false
	if not frozen:return
	frozen=false
	game.paused=old_paused;game.set_process_input(old_input);game.set_process_unhandled_input(old_unhandled)
	game.get_viewport().gui_disable_input=old_gui
	callback=null;bridge=null
