extends Node
## Temporary autoload for a disposable native-only diagnostic. Not a presentation clock.
const LIMIT := 8192
const STRIDE := 4
const CAPPED_US := 12000000
const UNCAPPED_US := 6000000
var _stamps := PackedInt64Array()
var _rows := PackedInt64Array()
var _count := 0
var _row_count := 0
var _lost := 0
var _faults := 0
var _mode := 0
var _main_thread := 0
var _last_post := 0
var _process_us := 0
var _pre_us := 0
var _guest_id := -1

func _ready() -> void:
	if not "--diagnostic-active-service" in OS.get_cmdline_user_args():
		return
	if OS.get_environment("LL_CADENCE_RAW").is_empty() or DisplayServer.get_name() != "X11" or OS.has_feature("web"):
		get_tree().quit(2)
		return
	_main_thread = OS.get_main_thread_id()
	_stamps.resize(LIMIT)
	RenderingServer.frame_post_draw.connect(_post_draw)
	_wait_for_active_cooking()

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
				_guest_id = int(guest.id)
				await _measure()
				return
	get_tree().quit(4)

func _state() -> Dictionary:
	var game := get_tree().current_scene
	var tracked_phase := "absent"
	var tracked_seated := false
	for guest in game.model.customers:
		if int(guest.id) == _guest_id:
			tracked_phase = str(guest.phase)
			tracked_seated = bool(guest.seated)
			break
	return {"open": game.model.operating_open, "served": game.model.served,
		"items": game.model.items.size(), "guests": game.model.customers.size(),
		"walls": game.model.built_walls.size(), "openings": game.model.wall_attachments.size(),
		"tracked_guest_id": _guest_id, "tracked_phase": tracked_phase, "tracked_seated": tracked_seated,
		"paused": game.paused, "editing": game.editing, "recovery_blocked": game.save_recovery_blocked,
		"intro_active": game.cafe_intro != null and game.cafe_intro.active}

func _capture(mode: int, duration: int) -> Dictionary:
	_count = 0
	_row_count = 0
	_lost = 0
	_faults = 0
	_last_post = 0
	_process_us = 0
	_pre_us = 0
	var cap := Engine.max_fps
	var before := _state()
	var start := Time.get_ticks_usec()
	_mode = mode
	while Time.get_ticks_usec() < start + duration:
		var remaining := float(start + duration - Time.get_ticks_usec()) / 1000000.0
		await get_tree().create_timer(maxf(remaining, 0.000001), true, false, true).timeout
	var end := Time.get_ticks_usec()
	_mode = 0
	var result := {"cap": cap, "cap_at_end": Engine.max_fps, "start_us": start, "end_us": end,
		"lost": _lost, "stamps_us": Array(_stamps.slice(0, _count)),
		"state_start": before, "state_end": _state(), "boundary_faults": _faults}
	if mode == 2:
		result["boundary_rows_us"] = Array(_rows.slice(0, _row_count * STRIDE))
	return result

func _measure() -> void:
	var original_cap := Engine.max_fps
	if original_cap != 60:
		get_tree().quit(5)
		return
	var environment := {"engine": Engine.get_version_info(),
		"display_server": DisplayServer.get_name(), "window": str(DisplayServer.window_get_size()),
		"refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"video_vendor": RenderingServer.get_video_adapter_vendor(),
		"video_api": RenderingServer.get_video_adapter_api_version(),
		"vsync_mode": DisplayServer.window_get_vsync_mode()}
	var capped := await _capture(1, CAPPED_US)
	# Persist the completed primary window OUTSIDE its timer and before resetting
	# the cap. A later diagnostic failure must not lose the only primary sample.
	var checkpoint := FileAccess.open(OS.get_environment("LL_CADENCE_RAW") + ".capped", FileAccess.WRITE)
	if checkpoint == null:
		get_tree().quit(3)
		return
	checkpoint.store_string(JSON.stringify({"schema":"little-leaf-current-native-cadence-v1","scenario":"active-first-cooking",
		"environment":environment,"capped":capped,"uncapped":null,"uncapped_status":"checkpoint_only","restored_cap":null}))
	checkpoint.close()
	var uncapped: Variant = null
	var uncapped_status := "skipped_scene_changed"
	if capped["state_start"] == capped["state_end"] and capped["cap_at_end"] == original_cap:
		_rows.resize(LIMIT * STRIDE)
		get_tree().process_frame.connect(_process_boundary)
		RenderingServer.frame_pre_draw.connect(_pre_draw)
		Engine.max_fps = 0
		await get_tree().create_timer(0.5, true, false, true).timeout
		if _state() == capped["state_start"] and Engine.max_fps == 0:
			uncapped = await _capture(2, UNCAPPED_US)
			uncapped_status = "captured"
		else:
			uncapped_status = "skipped_warmup_changed"
		Engine.max_fps = original_cap
		get_tree().process_frame.disconnect(_process_boundary)
		RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	var result := {"schema": "little-leaf-current-native-cadence-v1", "scenario": "active-first-cooking",
		"environment": environment, "capped": capped, "uncapped": uncapped,
		"uncapped_status": uncapped_status, "restored_cap": Engine.max_fps}
	var file := FileAccess.open(OS.get_environment("LL_CADENCE_RAW"), FileAccess.WRITE)
	if file == null:
		get_tree().quit(3)
		return
	file.store_string(JSON.stringify(result))
	file.close()
	get_tree().quit()

func _process_boundary() -> void:
	if _mode != 2:
		return
	if OS.get_thread_caller_id() != _main_thread or _process_us != 0 or _pre_us != 0:
		_faults += 1
		return
	_process_us = Time.get_ticks_usec()

func _pre_draw() -> void:
	if _mode != 2:
		return
	if OS.get_thread_caller_id() != _main_thread or _pre_us != 0 or (_process_us == 0 and _last_post != 0):
		_faults += 1
		return
	_pre_us = Time.get_ticks_usec()

func _post_draw() -> void:
	if _mode == 0:
		return
	var now := Time.get_ticks_usec()
	if OS.get_thread_caller_id() != _main_thread:
		_faults += 1
		return
	if _count >= LIMIT:
		_lost += 1
		return
	_stamps[_count] = now
	_count += 1
	if _mode != 2:
		return
	# Discard the partial leading interval. Tail has no terminating post.
	if _last_post != 0:
		if _last_post < _process_us and _process_us < _pre_us and _pre_us < now:
			var index := _row_count * STRIDE
			_rows[index] = _last_post
			_rows[index + 1] = _process_us
			_rows[index + 2] = _pre_us
			_rows[index + 3] = now
			_row_count += 1
		else:
			_faults += 1
	_last_post = now
	_process_us = 0
	_pre_us = 0
