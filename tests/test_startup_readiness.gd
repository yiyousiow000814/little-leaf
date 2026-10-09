extends SceneTree
const Main = preload("res://scripts/main.gd")
const Intro = preload("res://scripts/cafe_intro.gd")
const Warmup = preload("res://scripts/cafe_startup_readiness.gd")
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
	game = Main.new();game.process_mode = Node.PROCESS_MODE_DISABLED;root.add_child(game)
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
