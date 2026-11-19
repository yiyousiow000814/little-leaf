extends Node
## Diagnostic autoload in a disposable, immutable-source project copy only.
## Samples completed Godot viewport updates, not GPU/display presentation.
const LIMIT := 8192
const SAMPLE_MS := 12000
var _stamps := PackedInt64Array()
var _count := 0
var _missed := 0
var _started := 0
var _running := false
var _stage := "fresh-starter-manual"

func _ready() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	_stamps.resize(LIMIT)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	var args := OS.get_cmdline_user_args()
	if "--diagnostic-active-service" in args:
		_stage = "active-first-cooking"
		_wait_for_active_cooking()
	else:
		print("LL_DRAW_PROBE_READY manual F8 cue; isolated profile only")

func _input(event: InputEvent) -> void:
	if not _running and _stamps.size() == LIMIT and event is InputEventKey 			and event.pressed and not event.echo and event.physical_keycode == KEY_F8:
		if _stage == "fresh-starter-manual":
			_capture()

func _wait_for_active_cooking() -> void:
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.20, true, false, true).timeout
		var game := get_tree().current_scene
		if game == null or not "model" in game or game.model == null:
			continue
		if not game.model.operating_open or game.paused or game.editing or game.save_recovery_blocked:
			continue
		if game.cafe_intro != null and game.cafe_intro.active:
			continue
		for guest in game.model.customers:
			if guest.phase == "cooking" and guest.seated:
				await _capture()
				return
	push_error("LL probe did not naturally reach seated cooking; no result")
	get_tree().quit(4)

func _capture() -> void:
	_count = 0
	_missed = 0
	_started = Time.get_ticks_usec()
	_running = true
	# A wall-clock timer; no copy, JSON, GUI commands or log during measurement.
	await get_tree().create_timer(SAMPLE_MS / 1000.0, true, false, true).timeout
	var ended := Time.get_ticks_usec()
	_running = false
	var stamps := _stamps.slice(0, _count)
	var game := get_tree().current_scene
	var state := {}
	if game != null and "model" in game and game.model != null:
		state = {"open": game.model.operating_open, "served": game.model.served,
			"items": game.model.items.size(), "guests": game.model.customers.size()}
	var result := {"schema": "little-leaf-native-draw-diagnostic-v1",
		"scope": "Godot frame_post_draw, not physical presentations or busy time",
		"stage": _stage, "start_us": _started, "end_us": ended,
		"lost": _missed, "stamps_us": Array(stamps), "state_at_end": state,
		"engine": Engine.get_version_info(), "max_fps": Engine.max_fps,
		"display_server": DisplayServer.get_name(),
		"window": str(DisplayServer.window_get_size()),
		"refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"video_vendor": RenderingServer.get_video_adapter_vendor(),
		"video_api": RenderingServer.get_video_adapter_api_version(),
		"processor": OS.get_processor_name(), "platform": OS.get_name()}
	var file := FileAccess.open("user://diagnostic-native-draw.json", FileAccess.WRITE)
	if file == null:
		push_error("LL probe failed to save the isolated result")
		get_tree().quit(3)
		return
	file.store_string(JSON.stringify(result))
	file.close()
	print("LL_DRAW_PROBE_CAPTURED frames=", _count, " lost=", _missed)
	get_tree().quit(0 if _count > 0 and _missed == 0 else 2)

func _on_post_draw() -> void:
	if not _running:
		return
	if _count >= LIMIT:
		_missed += 1
		return
	_stamps[_count] = Time.get_ticks_usec()
	_count += 1
