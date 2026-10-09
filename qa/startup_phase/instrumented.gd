extends "res://scripts/main.gd"
## Test-only overlay. Never change startup/save branches or replace production work.
const PHASE_SOURCE_COMMIT = "@SOURCE_COMMIT@"
const PHASE_SOURCE_TREE = "@SOURCE_TREE@"
const PHASE_OVERLAY_ID = "@OVERLAY_ID@"
const PHASE_NAMES = ["_ready", "_load_startup", "_setup_world", "_build_ui", "_setup_music", "_rebuild_room", "_rebuild_furniture", "_restore_service_runtime"]
const PHASE_CAPACITY = 128
# Allocated before _ready, so this overhead is explicitly outside ready_total_us.
var _phase_ticks = PackedInt64Array()
var _phase_codes = PackedInt32Array()
var _phase_count = 0
var _phase_overflow = false
var _phase_active = false
var _phase_emitted = false
var _phase_first_draw_us = -1

func _init():
	_phase_ticks.resize(PHASE_CAPACITY)
	_phase_codes.resize(PHASE_CAPACITY)

func _phase_mark(code: int):
	if not _phase_active:
		return
	var now = Time.get_ticks_usec()
	if _phase_count == PHASE_CAPACITY:
		_phase_overflow = true
		return
	_phase_ticks[_phase_count] = now
	_phase_codes[_phase_count] = code
	_phase_count += 1

func _ready():
	_phase_active = true
	_phase_mark(0)
	# Register before super so this timestamp precedes the ordinary Web notification.
	RenderingServer.frame_post_draw.connect(_phase_after_first_draw, CONNECT_ONE_SHOT)
	super()
	_phase_mark(1)
	_phase_active = false

func _load_startup():
	_phase_mark(2)
	super()
	_phase_mark(3)

func _setup_world():
	_phase_mark(4)
	super()
	_phase_mark(5)

func _build_ui():
	_phase_mark(6)
	super()
	_phase_mark(7)

func _setup_music():
	_phase_mark(8)
	super()
	_phase_mark(9)

func _rebuild_room():
	_phase_mark(10)
	super()
	_phase_mark(11)

func _rebuild_furniture():
	_phase_mark(12)
	super()
	_phase_mark(13)

func _restore_service_runtime():
	_phase_mark(14)
	super()
	_phase_mark(15)

func _phase_after_first_draw():
	_phase_first_draw_us = Time.get_ticks_usec()
	_phase_emit.call_deferred()

func _phase_emit():
	if _phase_emitted:
		return
	_phase_emitted = true
	var emit_started_us = Time.get_ticks_usec()
	var marks = []
	for index in _phase_count:
		var code = _phase_codes[index]
		marks.append({"method": PHASE_NAMES[code / 2], "boundary": "begin" if code % 2 == 0 else "end", "ticks_us": _phase_ticks[index]})
	var packet = {
		"schema_version": 1,
		"kind": "little-leaf-startup-phases",
		"diagnostic_only": true,
		"release_qualified": false,
		"mode": "instrumented",
		"source_commit": PHASE_SOURCE_COMMIT,
		"source_tree": PHASE_SOURCE_TREE,
		"overlay_id": PHASE_OVERLAY_ID,
		"clock": "Godot.Time.get_ticks_usec",
		"clock_origin": "engine_monotonic_timer_origin_not_browser_navigation",
		"marks": marks,
		"buffer_overflow": _phase_overflow,
		"first_post_draw_ticks_us": _phase_first_draw_us,
		"emit_started_ticks_us": emit_started_us,
		"web_runtime": OS.has_feature("web"),
		"renderer_measured": DisplayServer.get_name() != "headless",
		"display": DisplayServer.get_name(),
		"engine_version": Engine.get_version_info().string,
		"fresh_start": fresh_start,
		"save_recovery_blocked": save_recovery_blocked,
		"web_save_ready": web_save != null and web_save.ready,
		"scope": "Real inherited startup; inclusive method spans; first post-draw signal, not presentation or GPU completion. No WASM/GDScript attribution."
	}
	# The only diagnostic bridge/log write happens after first draw, once.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__littleLeafStartupPhasePacket=" + JSON.stringify(packet) + ";")
	else:
		print("STARTUP_PHASE_PACKET ", JSON.stringify(packet))
