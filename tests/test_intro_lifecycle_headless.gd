extends SceneTree
## Logic/projection checks only. Native rendering and real audio remain separate.
const Main = preload("res://scripts/main.gd")
const Intro = preload("res://scripts/cafe_intro.gd")
var checks = 0
var failures = []
var game
var view: SubViewport
var result_path = OS.get_environment("LL_INTRO_RESULT")
var minimum_landscape_size = Vector2i.ZERO

func _initialize(): run.call_deferred()

func check(ok, label):
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func fresh_intro():
	game.cafe_intro.finish()
	Intro.shown_this_session = false
	var intro = Intro.new()
	intro.start(game)
	game.cafe_intro = intro
	return intro

func visible_alpha(item: CanvasItem) -> float:
	if not item.is_visible_in_tree():return 0.0
	var alpha = item.self_modulate.a
	var ancestor = item
	while ancestor is CanvasItem:
		alpha *= ancestor.modulate.a
		ancestor = ancestor.get_parent()
	return alpha

func check_restored(intro, label):
	check(not intro.active and intro.hud_alpha == 1.0, label + " releases intro and HUD")
	check(not intro.cover.visible, label + " hides overlay")
	for item in [intro.title, intro.welcome, intro.hint]:
		check(visible_alpha(item) == 0.0, label + " hides artwork and both text lines")
	check(intro.render_offset(view.size) == Vector2.ZERO, label + " has no presentation offset")
	for control in intro.hud_colors:
		if is_instance_valid(control):
			check(control.modulate.is_equal_approx(intro.hud_colors[control]), label + " restores HUD child " + str(control.name))

func run():
	var data_root = OS.get_environment("XDG_DATA_HOME")
	check(not data_root.is_empty() and OS.get_user_data_dir().begins_with(data_root), "disposable save profile")
	check("--visual-qa" in OS.get_cmdline_user_args(), "save-writing suppression enabled")
	view = SubViewport.new()
	view.size = Vector2i(390, 844)
	view.disable_3d = true
	root.add_child(view)
	Intro.shown_this_session = false
	game = Main.new()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	view.add_child(game)
	await process_frame
	check(game.cafe_intro.active, "clean startup runs once")
	check(game.cafe_intro.title is TextureRect and game.cafe_intro.title.texture != null, "approved artwork is a live texture")
	check(game.cafe_intro.title.texture.get_size() == Vector2(783, 518), "approved transparent crop dimensions")
	check(game.cafe_intro.welcome.text == "Welcome to", "greeting remains independent live text")
	check(game.cafe_intro.hint.text == "Tap or press any key to skip", "skip instruction keeps English copy")
	var intro = game.cafe_intro
	var zoom = game.illustration.zoom
	var pan = game.illustration.pan_offset
	var audio = game.audio_players.duplicate()
	var paused = game.paused
	var music_enabled = game.music_enabled
	var coins = game.model.coins
	var save_timer = game.save_timer
	var animation_time = game.animation_time
	for i in range(13):
		game._process(.5)
		intro._process(.5)
		var time = (i + 1) * .5
		check(is_equal_approx(intro.elapsed, time), "timeline advances " + str(time))
		check(is_equal_approx(intro.descent, smoothstep(1.0, 6.5, time)), "original eased descent " + str(time))
		if time < 6.5:
			check(is_equal_approx(visible_alpha(intro.title), 1.0 - smoothstep(1.5, 3.9, time)), "original effective title fade " + str(time))
			check(is_equal_approx(intro.sky_alpha, 1.0 - smoothstep(1.4, 4.8, time)), "original sky fade " + str(time))
			check(is_equal_approx(intro.hud_alpha, smoothstep(4.8, 6.5, time)), "original HUD fade " + str(time))
	check_restored(intro, "natural 6.5 second completion")
	check(game.model.coins == coins and game.save_timer == save_timer and game.animation_time == animation_time, "intro suspends gameplay and autosave timing")
	check(game.illustration.zoom == zoom and game.illustration.pan_offset.is_equal_approx(pan), "natural completion preserves camera")
	check(game.audio_players == audio and game.music_enabled == music_enabled and game.paused == paused, "natural completion preserves audio identity and user flags")
	var repeat = Intro.new()
	repeat.start(game)
	check(not repeat.active and repeat.cover == null, "same-session recreation does not replay")

	# Sample the entire reveal at 60 fps. Compare effective inherited opacity,
	# so a sibling hint with a delayed fade or a doubled child fade fails here.
	intro = fresh_intro()
	check(visible_alpha(intro.title) == 1.0 and visible_alpha(intro.hint) == 1.0, "intro artwork and hint start fully visible")
	for frame in range(391):
		intro._process(1.0 / 60.0)
		var title_alpha = visible_alpha(intro.title)
		check(is_equal_approx(visible_alpha(intro.welcome), title_alpha), "greeting shares title fade at frame " + str(frame))
		check(is_equal_approx(visible_alpha(intro.hint), title_alpha), "skip hint shares title fade at frame " + str(frame))
		if intro.elapsed >= 3.9:
			check(is_zero_approx(title_alpha) and is_zero_approx(visible_alpha(intro.hint)), "no lingering text after title fade at frame " + str(frame))
	check_restored(intro, "60 fps natural completion")

	for kind in ["mouse", "touch", "key", "joypad"]:
		intro = fresh_intro()
		var event
		if kind == "mouse":
			event = InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT
		elif kind == "touch":
			event = InputEventScreenTouch.new(); event.index = 1
		elif kind == "key":
			event = InputEventKey.new(); event.keycode = KEY_F10
		else:
			event = InputEventJoypadButton.new(); event.button_index = JOY_BUTTON_A
		event.pressed = true
		check(intro.handle_input(event), kind + " skip press owned")
		check_restored(intro, kind + " skip")
		check(intro.handle_input(event), kind + " held/repeat press owned")
		event.pressed = false
		check(intro.handle_input(event), kind + " skip release owned")
		check(not intro.handle_input(event), kind + " next independent event released")
		if kind == "touch":
			var emulated = InputEventMouseButton.new()
			emulated.device = InputEvent.DEVICE_ID_EMULATION
			emulated.button_index = MOUSE_BUTTON_LEFT
			emulated.pressed = true
			check(intro.handle_input(emulated), "touch emulated mouse press owned")
			emulated.pressed = false
			check(intro.handle_input(emulated), "touch emulated mouse release owned")
			check(not intro.handle_input(emulated), "later emulated pointer free")

	for kind in ["focus", "stall", "settings", "decorate"]:
		intro = fresh_intro()
		if kind == "focus": game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		elif kind == "stall": intro._process(1.01)
		elif kind == "settings":
			game.settings.show(); intro._process(.01); game.settings.hide()
		else:
			game._toggle_edit(); intro._process(.01); game._toggle_edit()
		check_restored(intro, kind + " interruption")
		check(game.paused == paused and game.music_enabled == music_enabled and game.audio_players == audio, kind + " preserves user state/audio")
		check(game.illustration.zoom == zoom and game.illustration.pan_offset.is_equal_approx(pan), kind + " preserves camera")
	check(not game.cafe_intro.active and Intro.shown_this_session, "decorate close does not restart intro")

	for dimensions in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(1360, 880), Vector2i(320, 568), Vector2i(568, 320)]:
		view.size = dimensions
		await process_frame
		game._sync_window_scale()
		game.illustration.update_projection()
		var gameplay_origin = game.illustration.origin
		var cell = Vector2i(4, 4)
		var projected = game.illustration.iso(cell.x + .5, cell.y + .5)
		intro = fresh_intro()
		intro._process(.5)
		check(intro.cover.size == Vector2(dimensions), "resize sky matches " + str(dimensions))
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(intro.title_group.get_rect()), "title artwork fits " + str(dimensions))
		check(is_equal_approx(intro.title.size.x / intro.title.size.y, 783.0 / 518.0), "title aspect preserved " + str(dimensions))
		check(intro.title_group.position.y + intro.welcome.position.y >= 10, "greeting safe margin " + str(dimensions))
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(Rect2(intro.title_group.position + intro.welcome.position, intro.welcome.size)), "greeting full bounds fit " + str(dimensions))
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(intro.hint.get_rect()), "skip hint full bounds fit " + str(dimensions))
		if dimensions == Vector2i(390, 844):
			check(absf(intro.title_group.position.y + intro.welcome.position.y - 224.65) < 1.0, "portrait greeting matches accepted native label position")
		check(intro.title_group.get_rect().end.y < intro.hint.position.y - 16, "title clears skip hint " + str(dimensions))
		check(intro.title_group.mouse_filter == Control.MOUSE_FILTER_IGNORE and intro.title.mouse_filter == Control.MOUSE_FILTER_IGNORE, "artwork never steals pointer input " + str(dimensions))
		check(intro.hint.position.y + intro.hint.size.y <= dimensions.y, "resize skip hint on screen " + str(dimensions))
		check(game.illustration.origin.is_equal_approx(gameplay_origin), "presentation does not change gameplay projection " + str(dimensions))
		check(game.illustration.screen_to_cell(projected) == cell, "input projection keeps cell " + str(dimensions))
		intro.finish()
		check(game.illustration.origin.is_equal_approx(gameplay_origin), "finish restores resize projection " + str(dimensions))
		check(game.illustration.screen_to_cell(projected) == cell, "finished projection keeps cell " + str(dimensions))


	# Exercise the current HUD's actual minimum landscape budget, not an assumed size.
	view.size = Vector2i(568, 320)
	for settle_step in range(3):
		await process_frame
		game._sync_window_scale()
		var hud = game.compact_ui.hud
		var minimum = preload("res://scripts/cafe_viewport_layout.gd").minimum_size(hud.layout_host.get_global_rect().end.y, hud._safe_insets(), Vector2(view.size))
		minimum_landscape_size = Vector2i(568, int(ceil(minimum.y)))
		view.size = minimum_landscape_size
	await process_frame
	game._sync_window_scale()
	intro = fresh_intro()
	intro._process(.5)
	check(not game.compact_ui.viewport_too_small, "minimum landscape supports the current HUD budget")
	check(Rect2(Vector2.ZERO, Vector2(view.size)).encloses(intro.title_group.get_rect()), "minimum landscape title visible")
	check(Rect2(Vector2.ZERO, Vector2(view.size)).encloses(Rect2(intro.title_group.position + intro.welcome.position, intro.welcome.size)), "minimum landscape greeting visible")
	check(Rect2(Vector2.ZERO, Vector2(view.size)).encloses(intro.hint.get_rect()), "minimum landscape skip visible")
	check(intro.title_group.position.y + intro.welcome.position.y >= 10, "minimum landscape greeting safe margin")
	check(intro.title_group.get_rect().end.y < intro.hint.position.y - 16, "minimum landscape title clears skip hint")
	intro.finish()

	for reason in ["recovery", "notice"]:
		Intro.shown_this_session = false
		game.save_recovery_blocked = reason == "recovery"
		game.startup_notice = "Preserved startup notice" if reason == "notice" else ""
		var blocked = Intro.new(); blocked.start(game)
		check(not blocked.active and blocked.cover == null and blocked.hud_colors.is_empty(), reason + " keeps startup unobscured")
		check(not Intro.shown_this_session, reason + " bypass does not consume once flag")
	game.save_recovery_blocked = false; game.startup_notice = ""
	game.paused = true; game.music_enabled = false
	intro = fresh_intro()
	for i in range(13): intro._process(.5)
	check_restored(intro, "paused muted completion")
	check(game.paused and not game.music_enabled and game.audio_players == audio, "paused/muted preference retained")
	var result = {"checks": checks, "failures": failures, "mode": "headless logic only", "base": "2a0ff543cf4f81207bad1eb843130c832b0f6327", "save_dir": OS.get_user_data_dir(), "native_render_verified": false, "minimum_landscape_viewport": [minimum_landscape_size.x, minimum_landscape_size.y]}
	print("INTRO_LIFECYCLE_RESULT ", JSON.stringify(result))
	if not result_path.is_empty():
		var output = FileAccess.open(result_path, FileAccess.WRITE)
		output.store_string(JSON.stringify(result, "\t")); output.close()
	if game.music_tween != null: game.music_tween.kill()
	for player in game.audio_players.values():
		player.stop(); player.stream = null
	await create_timer(.3).timeout
	view.queue_free()
	await process_frame; await process_frame
	quit(0 if failures.is_empty() else 1)
