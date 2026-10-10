extends CanvasLayer
## Keep first-use atlas/HUD work behind the opaque opening presentation.
## No save/account/audio changes; terminal failures use original geometry.
const MAX_WAIT_MS = 8000
var game
var atlases: Array = []
var started_ms = 0
var draws = 0
var terminal_draws = 0
var finishing = false
var completed = false
var timed_out = false
var cover: ColorRect
var label: Label
var ready_count = 0
var terminal_count = 0

func start(owner):
	game = owner
	layer = 110
	game.add_child(self)
	atlases = [game.illustration.furniture_art.static_atlas,game.illustration.head_atlas,game.illustration.moving_atlas]
	started_ms = Time.get_ticks_msec()
	game.cafe_intro.preparing = true
	# Ordinary HUD opacity compiles/draws its real materials while fully covered.
	game.cafe_intro._fade_hud(1.0)
	cover = ColorRect.new();cover.color = Color(.80,.89,.91,1)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP;add_child(cover)
	var logo = TextureRect.new();logo.texture = game.cafe_intro.TITLE_TEXTURE
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE;logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE;logo.name = "Brand";cover.add_child(logo)
	label = Label.new();label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font",game.compact_ui.hud.font_bold)
	label.add_theme_color_override("font_color",Color("735f43"));cover.add_child(label)
	_connect_draw()
	_update_status()

func _connect_draw():
	RenderingServer.frame_post_draw.connect(_after_draw)

func _exit_tree():
	if RenderingServer.frame_post_draw.is_connected(_after_draw):RenderingServer.frame_post_draw.disconnect(_after_draw)

func _check_recovery():
	# Preparation must not hide an ownership/account change from native recovery.
	if game.web_save != null:game.web_save.check_runtime_recovery()
	if not game.save_recovery_blocked:return
	game.cafe_intro.finish_after_preparation = true
	for atlas in atlases:
		if atlas.state in ["cold","warming"]:atlas.cancel_prepare("Startup preparation interrupted by save recovery")

func _process(_delta):
	if completed:return
	_check_recovery()
	if finishing:return
	if Time.get_ticks_msec() - started_ms >= MAX_WAIT_MS:
		timed_out = true
		for atlas in atlases:
			if atlas.state in ["cold","warming"]:atlas.cancel_prepare("Startup preparation timed out")
	_update_status()

func _update_status():
	ready_count = 0;terminal_count = 0
	for atlas in atlases:
		if atlas.is_ready():ready_count += 1
		if atlas.state not in ["cold","warming"]:terminal_count += 1
	var view = get_viewport().get_visible_rect().size
	cover.size = view
	var logo = cover.get_node("Brand")
	logo.size = Vector2(minf(view.x*.72,480),minf(view.y*.45,320))
	logo.position = (view-logo.size)*.5-Vector2(0,28)
	label.position = Vector2(8,logo.position.y+logo.size.y+12)
	label.size = Vector2(maxf(view.x-16,0),40)
	label.text = "Preparing café art · %d/%d ready" % [ready_count,atlases.size()]
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.LittleLeafBoot&&LittleLeafBoot.artWarmup)LittleLeafBoot.artWarmup(%d,%d);" % [ready_count,atlases.size()])

func _after_draw():
	if completed or finishing:return
	draws += 1
	# Status was sampled before this draw. Frames while any atlas was still
	# warming do not count toward drawing the final uploaded texture set.
	if terminal_count == atlases.size():terminal_draws += 1
	else:terminal_draws = 0
	if terminal_draws >= 2:
		finishing = true
		_finish.call_deferred()

func _finish():
	if completed:return
	# Authority may change after terminal draw scheduling but before this callback.
	_check_recovery()
	_update_status()
	completed = true
	game.startup_preparation_report = {"duration_ms":Time.get_ticks_msec()-started_ms,"ready":ready_count,"terminal":terminal_count,"fallback":terminal_count-ready_count,"timed_out":timed_out,"draws":draws,"terminal_draws":terminal_draws}
	var intro = game.cafe_intro
	intro.preparing = false
	if intro.finish_after_preparation:intro.finish()
	else:
		intro._fade_hud(0.0)
		intro.discard_preparation_delta = true
	if game.save_recovery_blocked:game.compact_ui.show_help()
	game._resume_frame = Engine.get_process_frames()+1
	# Reveal only after an actual welcome frame, never the loading/HUD warm-up.
	if OS.has_feature("web"):
		RenderingServer.frame_post_draw.connect(game._notify_first_web_frame,CONNECT_ONE_SHOT)
	queue_free()
