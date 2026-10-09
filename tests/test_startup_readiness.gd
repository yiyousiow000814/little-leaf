extends SceneTree
const Main = preload("res://scripts/main.gd")
const Intro = preload("res://scripts/cafe_intro.gd")
const Warmup = preload("res://scripts/cafe_startup_readiness.gd")
class TestMain extends Main:
	var autosaves = 0
	func _autosave():autosaves += 1
class RecoveryBridge extends RefCounted:
	var value = {"available":false,"choicesAvailable":false,"serverOwnership":false,"ownershipPaused":false,"accountChanged":false}
	var preserve_calls = 0
	func recoverySnapshot():return JSON.stringify(value)
	func preserveOwnerRuntime(_payload,_revision,_profile_id,_callback):preserve_calls += 1
	func preserveRuntime(_payload,_revision,_profile_id,_callback):preserve_calls += 1
class RecoveryController extends "res://scripts/cafe_web_save.gd":
	var bridge = RecoveryBridge.new()
	func _recovery_bridge():return bridge
	func _make_recovery_callback(handler:Callable):return handler
class TestWarmup extends Warmup:
	func _connect_draw():pass
class FakeAtlas extends RefCounted:
	var state = "warming"
	var cancellations = 0
	func is_ready():return state == "ready"
	func cancel_prepare(_reason):state = "failed_fallback";cancellations += 1
var checks = 0
var failures = []
var game
func check(ok,label):
	checks += 1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func fresh_intro():
	game.cafe_intro.finish();Intro.shown_this_session = false
	game.cafe_intro = Intro.new();game.cafe_intro.start(game)
	return game.cafe_intro
func run():
	Intro.shown_this_session = false
	game = TestMain.new();game.process_mode = Node.PROCESS_MODE_DISABLED;root.add_child(game)
	var music = game.audio_players.duplicate()
	var elapsed = game.animation_time
	var intro = game.cafe_intro
	var gate = TestWarmup.new();gate.start(game)
	var first = FakeAtlas.new();first.state = "ready"
	var second = FakeAtlas.new();var third = FakeAtlas.new()
	gate.atlases = [first,second,third];gate._update_status()
	check(intro.preparing and intro.active and intro.hud_alpha == 1.0,"opaque preparation owns active intro and warms real HUD")
	check(gate.cover.color.a == 1.0 and gate.layer > intro.layer,"warm HUD stays behind fully opaque cover")
	check(gate.ready_count == 1 and gate.terminal_count == 1 and "1/3" in gate.label.text,"readiness count reflects actual ready atlases")
	intro._process(5.0)
	check(intro.elapsed == 0.0 and intro.motion_delta(.5) == 0.0 and intro.motion_delta(5.0) == 0.0,"preparation never advances intro or simulation clocks")
	var key = InputEventKey.new();key.keycode = KEY_ENTER;key.pressed = true
	check(intro.handle_input(key) and intro.active,"loading key is consumed without entry or skip")
	gate._after_draw();gate._after_draw()
	check(not gate.finishing,"draws alone cannot release incomplete preparation")
	for early_frame in range(8):gate._after_draw()
	second.state = "ready";third.state = "ready";gate._update_status();gate._after_draw()
	check(not gate.finishing and gate.terminal_draws == 1 and intro.preparing,"earlier warming draws cannot replace two final-texture draws")
	gate._after_draw();await process_frame
	check(game.startup_preparation_report.terminal_draws == 2,"release records two draws after final atlas became terminal")
	check(not intro.preparing and intro.active and intro.elapsed == 0.0 and intro.hud_alpha == 0.0,"ready warm-up restores original welcome start and hidden HUD")
	check(intro.handle_input(key) and intro.active,"held loading key cannot skip newly visible welcome")
	key.pressed = false;check(intro.handle_input(key),"loading key release remains owned")
	intro._process(5.0)
	check(intro.active and intro.elapsed == 0.0,"first visible intro frame discards loading stall delta")
	intro._process(.1)
	check(is_equal_approx(intro.elapsed,.1),"ordinary timeline resumes after preparation")
	check(game.animation_time == elapsed and game.audio_players == music,"preparation leaves model animation and audio identity unchanged")
	check(not intro.entry_requested,"loading input cannot pre-request a later entrance")
	key.pressed = true
	check(intro.handle_input(key) and intro.active and intro.entry_requested and intro.elapsed == 1.0,"first independent gesture after preparation starts normal descent")
	key.pressed = false;check(intro.handle_input(key),"post-preparation entrance release is consumed")

	intro = fresh_intro();gate = TestWarmup.new();gate.start(game)
	first = FakeAtlas.new();first.state = "ready";second = FakeAtlas.new();third = FakeAtlas.new()
	gate.atlases = [first,second,third]
	gate.started_ms = Time.get_ticks_msec()-gate.MAX_WAIT_MS
	gate._process(0)
	check(gate.timed_out and first.cancellations == 0 and second.cancellations == 1 and third.cancellations == 1,"timeout cancels only pending bakes")
	check(gate.ready_count == 1 and gate.terminal_count == 3,"failed fallback is terminal without claiming it ready")
	intro.finish()
	check(intro.active and intro.finish_after_preparation,"interruption remains covered until preparation is terminal")
	gate._after_draw();gate._after_draw();await process_frame
	check(not intro.active and not intro.preparing and intro.hud_alpha == 1.0,"interrupted preparation releases to restored restaurant HUD")

	for reason in ["owner","account"]:
		for boundary in ["poll","deferred_finish"]:
			game.web_save = null;game.paused = false;game.save_recovery_blocked = false;game.save_writes_suppressed = false
			game.compact_ui.help_panel.hide()
			intro = fresh_intro();gate = TestWarmup.new();gate.start(game)
			first = FakeAtlas.new();second = FakeAtlas.new();third = FakeAtlas.new();gate.atlases = [first,second,third]
			var controller = RecoveryController.new(game);controller.pending = true;controller._inflight_payload = "synthetic pending bytes"
			game.web_save = controller
			var model_before = game.model;var animation_before = game.animation_time;var save_before = game.save_timer;var autosaves_before = game.autosaves
			if boundary == "deferred_finish":
				first.state = "ready";second.state = "ready";third.state = "ready";gate._update_status();gate._after_draw();gate._after_draw()
				check(gate.finishing,"terminal draw schedules deferred reveal before injected loss")
			if reason == "account":controller.bridge.value.accountChanged = true
			else:
				controller.bridge.value.serverOwnership = true;controller.bridge.value.ownershipPaused = true;controller.bridge.value.status = "other-device"
			if boundary == "poll":
				gate._process(0)
				check(game.paused and game.save_recovery_blocked and game.save_writes_suppressed,"poll immediately preserves recovery fences for "+reason)
				check(first.cancellations == 1 and second.cancellations == 1 and third.cancellations == 1,"recovery cancels pending preparation instead of hiding its UI until timeout")
			game._process(.25)
			check(game.model == model_before and game.animation_time == animation_before and game.save_timer == save_before and game.autosaves == autosaves_before,"preparation never advances model/save clocks across "+reason+" "+boundary)
			if boundary == "poll":gate._after_draw();gate._after_draw()
			await process_frame
			check(game.paused and game.save_recovery_blocked and game.save_writes_suppressed,"final reveal retains authority fences for "+reason+" "+boundary)
			check(not intro.active and not intro.preparing and intro.hud_alpha == 1.0 and game.compact_ui.help_panel.visible,"recovery UI is revealed without a welcome/descent overlay")
			check(controller.pending and controller._inflight_payload == "synthetic pending bytes" and game.model == model_before,"pending bytes and original model survive recovery reveal")
			check(game.autosaves == autosaves_before,"recovery reveal cannot autosave stale state")
	game.web_save = null;game.paused = false;game.save_recovery_blocked = false;game.save_writes_suppressed = false
	game.compact_ui.help_panel.hide()
	intro = fresh_intro();gate = TestWarmup.new();gate.start(game)
	first = FakeAtlas.new();second = FakeAtlas.new();third = FakeAtlas.new();gate.atlases = [first,second,third]
	var owner_controller = RecoveryController.new(game);game.web_save = owner_controller
	owner_controller.bridge.value.serverOwnership = true;owner_controller.bridge.value.ownershipPaused = true;owner_controller.bridge.value.status = "other-device"
	gate._process(0);gate._process(0)
	check(owner_controller.recovery_busy and owner_controller.bridge.preserve_calls == 1,"repeated preparation polls start one protected synthetic snapshot")
	gate._after_draw();gate._after_draw();await process_frame
	check(owner_controller.bridge.preserve_calls == 1 and owner_controller.recovery_busy and game.save_recovery_blocked,"final reveal check cannot duplicate an in-flight recovery transaction")
	game.web_save = null

	for script in [preload("res://scripts/furniture_static_atlas.gd"),preload("res://scripts/moving_art_atlas.gd"),preload("res://scripts/character_head_atlas.gd")]:
		var atlas = script.new();atlas.state = "warming"
		var target = atlas._viewport(self)
		atlas.cancel_prepare("Synthetic timeout")
		check(atlas.state == "failed_fallback" and atlas._bake_viewports.is_empty() and target.is_queued_for_deletion(),"cancel releases pending render target")
		atlas._build(self)
		check(atlas.texture == null,"cancelled deferred bake cannot restart or upload later")
		# Resume each real coroutine suspension after cancellation. No renderer
		# readback occurs because the cancellation guards must return first.
		for suspension in range(3):
			var pending = script.new();pending.state = "warming"
			pending._build(self)
			if suspension >= 1:RenderingServer.frame_post_draw.emit()
			if suspension >= 2:await process_frame
			check(not pending._bake_viewports.is_empty(),"suspended bake owns a tracked render target")
			pending.cancel_prepare("Synthetic suspended timeout")
			RenderingServer.frame_post_draw.emit();await process_frame
			check(pending.state == "failed_fallback" and pending.texture == null and pending._bake_viewports.is_empty(),"cancelled async bake cannot upload or replace resources after resume")
	await process_frame
	print("STARTUP_READINESS_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
