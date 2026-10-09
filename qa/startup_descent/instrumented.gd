extends "res://scripts/main.gd"
## Diagnostic-only wrappers; bounded numeric buffers, no bridge/log in frame loops.
const SOURCE_COMMIT = "@SOURCE_COMMIT@"
const SOURCE_TREE = "@SOURCE_TREE@"
const OVERLAY_ID = "@OVERLAY_ID@"
const CAPACITY = 8192
const WIDTH = 10
var _probe_process = PackedInt64Array()
var _probe_draw = PackedFloat64Array()
var _probe_process_count = 0
var _probe_draw_count = 0
var _probe_overflow = false
var _probe_running = true
var _probe_callback
var _probe_ready_begin = 0
var _probe_ready_end = 0

func _init():
	_probe_process.resize(CAPACITY * 3)
	_probe_draw.resize(CAPACITY * WIDTH)

func _ready():
	_probe_ready_begin = Time.get_ticks_usec()
	RenderingServer.frame_post_draw.connect(_probe_after_draw)
	super()
	_probe_ready_end = Time.get_ticks_usec()
	if OS.has_feature("web"):
		_probe_callback = JavaScriptBridge.create_callback(_probe_collect)
		JavaScriptBridge.get_interface("window").__littleLeafDescentCollect = _probe_callback

func _process(delta):
	if not _probe_running:
		super(delta)
		return
	var begin = Time.get_ticks_usec()
	super(delta)
	var end = Time.get_ticks_usec()
	if _probe_process_count >= CAPACITY:
		_probe_overflow = true
		return
	var i = _probe_process_count * 3
	_probe_process[i] = Engine.get_process_frames()
	_probe_process[i+1] = begin
	_probe_process[i+2] = end
	_probe_process_count += 1

func _probe_after_draw():
	if not _probe_running:return
	if _probe_draw_count >= CAPACITY:
		_probe_overflow = true
		return
	var i = _probe_draw_count * WIDTH
	_probe_draw[i] = Engine.get_process_frames()
	_probe_draw[i+1] = Time.get_ticks_usec()
	_probe_draw[i+2] = float(cafe_intro.active)
	_probe_draw[i+3] = cafe_intro.elapsed
	_probe_draw[i+4] = cafe_intro.hud_alpha
	_probe_draw[i+5] = float(cafe_intro.get("preparing") == true)
	_probe_draw[i+6] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_probe_draw[i+7] = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_probe_draw[i+8] = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_probe_draw[i+9] = Performance.get_monitor(Performance.TIME_PROCESS)
	_probe_draw_count += 1

func _probe_collect(_args = []):
	if not _probe_running:return
	_probe_running = false
	RenderingServer.frame_post_draw.disconnect(_probe_after_draw)
	var processes = []
	for n in _probe_process_count:
		processes.append([_probe_process[n*3],_probe_process[n*3+1],_probe_process[n*3+2]])
	var draws = []
	for n in _probe_draw_count:
		var row = []
		for j in WIDTH:row.append(_probe_draw[n*WIDTH+j])
		draws.append(row)
	var packet = {"schema_version":1,"kind":"little-leaf-descent-frames","diagnostic_only":true,"release_qualified":false,
		"source_commit":SOURCE_COMMIT,"source_tree":SOURCE_TREE,"overlay_id":OVERLAY_ID,
		"ready_begin_us":_probe_ready_begin,"ready_end_us":_probe_ready_end,
		"process_columns":["engine_frame","begin_us","end_us"],"processes":processes,
		"draw_columns":["engine_frame","post_draw_us","intro_active","intro_elapsed_s","hud_alpha","preparing","reported_draw_calls","reported_primitives","reported_objects","reported_process_s"],"draws":draws,
		"overflow":_probe_overflow,"fresh_start":fresh_start,"web_runtime":OS.has_feature("web"),
		"renderer_measured":DisplayServer.get_name() != "headless","scope":"Main._process wall time excludes child callbacks. Render counters are engine-reported at post-draw, not GPU timings. Post-draw is not presentation or GPU completion. No cross-clock subtraction."}
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__littleLeafStartupPhasePacket="+JSON.stringify(packet)+";")
	else:print("DESCENT_PACKET ",JSON.stringify(packet))
