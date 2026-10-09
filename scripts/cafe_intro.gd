extends CanvasLayer
## Startup presentation only. Never writes camera, save, pause or audio state.
const DURATION = 6.5
const DESCENT_START = 1.0
static var shown_this_session = false
var game
var active = false
var preparing = false
var finish_after_preparation = false
var discard_preparation_delta = false
var elapsed = 0.0
var descent = 0.0
var sky_alpha = 1.0
var held = {}
var hud_colors = {}
var hud_alpha = 1.0
var cover: Control
var content_group: Control
var title: TextureRect
var welcome: Label
var title_group: Control
const TITLE_TEXTURE = preload("res://assets/branding/little_leaf_approved_v3.png")
const TITLE_ASPECT = 783.0 / 518.0
var hint: Label

func start(owner_game):
	game = owner_game
	layer = 100
	game.add_child(self)
	if shown_this_session or "--skip-intro" in OS.get_cmdline_user_args() or game.save_recovery_blocked or game.startup_notice != "":
		return
	shown_this_session = true
	active = true
	for control in game.ui.get_children():
		if control is CanvasItem:hud_colors[control] = control.modulate
	cover = Control.new()
	content_group = Control.new()
	title_group = Control.new()
	title = TextureRect.new()
	welcome = Label.new()
	hint = Label.new()
	add_child(cover)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.draw.connect(_draw_sky)
	cover.add_child(content_group)
	content_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_group.add_child(title_group)
	title_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Artwork and live copy share one fade; the sky keeps its own timeline.
	title.texture = TITLE_TEXTURE
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_group.add_child(title)
	for label in [welcome, hint]:
		(title_group if label == welcome else content_group).add_child(label)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", game.compact_ui.hud.font_bold)
		label.add_theme_color_override("font_color", Color("735f43"))
	welcome.text = "Welcome to"
	hint.text = "Tap or press any key to skip"
	_present()

func _process(delta):
	if not active or preparing:return
	if discard_preparation_delta:
		discard_preparation_delta = false
		return
	# A suspended tab or frame stall lands immediately instead of trapping input.
	if delta > 1.0 or game.editing or game.settings.visible:
		finish();return
	elapsed += maxf(delta, 0.0)
	descent = smoothstep(DESCENT_START, DURATION, elapsed)
	sky_alpha = 1.0 - smoothstep(1.4, 4.8, elapsed)
	_present()
	if elapsed >= DURATION:finish()

func motion_delta(delta: float) -> float:
	# The title hold is not play time. Only the current frame's descending
	# portion advances the world; there is no catch-up after a stall or tab hide.
	if preparing or discard_preparation_delta:return 0.0
	if not is_finite(delta) or delta <= 0.0 or delta > 1.0:return 0.0
	return clampf(elapsed + delta - DESCENT_START, 0.0, delta) if active else delta

func _present():
	var view = get_viewport().get_visible_rect().size
	cover.size = view
	content_group.size = view
	content_group.modulate.a = 1.0 - smoothstep(1.5, 3.9, elapsed)
	# Match the accepted portrait composition; cap by height for short landscapes.
	var width = minf(minf(view.x * 783.0 / 853.0, 620.0), view.y * .60 * TITLE_ASPECT)
	var art_size = Vector2(width, width / TITLE_ASPECT)
	title_group.position = Vector2((view.x - width) * .5, view.y * .428 - art_size.y * .5)
	title_group.size = art_size
	title.position = Vector2.ZERO
	title.size = art_size
	welcome.position = Vector2(-title_group.position.x, -18)
	welcome.size = Vector2(view.x, 34)
	welcome.add_theme_font_size_override("font_size", 18 if view.x < 700 else 24)
	hint.position = Vector2(16, view.y - 58)
	hint.size = Vector2(maxf(0, view.x - 32), 40)
	hint.add_theme_font_size_override("font_size", 12 if view.x < 700 else 14)
	_fade_hud(smoothstep(4.8, DURATION, elapsed))
	cover.queue_redraw()

func _draw_sky():
	var view = cover.size
	cover.draw_rect(Rect2(Vector2.ZERO, view), Color(.80, .89, .91, sky_alpha))
	# Soft procedural clouds; no external asset or video dependency.
	for spot in [Vector2(.16,.18), Vector2(.78,.23), Vector2(.60,.68)]:
		var center = spot * view - Vector2(0, descent * view.y * .35)
		for cloud in [Vector3(-26,4,23), Vector3(0,0,32), Vector3(30,6,25)]:
			cover.draw_circle(center + Vector2(cloud.x,cloud.y), cloud.z, Color(1,1,.98,sky_alpha*.42))

func render_offset(view: Vector2) -> Vector2:
	return Vector2(0, view.y * 1.35 * (1.0 - descent)) if active else Vector2.ZERO

func handle_input(event) -> bool:
	var token = ""
	var pressed = false
	if event is InputEventScreenTouch:
		token = "touch_%s" % event.index;pressed = event.pressed
	elif event is InputEventMouseButton:
		token = "mouse_%s" % event.button_index;pressed = event.pressed
	elif event is InputEventKey:
		token = "key_%s" % event.keycode;pressed = event.pressed
	elif event is InputEventJoypadButton:
		token = "pad_%s" % event.button_index;pressed = event.pressed
	if token != "" and held.has(token):
		if not pressed:held.erase(token)
		return true
	# Touch-to-mouse emulation belongs to the same skip gesture.
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION and held.has("touch_skip"):
		if not event.pressed:held.erase("touch_skip")
		return true
	if not active:return false
	if preparing:
		if token != "" and pressed:
			held[token] = true
			if event is InputEventScreenTouch:held["touch_skip"] = true
		return true
	if token != "" and pressed:
		held[token] = true
		if event is InputEventScreenTouch:held["touch_skip"] = true
		finish()
	return true

func finish():
	if not active:return
	if preparing:
		finish_after_preparation = true
		return
	active = false
	descent = 1.0
	cover.hide()
	_fade_hud(1.0)
	game.illustration.update_projection()
	game.illustration.queue_redraw()
	# Keep held releases owned until they arrive; a skip cannot click the cafe.

func _fade_hud(alpha: float):
	hud_alpha = alpha
	for control in hud_colors:
		if is_instance_valid(control):
			var color: Color = hud_colors[control]
			color.a *= alpha
			control.modulate = color
