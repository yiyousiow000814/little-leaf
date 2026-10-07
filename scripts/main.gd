extends Node3D
const SaveLog=preload("res://scripts/cafe_save_log.gd")
const Money=preload("res://scripts/cafe_money.gd")

const ArtFont = preload("res://assets/fonts/NotoSans-Regular.ttf")
const Illustration = preload("res://scripts/illustrated_cafe.gd")
const Model = preload("res://scripts/cafe_model.gd")
const MinimalStart = preload("res://scripts/minimal_start.gd")
const Interaction = preload("res://scripts/cafe_interaction.gd")
const CameraGestures = preload("res://scripts/cafe_camera_gestures.gd")
var camera_gestures
const WebLifecycle = preload("res://scripts/cafe_web_lifecycle.gd")
const WebSave = preload("res://scripts/cafe_web_save.gd")
var web_lifecycle
var web_save
const BuildTools = preload("res://scripts/cafe_build_tools.gd")
const SettingsControls = preload("res://scripts/cafe_settings.gd")
const SaveProfiles = preload("res://scripts/cafe_save_profiles.gd")
const FloorTasks = preload("res://scripts/cafe_floor_tasks.gd")
const Dishwashing = preload("res://scripts/cafe_dishwashing.gd")
const CompactUI = preload("res://scripts/cafe_compact_ui.gd")
var compact_ui
const SaveContract=preload("res://scripts/cafe_save_contract.gd")
const Checkout=preload("res://scripts/cafe_checkout.gd")
const SAVE_FILE = SaveContract.PRIMARY_FILE
const RECENT_SAVE_FILE = "user://little_leaf_illustrated_r9.json"
const LEGACY_SAVE_FILE = "user://little_leaf_illustrated_r7.json"
const OLDER_SAVE_FILE = "user://little_leaf_illustrated_r6.json"
const OLDEST_SAVE_FILE = "user://little_leaf_illustrated_r5.json"
const HISTORICAL_SAVE_FILE = "user://little_leaf_illustrated_r4.json"
const CREAM = Color("f6f0dc")
const SAGE = Color("72896b")
const DARK = Color("29473c")
const WOOD = Color("b88c53")
var model = Model.new()
var world = Node3D.new()
var furnishings = Node3D.new()
var people = Node3D.new()
var camera = Camera3D.new()
var ui = CanvasLayer.new()
var tray: PanelContainer
var top_text: Label
var state_badge: Label
var tool_text: Label
var business_button: Button
var catalog_prices={}
var catalog_cards={}
var category_buttons={}
var catalog_category="Tables"
var build_panel:Control
var build_tools
var catalog_scroll:ScrollContainer
var startup_save_source=""
var fresh_start=false
var startup_notice=""
var edit_button: Button
var expand_button: Button
var pause_button: Button
var settings: PanelContainer
var selected_kind = ""
var selected_id = -1
var rotation_step = 0
var editing = false
var paused = false
var platform_music
var platform_autosave_dirty=false
var platform_dirty_generation=0
var speed = 1.0
var ghost: Node3D
var hover_cell = Vector2i(-100,-100)
var save_timer = 0.0
var progress_unsaved = false
var progress_save_error = ""
var save_recovery_blocked = false
var save_writes_suppressed = false
var visual_timer = 0.0
var material_cache = {}
var item_nodes = {}
var actor_nodes = {}
var loading = false
var staff_states = []
# Runtime-only service ledger. No decorative loops: every job belongs to a live
# model guest, and each bounded action must reach its real furnishing first.
var service_guests = {}
var floor_tasks=FloorTasks.new(self)
var dishwashing=Dishwashing.new(self)
var service_serial = 0
var active_staff_passages = {}
var static_service_paths = {}
var static_service_revision = -1
const SERVICE_STEPS = {
	"take_payment": [{"kind":"register","action":"taking_payment","seconds":Checkout.PAYMENT_SECONDS}],
	"floor": FloorTasks.STEPS,
	"wash": Dishwashing.STEPS,
	"order": [{"kind":"table","action":"taking_order","seconds":Model.ORDER_TAKING_SECONDS}],
	"cook": [{"kind":"stove","action":"preparing_food","seconds":1.5},{"kind":"stove","action":"cooking","seconds":Model.BASE_COOK_SECONDS},{"kind":"stove","action":"plating","seconds":1.5},{"kind":"counter","action":"placing_plate","seconds":.8}],
	"brew": [{"kind":"beverage","action":"preparing_drink","seconds":3.5},{"kind":"beverage","action":"collecting_drink","seconds":.7},{"kind":"table","action":"serving","seconds":.8}],
	"deliver_meal": [{"kind":"counter","action":"collecting_plate","seconds":.7},{"kind":"table","action":"serving","seconds":.8}],
	"deliver_drink": [{"kind":"beverage","action":"collecting_drink","seconds":.7},{"kind":"table","action":"serving","seconds":.8}],
	"cleanup": [{"kind":"table","action":"collecting","seconds":.75},{"kind":"sink","action":"dropping_dishes","seconds":Dishwashing.DROP_SECONDS},{"kind":"table","action":"wiping","seconds":1.2},{"kind":"table","action":"sweeping","debris_kind":"banana","seconds":.85},{"kind":"table","action":"sweeping","debris_kind":"crumbs","seconds":1.25},{"kind":"bin","action":"disposing_trash","seconds":.9},{"kind":"table","action":"mopping","seconds":1.5}]
}
const ROLE_JOBS={"chef":["cook"],"waiter":["order","deliver_meal","brew","deliver_drink","cleanup"],"cleaner":["cleanup"],"cashier":["take_payment"]}
const MEAL_IMPATIENCE_SECONDS=70.0
const MEAL_DEPARTURE_SECONDS=120.0
var idle_home_revision=-1
var idle_home_count=-1

var service_props = {}
var animation_time = 0.0
var wall_detail = false
var audio_players = {}
var music_state = ""
var music_age = 0.0
var music_enabled = true
var music_toggle: Button
var detail_stats: Label
var music_tween: Tween
var cafe_intro
var illustration: Node2D
var interaction
var workface_guidance
var settings_controls
var responsive_view=Vector2(-1,-1)

func _ready():
	_sync_window_scale()
	get_window().size_changed.connect(_sync_window_scale)
	get_tree().auto_accept_quit=false
	get_window().close_requested.connect(_on_window_close)
	# Keep the hidden legacy 3D scene out of the illustrated game's renderer.
	# Matched native profiling verified the empty camera/MSAA pass was costly.
	get_viewport().disable_3d=true
	if not "--visual-qa" in OS.get_cmdline_user_args():
		DisplayServer.window_set_title("Little Leaf Cafe · "+str(ProjectSettings.get_setting("application/config/version","R7 review")))
	_load_startup()
	_setup_world()
	build_tools=BuildTools.new(self)
	_build_ui()
	if OS.has_feature("crazygames"):
		platform_music=preload("res://scripts/crazygames_music.gd").new(self)
		_mark_platform_dirty()
	else:_setup_music()
	settings_controls.setup_audio()
	_connect_model_events()
	_rebuild_room()
	_rebuild_furniture()
	illustration=Illustration.new()
	illustration.game=self
	add_child(illustration)
	if fresh_start:illustration.focus_fresh_start()
	interaction=Interaction.new(self)
	camera_gestures=CameraGestures.new(self)
	web_lifecycle=WebLifecycle.new(self)
	workface_guidance=load("res://scripts/cafe_workface_guidance.gd").new();workface_guidance.game=self;workface_guidance.z_index=5;add_child(workface_guidance)
	_restore_service_runtime()
	_ensure_checkout_deployment()
	world.visible=false; furnishings.visible=false; people.visible=false
	_update_ui()
	print("NATIVE_READY children=",get_child_count()," world=",world.get_child_count()," ui=",ui.get_child_count())
	if "--capture-diagnostics" in OS.get_cmdline_user_args():
		get_tree().create_timer(3).timeout.connect(_capture)
	if save_recovery_blocked:compact_ui.show_help()
	web_lifecycle.start()
	cafe_intro=preload("res://scripts/cafe_intro.gd").new()
	cafe_intro.start(self)
	if "--self-check" in OS.get_cmdline_user_args():
		print("SCENE_READY furniture=", model.items.size(), " wall_thickness=0.24 expansion_parcels=24 parcel_tiles=9")
		get_tree().quit()

func _mark_platform_dirty():
	platform_dirty_generation+=1
	platform_autosave_dirty=true

func _connect_model_events():
	if OS.has_feature("crazygames"):model.changed.connect(_mark_platform_dirty)
	model.meal_completed.connect(func(_customer_id,payment):
		settings_controls.play_sfx("coin")
		compact_ui.show_earnings(payment))

func _resume_loaded_cafe():
	# Only called after startup retry has validated a complete saved model.
	_connect_model_events()
	_cancel_selection()
	for staff in staff_states:staff.node.queue_free()
	staff_states.clear();service_guests.clear()
	floor_tasks=FloorTasks.new(self)
	dishwashing=Dishwashing.new(self)
	_rebuild_room();_rebuild_furniture();_restore_service_runtime()
	_ensure_checkout_deployment()
	compact_ui.help_panel.hide()
	_update_ui();illustration.queue_redraw()

func _exit_tree():
	if web_lifecycle!=null:web_lifecycle.stop()
	if web_save!=null:web_save.stop()

func _load_startup():
	SaveLog.record("boot_requested",{"layer":"controller" if OS.has_feature("web") else "native"})
	if OS.has_feature("web"):
		web_save=WebSave.new(self)
		web_save.load_startup()
		return
	var args=OS.get_cmdline_user_args()
	save_writes_suppressed="--visual-qa" in args or "--fresh-review" in args or "--review-checkpoint" in args
	if "--fresh-review" in args:
		SaveLog.record("read_accepted",{"layer":"native","source":"review"})
		fresh_start=true;MinimalStart.apply(model);return
	if "--review-checkpoint" in args:
		if not model.load_save("res://docs/reconstructed_runtime_save.json"): MinimalStart.apply(model)
		return
	# Each prior build remains a read-only import source. An invalid priority
	# source is never skipped, and every R10 write uses only the R10 profile.
	var source=SaveProfiles.first_existing(SaveProfiles.progress_candidates(SAVE_FILE))
	startup_save_source=source
	if source!="":
		if model.load_save(source):
			SaveLog.record("read_accepted",{"layer":"native","source":"native-primary" if source==SAVE_FILE else "native-import"})
			if model.included_bin_pending:
				model.ensure_basic_bin()
			return
		# Never skip a corrupt primary/import source or treat it as absent.
		# Recovery preserves both profile files and prevents all progress writes.
		SaveLog.record("read_failure",{"layer":"native","code":"VALIDATION_FAILED"})
		save_recovery_blocked=true;paused=true
		MinimalStart.apply(model);return
	SaveLog.record("read_accepted",{"layer":"native","source":"fresh"})
	fresh_start=true;MinimalStart.apply(model)

func material(color: Color) -> StandardMaterial3D:
	var key = color.to_html()
	if material_cache.has(key): return material_cache[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	m.metallic_specular = 0.0
	if color.a < 1: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_cache[key] = m
	return m

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	n.mesh = mesh
	n.material_override = material(color)
	n.position = pos
	parent.add_child(n)
	return n

func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, top_radius = -1.0) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	n.mesh = mesh
	n.position = pos
	n.material_override = material(color)
	parent.add_child(n)
	return n

func sphere(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	n.mesh = mesh
	n.position = pos
	n.scale = size
	n.material_override = material(color)
	parent.add_child(n)
	return n

func text3(parent: Node3D, words: String, pos: Vector3, font_size=32, tint=DARK) -> Label3D:
	var n = Label3D.new()
	n.text = words
	n.position = pos
	n.font_size = font_size
	n.pixel_size = 0.011
	n.modulate = tint
	n.outline_size = 0
	n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(n)
	return n

func _setup_world():
	add_child(world)
	add_child(furnishings)
	add_child(people)
	var env = WorldEnvironment.new()
	var e = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("becaaa")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("fff9ed")
	e.ambient_light_energy = 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-30,0)
	sun.light_color = Color("fff9ed")
	sun.light_energy = 0.45
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40
	add_child(sun)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16.5
	camera.position = Vector3(20,20,24)
	add_child(camera)
	camera.look_at(Vector3(5.2,0,4.7))
	camera.current = true

func _rebuild_room():
	for c in world.get_children(): c.queue_free()
	box(world,Vector3(5,-0.18,4),Vector3(45,0.24,45),Color("b9caa0"))
	# Exterior circulation is ONLY on the actual entrance/street side.
	box(world,Vector3(-2.3,-0.045,5),Vector3(2.5,0.10,17),Color("879389"))
	for z in range(-3,14):
		box(world,Vector3(-0.65,-0.005,z+0.5),Vector3(1.0,0.06,0.98),Color("d8dcc6"))
	for x in range(model.MAX_WIDTH):
		for z in range(model.MAX_DEPTH):
			var palette=preload("res://scripts/illustrated_ground.gd").floor_palette(model.floor_style_at(Vector2i(x,z)))
			var c = palette[posmod(x+z,2)]
			if not model.is_floor_owned(Vector2i(x,z)): c = Color("d5cfb0") if (x+z)%2==0 else Color("dfd7bd")
			box(world,Vector3(x+0.5,-0.01,z+0.5),Vector3(0.99,0.05,0.99),c)
	# Walls are solid 0.24-unit volumes, with full exposed end faces and caps.
	_wall(Vector3(6,1.18,-0.12),Vector3(12.24,2.4,0.24))
	_wall(Vector3(-0.12,1.18,2.5),Vector3(0.24,2.4,5.0))
	_wall(Vector3(-0.12,1.18,7.0),Vector3(0.24,2.4,2.0))
	# Deep jambs and lintel frame the door, rather than a line pasted onto a wall.
	box(world,Vector3(-0.10,1.06,4.99),Vector3(0.34,2.16,0.13),DARK)
	box(world,Vector3(-0.10,1.06,6.01),Vector3(0.34,2.16,0.13),DARK)
	box(world,Vector3(-0.10,2.10,5.5),Vector3(0.34,0.16,1.16),DARK)
	box(world,Vector3(-0.06,2.32,5.5),Vector3(0.26,0.32,1.0),Color("cddabe"))
	box(world,Vector3(-0.05,0.04,5.5),Vector3(0.40,0.06,1.0),WOOD)
	# Real sill/recess depth, window mullions and header give the shell scale.
	for x in [2.2,5.2,8.2]:
		box(world,Vector3(x,1.30,0.025),Vector3(1.75,1.05,0.10),DARK)
		box(world,Vector3(x,1.32,0.09),Vector3(1.57,0.87,0.09),Color("b0cace"))
		box(world,Vector3(x,1.30,0.16),Vector3(0.06,0.99,0.08),CREAM)
		box(world,Vector3(x,0.79,0.20),Vector3(1.90,0.10,0.35),CREAM)
	box(world,Vector3(10.6,1.35,0.08),Vector3(1.18,1.14,0.14),WOOD)
	box(world,Vector3(10.6,1.35,0.17),Vector3(1.03,0.99,0.04),DARK)
	for i in range(4): box(world,Vector3(10.6,1.61-i*0.17,0.20),Vector3(0.65 if i>0 else 0.8,0.025,0.01),CREAM)
	# Only the back of the outward-facing hanging sign is visible from this camera.
	box(world,Vector3(-0.67,2.16,4.7),Vector3(0.9,0.06,0.06),DARK)
	box(world,Vector3(-0.84,1.83,4.7),Vector3(0.08,0.48,0.64),WOOD)
	# Each unowned plot has its own marker. Purchases never add wall geometry.
	for parcel in model.expansion_parcels():
		if not editing or parcel.owned or not parcel.visible: continue
		var cx=float(parcel.x)+float(parcel.w)*.5
		text3(world,"FOR SALE · %s"%preload("res://scripts/cafe_money.gd").amount(int(parcel.cost)),Vector3(cx,0.08,float(parcel.z)+float(parcel.h)*.5),22,Color("4e6654"))
	# Small landscaping stays outside the restaurant plan.
	for p in [Vector3(-2.6,0,-1.5),Vector3(13,0,-1),Vector3(13.5,0,6)]:
		if model.is_floor_owned(Vector2i(floori(p.x),floori(p.z))):continue
		var plant = Node3D.new()
		world.add_child(plant)
		plant.position = p
		_plant(plant,1.15)

func _wall(p: Vector3,s: Vector3):
	box(world,p,s,Color("cddabe"))
	box(world,Vector3(p.x,0.34,p.z),Vector3(s.x+0.012,0.66,s.z+0.012),Color("879c7c"))
	box(world,Vector3(p.x,2.41,p.z),Vector3(s.x+0.06,0.10,s.z+0.06),Color("f2e9cd"))
	box(world,Vector3(p.x,0.055,p.z),Vector3(s.x+0.03,0.11,s.z+0.03),Color("5f775e"))

func _plant(n: Node3D, scale_factor=1.0):
	cylinder(n,Vector3(0,0.19,0),0.20,0.38,Color("c28153"),0.26)
	cylinder(n,Vector3(0,0.40,0),0.26,0.05,Color("dbac76"))
	cylinder(n,Vector3(0,0.41,0),0.21,0.02,Color("5c4d32"))
	for i in range(7):
		var a = i*TAU/7
		var leaf = sphere(n,Vector3(cos(a)*0.18,0.75+sin(a*2)*0.15,sin(a)*0.18),Vector3(0.25,0.55,0.20),Color("547b48") if i%2 else Color("789d59"))
		leaf.rotation_degrees.z = cos(a)*40
	n.scale *= scale_factor

func make_item(kind: String) -> Node3D:
	var n = Node3D.new()
	match kind:
		"table":
			cylinder(n,Vector3(0,0.80,0),0.43,0.10,Color("c7a169"))
			cylinder(n,Vector3(0,0.40,0),0.07,0.75,WOOD)
			for v in [Vector3(-.24,.2,-.24),Vector3(.24,.2,.24),Vector3(-.24,.2,.24),Vector3(.24,.2,-.24)]: box(n,v,Vector3(.055,.38,.055),WOOD)
			cylinder(n,Vector3(.12,.91,.04),0.055,0.13,Color("bd875c"))
			sphere(n,Vector3(.12,1.04,.04),Vector3(.13,.22,.13),SAGE)
			cylinder(n,Vector3(-.16,.868,.10),0.095,0.015,CREAM)
		"chair":
			box(n,Vector3(0,.46,0),Vector3(.48,.10,.48),Color("bfa06d"))
			for x in [-.19,.19]:
				for z in [-.19,.19]: box(n,Vector3(x,.22,z),Vector3(.055,.46,.055),WOOD)
			box(n,Vector3(0,.84,-.21),Vector3(.48,.11,.065),WOOD)
			for x in [-.2,.2]: box(n,Vector3(x,.68,-.21),Vector3(.055,.60,.055),WOOD)
		"stove":
			box(n,Vector3(0,.43,0),Vector3(.84,.85,.82),Color("c3c3ae"))
			box(n,Vector3(0,.91,0),Vector3(.90,.12,.87),Color("56655b"))
			for x in [-.23,.23]:
				for z in [-.23,.23]: cylinder(n,Vector3(x,.985,z),.15,.02,Color("283e39"))
			cylinder(n,Vector3(-.23,1.08,.23),.14,.19,Color("dbc18d"))
			sphere(n,Vector3(-.23,1.18,.23),Vector3(.28,.04,.28),Color("f2da9d"))
			box(n,Vector3(0,.44,.43),Vector3(.63,.38,.02),Color("52615b"))
			box(n,Vector3(0,.66,.45),Vector3(.44,.035,.06),CREAM)
		"beverage":
			box(n,Vector3(0,.46,0),Vector3(.94,.92,.84),Color("65846e"))
			box(n,Vector3(0,.97,0),Vector3(1.0,.10,.90),Color("f0e1bd"))
			box(n,Vector3(-.15,1.22,-.10),Vector3(.52,.42,.40),Color("4f645f"))
			box(n,Vector3(-.15,1.35,.12),Vector3(.46,.07,.10),Color("be9863"))
			for x in [-.28,-.02]:
				cylinder(n,Vector3(x,1.1,.24),.065,.13,CREAM)
				cylinder(n,Vector3(x,1.173,.24),.05,.009,Color("6d4b31"))
			cylinder(n,Vector3(.33,1.18,-.12),.10,.33,Color("ca9d4f"))
			cylinder(n,Vector3(.33,1.36,-.12),.10,.045,CREAM)
		"sink":
			box(n,Vector3(0,.42,0),Vector3(.80,.83,.80),Color("9fac99"))
			box(n,Vector3(0,.87,0),Vector3(.89,.08,.88),Color("d2d9c5"))
			cylinder(n,Vector3(0,.92,.02),.31,.035,Color("4b746e"))
			cylinder(n,Vector3(0,.935,.02),.24,.01,Color("90b6ad"))
			cylinder(n,Vector3(0,1.13,-.28),.033,.42,CREAM)
			box(n,Vector3(0,1.33,-.19),Vector3(.066,.06,.22),CREAM)
		"counter":
			box(n,Vector3(0,.48,0),Vector3(.95,.96,.84),WOOD)
			box(n,Vector3(0,.99,0),Vector3(1.02,.10,.91),CREAM)
			box(n,Vector3(0,.52,.43),Vector3(.78,.62,.03),Color("9d794a"))
		"plant": _plant(n)
		"lamp":
			cylinder(n,Vector3(0,.035,0),.25,.07,DARK)
			cylinder(n,Vector3(0,.8,0),.035,1.6,WOOD)
			cylinder(n,Vector3(0,1.65,0),.33,.40,Color("ead99c"),.18)
		"bookshelf":
			box(n,Vector3(0,.85,0),Vector3(.88,1.70,.48),WOOD)
			for y in [.36,.85,1.33]:
				box(n,Vector3(0,y,.26),Vector3(.80,.39,.05),Color("735d3d"))
				for i in range(6): box(n,Vector3(-.32+i*.13,y,.30),Vector3(.085,.28+float(i%2)*.06,.20),[SAGE,Color("c98a58"),CREAM][i%3])
		"rug": box(n,Vector3(0,.038,0),Vector3(.90,.025,.90),Color("ab7453"))
		"bench":
			box(n,Vector3(0,.48,0),Vector3(.90,.17,.50),Color("76906b"))
			box(n,Vector3(0,.83,-.2),Vector3(.90,.55,.13),Color("8da17d"))
			for x in [-.35,.35]: box(n,Vector3(x,.23,0),Vector3(.10,.47,.38),WOOD)
		"divider":
			box(n,Vector3(0,.63,0),Vector3(.92,1.26,.16),Color("839570"))
			box(n,Vector3(0,1.29,0),Vector3(1.0,.08,.24),CREAM)
		_: box(n,Vector3(0,.4,0),Vector3(.8,.8,.8),SAGE)
	return n

func _apply_edit_staff_positions(previous:Array,positions:Array)->bool:
	# Validate every live identity/position before writing either half of the edit.
	if not editing or previous.size()!=staff_states.size() or positions.size()!=staff_states.size():return false
	for index in staff_states.size():
		if staff_states[index].pos!=previous[index]:return false
	for index in staff_states.size():
		var staff=staff_states[index]
		if staff.pos==positions[index]:continue
		staff.pos=positions[index];staff.node.position=Vector3(staff.pos.x,0,staff.pos.y)
		staff.destination=Vector2i(-100,-100);staff.path=[];staff.index=0
		staff.blocked_time=0.0;staff.stalled_time=0.0
		# Jobs, payload ownership and progress survive; only the walking pose resets.
		if illustration!=null:
			var key="staff_%s"%index
			illustration.motion.remove(key);illustration.stance_offsets.erase(key)
	idle_home_revision=-1
	return true

func _rebuild_furniture():
	static_service_paths.clear();static_service_revision=model.revision
	for c in furnishings.get_children(): c.queue_free()
	item_nodes.clear()
	service_props.clear()
	for staff in staff_states:
		staff.destination=Vector2i(-100,-100); staff.path=[]; staff.index=0
	for item in model.items:
		var n = make_item(item.kind)
		n.name = "Furniture_%s_%s" % [item.id,item.kind]
		n.position = Vector3(item.x+.5,0,item.z+.5)
		n.rotation.y = float(item.rot)*PI/2
		furnishings.add_child(n)
		item_nodes[item.id] = n
		if item.kind=="stove" and int(item.get("level",1))>1: text3(n,"Lv. "+str(item.level),Vector3(0,1.55,0),22,DARK)

func _style(bg: Color, border=Color.TRANSPARENT, radius=14) -> StyleBoxFlat:
	var s=StyleBoxFlat.new()
	s.bg_color=bg
	s.border_color=border
	s.set_border_width_all(1 if border.a>0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left=16
	s.content_margin_right=16
	s.content_margin_top=10
	s.content_margin_bottom=10
	return s

func label(words: String,size=16,color=DARK) -> Label:
	var n=Label.new()
	n.text=words
	n.add_theme_font_size_override("font_size",size)
	n.add_theme_font_override("font",ArtFont)
	n.add_theme_color_override("font_color",color)
	return n

func button(words: String,callback: Callable,accent=false) -> Button:
	var n=Button.new()
	n.text=words
	n.custom_minimum_size=Vector2(80,38)
	n.add_theme_font_size_override("font_size",15)
	n.add_theme_font_override("font",ArtFont)
	n.add_theme_color_override("font_color",CREAM if accent else DARK)
	n.add_theme_color_override("font_hover_color",CREAM if accent else DARK)
	n.add_theme_color_override("font_pressed_color",CREAM if accent else DARK)
	n.add_theme_color_override("font_focus_color",CREAM if accent else DARK)
	n.add_theme_stylebox_override("normal",_style(DARK if accent else Color("ebe8d7"),Color.TRANSPARENT,9))
	n.add_theme_stylebox_override("hover",_style(Color("547961") if accent else Color("dfdfc8"),Color.TRANSPARENT,9))
	n.add_theme_stylebox_override("pressed",_style(SAGE,Color.TRANSPARENT,9))
	n.add_theme_stylebox_override("disabled",_style(Color("e3e0d1"),Color.TRANSPARENT,9))
	n.add_theme_color_override("font_disabled_color",Color("5b6850"))
	n.pressed.connect(callback)
	n.pressed.connect(func():
		if settings_controls!=null: settings_controls.play_sfx("click"))
	return n

func _build_ui():
	add_child(ui)
	var top=PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left=18; top.offset_top=14; top.offset_right=-18; top.offset_bottom=76
	top.add_theme_stylebox_override("panel",_style(Color("f8f4e7"),Color("dfdec7"),17))
	ui.add_child(top)
	var row=HBoxContainer.new(); row.add_theme_constant_override("separation",15); top.add_child(row)
	row.add_child(label("Little Leaf Cafe",23,Color("4c6b58")))
	state_badge=label("Open",16,Color("819072"));row.add_child(state_badge)
	var gap=Control.new(); gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(gap)
	top_text=label("",22,Color("ad8845")); row.add_child(top_text)
	business_button=button("Close cafe",_toggle_business);row.add_child(business_button)
	business_button.tooltip_text="Stop new arrivals; current guests finish and staff keep working"
	edit_button=button("Decorate",_toggle_edit); row.add_child(edit_button)
	row.add_child(button("Settings",func(): settings.visible=not settings.visible))
	settings_controls=SettingsControls.new(self,SAVE_FILE)
	settings=settings_controls.build()
	ui.add_child(settings)
	tray=PanelContainer.new()
	tray.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tray.offset_left=18; tray.offset_right=-18; tray.offset_top=-220; tray.offset_bottom=-16
	tray.add_theme_stylebox_override("panel",_style(Color("f8f4e7"),Color("dfdec7"),18))
	ui.add_child(tray); tray.hide()
	var column=VBoxContainer.new(); tray.add_child(column)
	var tools=HBoxContainer.new(); tools.add_theme_constant_override("separation",8); column.add_child(tools)
	tool_text=label("Choose an item · click a floor tile to place",14); tool_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL; tools.add_child(tool_text)
	tools.add_child(button("Rotate  R",_rotate))
	tools.add_child(button("Sell selected",_sell))
	expand_button=button("Next plot",_expand); tools.add_child(expand_button)
	expand_button.tooltip_text="Buy the next unowned plot, or click a specific FOR SALE sign"
	tools.add_child(button("Hire cook",_hire))
	tools.add_child(button("Upgrade stove",_upgrade))
	var categories=HFlowContainer.new();categories.add_theme_constant_override("separation",6);column.add_child(categories)
	for category in ["Tables","Kitchen","Drinks","Cleaning","Decor","Build"]:
		var tab=button(category,func():_set_catalog_category(category));tab.toggle_mode=true;tab.button_pressed=category==catalog_category
		categories.add_child(tab);category_buttons[category]=tab
	var scroll=ScrollContainer.new();catalog_scroll=scroll; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; column.add_child(scroll)
	var products=HBoxContainer.new(); products.add_theme_constant_override("separation",8); scroll.add_child(products)
	for spec in model.catalog:
		if bool(spec.get("hidden",false)):continue
		var card=button("",func(): _choose(spec.kind)); card.custom_minimum_size=Vector2(99,105); products.add_child(card);catalog_cards[spec.kind]=card
		var v=VBoxContainer.new(); v.mouse_filter=Control.MOUSE_FILTER_IGNORE; v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); v.offset_top=1; v.offset_left=4; v.offset_right=-4; card.add_child(v)
		var icon_holder=Control.new(); icon_holder.custom_minimum_size=Vector2(91,57); icon_holder.mouse_filter=Control.MOUSE_FILTER_IGNORE; v.add_child(icon_holder)
		var icon=Illustration.new(); icon.icon_kind=spec.kind; icon_holder.add_child(icon)
		var title=label(spec.name,11); title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; v.add_child(title)
		var price=label("",11,Color("7b856c")); price.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; v.add_child(price);catalog_prices[spec.kind]=price

	build_panel=build_tools.build();column.add_child(build_panel);build_panel.hide()
	compact_ui=CompactUI.new(self);compact_ui.setup()
	for kind in catalog_cards:catalog_cards[kind].visible=_catalog_group(kind)==catalog_category

func _catalog_group(kind:String)->String:
	if model.is_dining_product(kind) or kind in ["table","chair","bench"]:return "Tables"
	if kind in ["stove","counter","register"]:return "Kitchen"
	if kind=="beverage":return "Drinks"
	if kind in ["sink","bin"]:return "Cleaning"
	return "Decor"

func _set_catalog_category(category:String):
	catalog_category=category
	_cancel_selection()
	for key in category_buttons:category_buttons[key].button_pressed=key==category
	for kind in catalog_cards:catalog_cards[kind].visible=category=="All" or _catalog_group(kind)==category
	if is_instance_valid(build_panel):build_panel.visible=category=="Build"
	if is_instance_valid(catalog_scroll):catalog_scroll.visible=category!="Build"
	if compact_ui!=null:compact_ui.sync()

func _toggle_business():
	if save_recovery_blocked:return
	model.set_operating_open(not model.operating_open)
	_sync_service_guests();_update_ui();_save()

func _toggle_edit():
	if save_recovery_blocked:return
	editing=not editing
	if editing:model.begin_decoration_session()
	else:model.finish_decoration_session()
	_cancel_selection()
	if not editing:_save()
	_update_ui()
	compact_ui.set_tray_open(editing)

func _choose(kind: String):
	_cancel_selection()
	selected_kind=kind
	tool_text.text="Place %s · R rotates · right click cancels" % kind.capitalize()
	ghost=make_item(kind); add_child(ghost)
	for mesh in ghost.get_children():
		if mesh is MeshInstance3D:
			var faded=mesh.material_override.duplicate()
			faded.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
			faded.albedo_color.a=0.45
			mesh.material_override=faded
			mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _cancel_selection():
	if compact_ui!=null:compact_ui.clear_selection()
	if build_tools!=null:build_tools.cancel()
	if interaction!=null: interaction.cancel(false)
	selected_kind=""; selected_id=-1
	if is_instance_valid(tool_text): tool_text.text="Choose an item · click a floor tile to place"
	if is_instance_valid(ghost): ghost.queue_free()
	ghost=null

func _rotate():
	if build_tools!=null and build_tools.active():build_tools.rotate();return
	if interaction!=null: interaction.rotate_selection()

func _expand():
	for parcel in model.expansion_parcels():
		if not parcel.owned:
			_buy_parcel(str(parcel.id));return

func _buy_parcel(parcel_id: String):
	if not editing:return
	if save_recovery_blocked:return
	if model.buy_parcel(parcel_id):
		_cancel_selection();_rebuild_room();_update_ui();_save()

func _hire():_hire_staff("chef")
func _hire_staff(role:String):
	if save_recovery_blocked:return
	if model.hire_staff(role):_update_people();_sync_staff_duty();_update_ui();_save()
func _change_staff_duty(role:String,change:int):
	if save_recovery_blocked:return
	if model.request_duty(role,change):
		_sync_staff_duty()
		_update_ui();_save()
func _sync_staff_duty():
	model.checkout_staff_claims.clear()
	for worker in staff_states:
		model.checkout_staff_claims.append(worker.pos)
		for route_index in range(int(worker.index),worker.path.size()):model.checkout_staff_claims.append(model.cell_center(worker.path[route_index]))
	var changed=false;var counts={"chef":0,"waiter":0,"cleaner":0,"cashier":0};var ranks={"chef":0,"waiter":0,"cleaner":0,"cashier":0}
	for staff in staff_states:
		var role=str(staff.role);var wanted=int(ranks[role])<int(model.duty_targets[role]);ranks[role]+=1
		var working=wanted or staff.job_kind!=""
		var pending=not wanted and staff.job_kind!=""
		if bool(staff.get("on_duty",true))!=working:changed=true;staff.blocked_reason=""
		staff.on_duty=working;staff.duty_pending=pending
		if working:counts[role]+=1
	if not staff_states.is_empty():model.duty_counts=counts
	if changed:idle_home_revision=-1
func _staff_on_duty()->bool:
	if model.operating_open or not model.customers.is_empty() or not floor_tasks.messes.is_empty() or not dishwashing.dishes.is_empty():return true
	for staff in staff_states:
		if staff.job_kind!="":return true
	return false

func _upgrade():
	if selected_id<0:return
	if model.upgrade_stove(selected_id):_update_ui();_save()

func _sell():
	if selected_id<0 or _item_service_locked(selected_id):return
	if model.remove(selected_id):
		_cancel_selection(); _rebuild_furniture(); _update_ui()
		_save()

func _update_ui():
	top_text.text="Leaf Coins  %s" % Money.amount(model.coins)
	if is_instance_valid(detail_stats): detail_stats.text="%s served · %s guests · %s×" % [model.served,model.customers.size(),int(speed)]
	pause_button.text="Resume" if paused else "Pause"
	edit_button.text="Done decorating" if editing else "Decorate"
	if is_instance_valid(business_button):business_button.text="Close cafe" if model.operating_open else "Open cafe"
	for kind in catalog_prices:
		var cost=model.price_of(kind);catalog_prices[kind].text="Included" if cost==0 else Money.amount(cost)+" coins"
	if is_instance_valid(expand_button):
		expand_button.disabled=model.expanded or save_recovery_blocked
		var next_plot=model.next_parcel()
		expand_button.text="All plots owned" if next_plot.is_empty() else "Next plot · %s"%Money.amount(int(next_plot.cost))
	if is_instance_valid(state_badge): state_badge.text="Recovery" if save_recovery_blocked else ("Unsaved" if progress_unsaved else ("Decorating" if editing else ("Paused" if paused else model.operating_status())))
	if settings_controls!=null: settings_controls.sync()
	if build_tools!=null:build_tools.sync()
	if compact_ui!=null:compact_ui.sync()

func _service_save_snapshot()->Dictionary:
	_sync_staff_duty();_sync_service_guests()
	var records=[]
	for id in service_guests:
		var record=service_guests[id].duplicate(true);record.erase("guest");record["guest_id"]=int(id);records.append(record)
	var staff=[]
	for source in staff_states:
		var state={}
		for key in ["role","on_duty","duty_pending","pos","destination","path","index","yield_time","blocked_reason","blocked_target_id","blocked_guest_id","job_guest_id","job_mess_id","job_dish_id","job_token","job_kind","job_step","job_elapsed","station_id","blocked_time","stalled_time","art_heading","table_face_id","table_face_cell"]:
			if source.has(key):state[key]=source[key].duplicate(true) if source[key] is Array or source[key] is Dictionary else source[key]
		staff.append(state)
	return {"version":SaveContract.SERVICE_VERSION,"checkout_format":SaveContract.CHECKOUT_FORMAT,"serial":service_serial,"records":records,"staff":staff,"animation_time":animation_time,"floor_tasks":floor_tasks.snapshot(),"dishwashing":dishwashing.snapshot()}

func _restore_service_runtime():
	var snapshot=model.service_snapshot
	if snapshot.is_empty():
		dishwashing.restore({})
		_update_people()
		if fresh_start and not save_recovery_blocked:_place_fresh_staff_at_posts()
		_sync_service_guests();return
	service_serial=int(snapshot.serial);animation_time=float(snapshot.animation_time)
	floor_tasks.restore(snapshot.get("floor_tasks",{}))
	dishwashing.restore(snapshot.get("dishwashing",{}))
	service_guests.clear()
	for saved in snapshot.records:
		for guest in model.customers:
			if int(guest.id)==int(saved.guest_id):
				var record=saved.duplicate(true);record.erase("guest_id");record["guest"]=guest
				record["meal_wait_seconds"]=float(saved.get("meal_wait_seconds",0.0))
				service_guests[int(guest.id)]=record;break
	# Preserve staff ordering: later chef hires were appended, and payloads
	# refer to stable staff indices. Recreating all chefs first would swap hands.
	for staff in staff_states:staff.node.queue_free()
	staff_states.clear()
	for saved in snapshot.staff:
		_add_staff(str(saved.role),saved.pos)
		var staff=staff_states[-1]
		for key in saved:staff[key]=saved[key].duplicate(true) if saved[key] is Array or saved[key] is Dictionary else saved[key]
		staff.node.position=Vector3(staff.pos.x,0,staff.pos.y)
	_update_people();_sync_service_guests()
	dishwashing.migrate_legacy()
	for index in range(staff_states.size()):
		var staff=staff_states[index]
		if staff.job_kind=="":_set_staff_art(staff,"idle",{},0.0,"none");continue
		_prepare_cleanup_step(staff,index);floor_tasks.prepare(staff,index)
		if staff.job_kind=="":_set_staff_art(staff,"idle",{},0.0,"none");continue
		var target=_service_target(staff);var step=SERVICE_STEPS[staff.job_kind][int(staff.job_step)]
		var seconds=float(step.seconds)
		if step.action=="cooking":seconds=Model.cooking_seconds(Model.stove_speed_multiplier(target))
		var payload=_staff_payload(staff,index)
		var destination=_service_destination(staff,target,Vector2i(floori(staff.pos.x),floori(staff.pos.y))) if not target.is_empty() else Vector2i(-1,-1)
		var arrived=destination!=Vector2i(-1,-1) and staff.pos.distance_to(Vector2(destination)+Vector2(.5,.5))<.03
		var travel_action={"plate":"carrying_to_pass" if staff.role=="chef" else "carrying_plate","drink":"carrying_drink","dishes":"carrying_dishes","trash":"carrying_trash"}.get(payload,"walking")
		_set_staff_art(staff,str(step.action) if arrived else travel_action,target,clampf(float(staff.job_elapsed)/seconds,0,1) if arrived else 0.0,payload)

func _place_fresh_staff_at_posts():
	# Only a genuinely new cafe has no saved positions to resume. Use the same
	# reachable posts as ordinary idle work, before its first illustrated frame.
	# Saved snapshots and recovery fallbacks never pass through this placement.
	var claimed=[]
	for index in staff_states.size():
		var staff=staff_states[index]
		var cell=_staff_idle_cell(index,claimed)
		if not _staff_walkable(cell):continue
		claimed.append(cell)
		staff.pos=model.cell_center(cell)
		staff.node.position=Vector3(staff.pos.x,0,staff.pos.y)
		staff.destination=cell;staff.path=[];staff.index=0
		var station=model.get_item(int(staff.get("idle_home_id",-1)))
		_set_staff_art(staff,"standby",station,0.0,"none")

func _on_window_close():
	# Persist the same validated runtime transaction before an ordinary close.
	# Isolated QA suppresses all writes and can still exit its own process.
	if _save():get_tree().quit()
	elif compact_ui!=null:compact_ui.show_help()

func _recovery_notice()->String:
	return startup_notice if startup_notice!="" else "Saved café needs recovery · original file kept untouched"

func _unsaved_progress_message()->String:
	# Existing Help shows failure details; pending and successful saves stay silent.
	if not progress_unsaved or progress_save_error=="":return ""
	var action="Open Settings → Quick help" if save_recovery_blocked else "Keep this page open; saving will retry" if web_save!=null else "Keep the game open; saving will retry"
	return "Unsaved changes · "+progress_save_error+" · "+action

func _save():
	if OS.has_feature("web"):return web_save.request_save() if web_save!=null else false
	SaveLog.record("save_requested",{"layer":"native"})
	save_timer=0.0
	if save_recovery_blocked or save_writes_suppressed or "--visual-qa" in OS.get_cmdline_user_args() or "--fresh-review" in OS.get_cmdline_user_args() or "--review-checkpoint" in OS.get_cmdline_user_args():
		SaveLog.record("save_skipped",{"layer":"native","code":"RECOVERY_BLOCKED" if save_recovery_blocked else "WRITES_SUPPRESSED"});return true
	# Only this version's profile is mutable. Older import sources and the
	# reconstructed source checkpoint remain byte-for-byte untouched.
	_update_people()
	model.service_snapshot=_service_save_snapshot()
	if not model.save(SAVE_FILE):
		SaveLog.record("save_failure",{"layer":"native","code":"NATIVE_SAVE_FAILED"})
		progress_unsaved=true;progress_save_error=model.last_error;return false
	SaveLog.record("save_accepted",{"layer":"native"})
	progress_unsaved=false;progress_save_error=""
	return true

func _input(event):
	if cafe_intro!=null and cafe_intro.handle_input(event):
		get_viewport().set_input_as_handled();return
	if web_lifecycle!=null and web_lifecycle.handle_input(event):
		get_viewport().set_input_as_handled();return
	# A dismissed modal owns its complete pointer sequence before camera pinch.
	if compact_ui!=null and compact_ui.consume_modal_dismissal(event):
		get_viewport().set_input_as_handled();return
	if compact_ui!=null and compact_ui.viewport_too_small:
		get_viewport().set_input_as_handled();return
	if camera_gestures!=null and camera_gestures.handle_input(event):
		get_viewport().set_input_as_handled();return
	if compact_ui!=null and compact_ui.handle_input(event):
		get_viewport().set_input_as_handled();return
	# Modal Controls keep GUI dispatch, but world tools never own their input.
	if compact_ui!=null and compact_ui.has_open_popup():return
	if build_tools!=null and build_tools.handle_input(event):get_viewport().set_input_as_handled();return
	if interaction!=null and interaction.handle_input(event):
		get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F12: _capture()
		if event.keycode==KEY_F10: _toggle_wall_detail()

func _unhandled_input(event):
	if compact_ui!=null and (compact_ui.viewport_too_small or compact_ui.has_open_popup()):get_viewport().set_input_as_handled();return
	if compact_ui!=null and compact_ui.handle_unhandled_input(event):return
	if build_tools!=null and build_tools.handle_unhandled_input(event):get_viewport().set_input_as_handled();return
	if interaction!=null and interaction.handle_unhandled_input(event): get_viewport().set_input_as_handled()

func _sync_window_scale():
	# Responsive UI lays out in device-independent window units. A fixed
	#1360x880 canvas would letterbox narrow windows before breakpoints run.
	var window=get_window()
	var scale=maxf(1.0,DisplayServer.screen_get_scale(window.current_screen))
	if not is_equal_approx(window.content_scale_factor,scale):window.content_scale_factor=scale
	var view=get_viewport().get_visible_rect().size
	if view!=responsive_view:
		responsive_view=view
		# A late release in the new projection cannot commit a prior GUI/world press.
		if web_lifecycle!=null:web_lifecycle.cancel_pending()
	if compact_ui!=null:compact_ui.sync()
	if is_instance_valid(illustration):
		illustration.update_projection();illustration.queue_redraw()
		if interaction!=null:interaction.pan_offset=illustration.pan_offset

func _notification(what):
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if cafe_intro!=null:cafe_intro.finish()
		if web_lifecycle!=null:web_lifecycle.cancel_pending()
		if compact_ui!=null:compact_ui.cancel_modal_pointer()
		if camera_gestures!=null:camera_gestures.on_focus_lost()
		if interaction!=null:interaction.on_focus_lost()
		if build_tools!=null:build_tools.on_focus_lost()

func _floor_cell(screen: Vector2) -> Vector2i:
	if is_instance_valid(illustration): return illustration.screen_to_cell(screen)
	var point=Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))
	if point==null: return Vector2i(-100,-100)
	return Vector2i(floori(point.x),floori(point.z))

func _process(delta):
	if OS.has_feature("web") and OS.has_feature("crazygames"):
		var platform=JavaScriptBridge.get_interface("LittleLeafPlatform")
		if platform!=null:
			if not bool(platform.ready):
				paused=true;save_recovery_blocked=true;save_writes_suppressed=true
				startup_notice="Platform account changed or storage failed. Reload to load progress."
			var playable=preload("res://scripts/cafe_platform_state.gd").playable(paused,editing,save_recovery_blocked,cafe_intro!=null and cafe_intro.active,compact_ui.viewport_too_small,compact_ui.has_open_popup())
			platform.viewportPlayable=not compact_ui.viewport_too_small
			platform.update(playable)
			if platform_music!=null and playable and bool(platform.playing):platform_music.begin()
			AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),bool(platform.muteAudio))
	if cafe_intro!=null and cafe_intro.active:
		_music_tick(delta);return
	if compact_ui!=null and compact_ui.viewport_too_small:return
	_sync_staff_duty()
	if interaction!=null: interaction.refresh(get_viewport().get_mouse_position())
	if build_tools!=null:build_tools.refresh(get_viewport().get_mouse_position())
	if compact_ui!=null:compact_ui.update_pointer()
	if compact_ui!=null:compact_ui.tick_earnings(delta)
	if not editing and not paused and not save_recovery_blocked:
		_tick_live_service(delta*speed)
		_update_people()
		# Resolve cooking/contact before deadlines and before any autosave.
		_animate_staff(delta*speed)
		# Arrival/payroll/customer/staff timers advance saved state during play.
		if OS.has_feature("crazygames"):_mark_platform_dirty()
	visual_timer+=delta
	save_timer+=delta
	if visual_timer>.2:
		visual_timer=0; _update_ui(); _update_service_props()
	if preload("res://scripts/cafe_autosave_policy.gd").due(OS.has_feature("crazygames"),platform_autosave_dirty,save_timer,web_save!=null and web_save.pending,save_recovery_blocked or save_writes_suppressed,interaction!=null and interaction.drag_active):_save()
	_update_people()
	animation_time+=delta if not editing and not paused else 0.0
	_music_tick(delta)
	if is_instance_valid(ghost):
		hover_cell=_floor_cell(get_viewport().get_mouse_position())
		ghost.position=Vector3(hover_cell.x+.5,.04,hover_cell.y+.5)
		ghost.rotation.y=rotation_step*PI/2
		ghost.visible=model.is_floor_owned(hover_cell)

func _person(color: Color,apron=false) -> Node3D:
	var n=Node3D.new()
	cylinder(n,Vector3(0,.51,0),.15,.39,color,.20)
	for x in [-.095,.095]:
		cylinder(n,Vector3(x,.16,0),.045,.30,Color("586452"))
		box(n,Vector3(x,.03,.045),Vector3(.12,.07,.19),DARK)
	sphere(n,Vector3(0,.87,0),Vector3(.39,.40,.34),Color("e9c49a"))
	sphere(n,Vector3(0,.82,.14),Vector3(.21,.15,.13),Color("f4dbb5"))
	for x in [-.15,.15]: sphere(n,Vector3(x,1.025,-.025),Vector3(.14,.17,.11),Color("bc956a"))
	if apron: cylinder(n,Vector3(0,1.04,0),.20,.10,CREAM)
	for x in [-.07,.07]: sphere(n,Vector3(x,.88,.164),Vector3(.025,.025,.018),DARK)
	if apron: box(n,Vector3(0,.48,.16),Vector3(.23,.29,.03),CREAM)
	return n

func _update_people():
	var alive = {}
	for customer in model.customers:
		if str(customer.get("phase","")) in ["dirty","cleaning"]: continue
		var id = int(customer.id)
		alive[id] = true
		if not actor_nodes.has(id):
			var person = _person([Color("ba8259"),Color("709696"),Color("9c8dab"),Color("c4ab68")][id%4])
			people.add_child(person)
			var bubble = text3(person,"",Vector3(0,1.4,0),22,DARK)
			bubble.name="Dialogue"
			bubble.outline_size=7
			bubble.outline_modulate=CREAM
			actor_nodes[id]=person
		var person=actor_nodes[id]
		var target=Vector3(float(customer.get("x",0.5)),0,float(customer.get("z",5.5)))
		var direction=target-person.position
		if direction.length()>0.005 and direction.length()<1.0: person.rotation.y=atan2(direction.x,direction.z)
		person.position=target
		var phase=str(customer.get("phase","ordering"))
		var words={"arriving":"A table for me?","ordering":"Today's special, please","cooking":"Smells lovely!","drinking":"A drink, please","eating":"","leaving":"Thank you!"}.get(phase,"")
		person.get_node("Dialogue").text=words
		if phase in ["arriving","leaving","checkout_walk"]: person.position.y=abs(sin(animation_time*10+id))*0.025
	for id in actor_nodes.keys():
		if not alive.has(id): actor_nodes[id].queue_free(); actor_nodes.erase(id)
	# Keep stable staff indices, including the former drink worker. Both
	# waiters now take whole customer-facing tasks from start to finish.
	var chef_count=0
	for staff in staff_states:
		if staff.role=="chef":chef_count+=1
	while chef_count<model.cooks:
		_add_staff("chef");chef_count+=1
	for role in ["waiter","cleaner","cashier"]:
		var present=0
		for staff in staff_states:
			if staff.role==role:present+=1
		while present<model.staff_count(role):
			if not _add_staff(role):break
			present+=1

func _ensure_checkout_deployment():
	if not model.included_checkout_pending:return
	_sync_staff_duty()
	var actors=[]
	for staff in staff_states:actors.append(staff.pos)
	if model.ensure_basic_register(actors):
		_update_people();_sync_staff_duty();_rebuild_furniture()

func _add_staff(role: String, restored_position=null) -> bool:
	var cashier_start=Vector2.ZERO
	if role=="cashier" and restored_position==null:
		var register=model.checkout_register()
		if register.is_empty():return false
		var rear=model.checkout_rear(register)
		cashier_start=model.cell_center(rear)
		if not _staff_walkable(rear):return false
		for staff in staff_states:
			if staff.pos.distance_to(cashier_start)<.9:return false
		for guest in model.customers:
			if guest.phase not in ["dirty","cleaning"] and Checkout.point(guest).distance_to(cashier_start)<.9:return false
	var n=_person({"chef":Color("6d8b67"),"waiter":Color("ae8a5c"),"cleaner":Color("7d99a2"),"cashier":Color("b68b92")}[role],true)
	people.add_child(n)
	var start=Vector2(7.5,1.5)
	var found=false
	for z in range(model.depth):
		for x in range(2,model.width):
			var cell=Vector2i(x,z)
			if not _staff_walkable(cell) or _is_station_workface(cell): continue
			var point=Vector2(x+.5,z+.5)
			var occupied=false
			for staff in staff_states:
				if point.distance_to(staff.pos)<.9: occupied=true;break
			for guest in model.customers:
				if str(guest.phase) not in ["dirty","cleaning"] and point.distance_to(Vector2(float(guest.x),float(guest.z)))<.9: occupied=true;break
			if occupied or _static_service_path(Model.ENTRY_LANDING,cell).is_empty(): continue
			start=point;found=true;break
		if found: break
	if restored_position!=null:start=restored_position
	elif role=="cashier":start=cashier_start
	n.position=Vector3(start.x,0,start.y)
	staff_states.append({"node":n,"role":role,"art_role":role,"pos":start,"destination":Vector2i(-100,-100),"path":[],"index":0,"yield_time":0.0,
		"on_duty":true,"duty_pending":false,"blocked_reason":"","blocked_target_id":-1,"blocked_guest_id":-1,"art_block_reason":"","job_guest_id":-1,"job_token":-1,"job_kind":"","job_step":0,"job_elapsed":0.0,"station_id":-1,"blocked_time":0.0,"stalled_time":0.0,
		"table_face_id":-1,"table_face_cell":Vector2i(-1,-1),"idle_home_id":-1,"idle_home_cell":Vector2i(-1,-1),"idle_return_delay":0.0,
		"art_action":"idle","art_phase":0.0,"art_contact":false,"art_tool":"none","art_service_kind":"","art_guest_id":-1,"art_guest_phase":"","art_target":start,"art_target_id":-1,"art_station":start,"art_payload":"none"})
	return true

func _is_station_workface(cell: Vector2i) -> bool:
	for item in model.items:
		if str(item.kind)=="bin" and model.bin_service_cells(item).has(cell):return true
		if str(item.kind) in ["stove","beverage","sink","counter","register"] and model.workface_cell(item)==cell: return true
		if str(item.kind) in ["counter","register"] and Vector2i(int(item.x),int(item.z))*2-model.workface_cell(item)==cell: return true
	return false

func _sync_service_guests():
	var active={}
	for guest in model.customers:
		var id=int(guest.id)
		active[id]=true
		if service_guests.has(id) and is_same(service_guests[id].guest,guest):
			_update_floor_state(service_guests[id])
			continue
		service_serial+=1
		var phase=str(guest.phase)
		service_guests[id]={"guest":guest,"token":service_serial,"meal_wait_seconds":0.0,
			"order_done":phase in ["cooking","drinking","eating","checkout_wait","checkout_walk","paying","leaving","dirty","cleaning"],"meal_ready":phase in ["drinking","eating","checkout_wait","checkout_walk","paying","leaving","dirty","cleaning"],"drink_ready":phase in ["eating","checkout_wait","checkout_walk","paying","leaving","dirty","cleaning"],"meal_station_id":-1,"meal_pass_id":-1,"pass_reserved":false,"drink_station_id":-1,"floor_cleaned":false,"floor_dirty":phase in ["eating","checkout_wait","checkout_walk","paying","leaving","dirty","cleaning"],
			"meal_done":phase in ["drinking","eating","checkout_wait","checkout_walk","paying","leaving","dirty","cleaning"],
			"drink_done":phase in ["eating","checkout_wait","checkout_walk","paying","leaving","dirty","cleaning"],
			"dishes_collected":false,"table_wiped":false,"cleanup_done":false,"dish_sink_id":-1,"dish_id":-1,
			"plate_owner":"table" if phase in ["drinking","eating","checkout_wait","checkout_walk","paying","leaving","dirty","cleaning"] else "kitchen",
			"plate_staff_index":-1,"plate_target_id":int(guest.table_id) if phase in ["drinking","eating","checkout_wait","checkout_walk","paying","leaving","dirty","cleaning"] else -1,
			"drink_owner":"table" if phase in ["eating","checkout_wait","checkout_walk","paying","leaving","dirty","cleaning"] else "beverage",
			"drink_staff_index":-1,"drink_target_id":int(guest.table_id) if phase in ["eating","checkout_wait","checkout_walk","paying","leaving","dirty","cleaning"] else -1}
		_init_floor_state(service_guests[id])
		_update_floor_state(service_guests[id])
	for id in service_guests.keys():
		if not active.has(id): service_guests.erase(id)
	_retire_service_station_references()

func _init_floor_state(record:Dictionary):
	var guest=record.guest
	var kind="none";var wet=false
	record.floor_dirty=false;record.floor_cleaned=true
	var table=model.get_item(int(guest.table_id))
	var center=Vector2(float(table.get("x",0))+.5,float(table.get("z",0))+.5)
	var floor_cell=_choose_floor_cell(table)
	var floor_center=Vector2(floor_cell)+Vector2(.5,.5)
	var side=(floor_center-center).normalized()
	var cross=Vector2(-side.y,side.x)
	record.floor_debris=kind;record.floor_spill=wet
	record.trash_owner="none" if kind=="none" else "floor"
	record.trash_staff_index=-1;record.trash_target_id=-1
	record.spill_cleaned=not wet;record.spill_remaining=1.0 if wet else 0.0
	record.floor_cell=floor_cell
	record.floor_target=floor_center+side*.22
	record.debris_target=record.floor_target+cross*.14
	record.spill_target=record.floor_target-cross*.14

func _choose_floor_cell(table:Dictionary)->Vector2i:
	# A mess belongs on a clear floor tile, not the projected chair seat.
	# Prefer the camera-facing sides and pin this tile for the whole job.
	var base=Vector2i(int(table.get("x",0)),int(table.get("z",0)))
	var service_side=base+model.table_service_direction(int(table.get("id",-1)))
	for offset in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i(1,1),Vector2i(2,0),Vector2i(0,2),Vector2i.LEFT,Vector2i.UP,Vector2i(-1,1),Vector2i(1,-1)]:
		var cell=base+offset
		if not _staff_walkable(cell):continue
		if model.has_method("edge_blocked") and absi(offset.x)+absi(offset.y)==1 and model.edge_blocked(base,cell):continue
		if not _static_service_path(service_side,cell).is_empty():return cell
	return service_side

func _is_floor_cleanup(staff:Dictionary)->bool:
	if str(staff.get("job_kind",""))=="floor":return int(staff.job_step)!=2
	if str(staff.get("job_kind",""))!="cleanup":return false
	var index=int(staff.get("job_step",-1))
	return index>=0 and index<SERVICE_STEPS.cleanup.size() and str(SERVICE_STEPS.cleanup[index].action) in ["sweeping","mopping"]

func _table_face_available(cell:Vector2i,staff:Dictionary,claimed:Array)->bool:
	# Work destinations stay exclusive; passing bodies never reserve the floor.
	if claimed.has(cell) or model.checkout_claims().has(cell):return false
	for other in staff_states:
		if is_same(other,staff):continue
		if other.job_kind!="" and (other.get("table_face_cell",Vector2i(-1,-1))==cell or other.destination==cell):return false
	return true

func _table_service_destination(staff:Dictionary,item:Dictionary,from:Vector2i,claimed:Array)->Vector2i:
	var cells=model.table_service_cells(item)
	var pinned:Vector2i=staff.get("table_face_cell",Vector2i(-1,-1))
	var staff_index=staff_states.find(staff)
	var force_replan=float(staff.get("stalled_time",0.0))>.65
	if int(staff.get("table_face_id",-1))==int(item.id) and cells.has(pinned) and _table_face_available(pinned,staff,claimed) and not _static_service_path(from,pinned).is_empty():
		if not force_replan or staff_index<0 or from==pinned or not _staff_route(staff_index,pinned).is_empty():return pinned
	var best=Vector2i(-1,-1);var shortest=1000000
	for cell in cells:
		if not _table_face_available(cell,staff,claimed):continue
		var route=_staff_route(staff_index,cell) if staff_index>=0 else _static_service_path(from,cell)
		if route.is_empty() and from!=cell:continue
		if route.size()<shortest:best=cell;shortest=route.size()
	staff.table_face_id=int(item.id) if best!=Vector2i(-1,-1) else -1
	staff.table_face_cell=best
	return best

func _bin_service_destination(staff:Dictionary,item:Dictionary,from:Vector2i,claimed:Array)->Vector2i:
	var cells=model.bin_service_cells(item)
	var staff_index=staff_states.find(staff)
	var pinned:Vector2i=staff.get("destination",Vector2i(-1,-1))
	# Keep an in-flight approach stable. Replan when a peer, wall or changed
	# layout makes that route unavailable; no new persistent save fields.
	if cells.has(pinned) and _table_face_available(pinned,staff,claimed):
		if staff_index>=0:
			if not _staff_cell_claimed(pinned,staff_index) and (from==pinned or not _staff_route(staff_index,pinned).is_empty()):return pinned
		elif not _static_service_path(from,pinned).is_empty():return pinned
	var best=Vector2i(-1,-1);var shortest=1000000
	for cell in cells:
		if not _table_face_available(cell,staff,claimed):continue
		if staff_index>=0 and _staff_cell_claimed(cell,staff_index):continue
		var route=_staff_route(staff_index,cell) if staff_index>=0 else _static_service_path(from,cell)
		if route.is_empty() and from!=cell:continue
		if route.size()<shortest:best=cell;shortest=route.size()
	return best

func _service_destination(staff:Dictionary,item:Dictionary,from:Vector2i,claimed=[])->Vector2i:
	if staff.job_kind=="floor" and _is_floor_cleanup(staff):return floor_tasks.destination(staff,from,claimed)
	if _is_floor_cleanup(staff) and service_guests.has(int(staff.job_guest_id)):
		staff.table_face_id=-1;staff.table_face_cell=Vector2i(-1,-1)
		var record=service_guests[int(staff.job_guest_id)]
		return floor_tasks.destination_for_record(record,staff,from,claimed)
	if str(item.get("kind",""))=="table":return _table_service_destination(staff,item,from,claimed)
	staff.table_face_id=-1;staff.table_face_cell=Vector2i(-1,-1)
	if str(item.get("kind",""))=="bin":return _bin_service_destination(staff,item,from,claimed)
	if str(item.get("kind",""))=="sink" and not dishwashing.workface_available(staff,int(item.id)):return Vector2i(-1,-1)
	return _service_cell(item,from,claimed,str(staff.role))

func _update_floor_state(record:Dictionary):
	var guest=record.guest
	if bool(guest.get("withdrawn",false)):
		for key in ["order_done","meal_ready","drink_ready","meal_done","drink_done","dishes_collected","table_wiped","cleanup_done","floor_cleaned","spill_cleaned"]:record[key]=true
		record.floor_dirty=false;record.floor_debris="none";record.floor_spill=false;record.spill_remaining=0.0
		record.plate_owner="clean";record.drink_owner="cleared";record.trash_owner="none"
		return
	var after_meal=str(guest.phase) in ["checkout_wait","checkout_walk","paying","leaving","dirty","cleaning"]
	var during_meal=str(guest.phase)=="eating" and float(guest.elapsed)>=float(guest.duration)*.55
	if (after_meal or during_meal) and not bool(record.floor_cleaned):record.floor_dirty=true

func _cleanup_step_needed(record:Dictionary,action:String,debris_kind="")->bool:
	match action:
		"collecting":return not record.dishes_collected
		"dropping_dishes":return record.plate_owner=="staff"
		"wiping":return not record.table_wiped
		"sweeping":return record.floor_debris in ["banana","crumbs"] and record.trash_owner=="floor" and (debris_kind=="" or record.floor_debris==debris_kind)
		"disposing_trash":return record.trash_owner in ["staff","bin"]
		"mopping":return record.floor_spill and not record.spill_cleaned
	return false

func _cleanup_role_step(record:Dictionary,role:String)->int:
	# Keep the save's seven stage indices: table 0–2, floor 3–6.
	for candidate in (range(0,3) if role=="waiter" else range(3,7)):
		var step=SERVICE_STEPS.cleanup[candidate]
		if _cleanup_step_needed(record,str(step.action),step.get("debris_kind","")):return candidate
	return SERVICE_STEPS.cleanup.size()

func _sync_cleanup_completion(record:Dictionary):
	# Either worker may finish first. Never erase the other role's work.
	record.floor_cleaned=record.trash_owner in ["none","disposed"] and record.spill_cleaned
	record.floor_dirty=not record.floor_cleaned
	record.cleanup_done=record.dishes_collected and record.plate_owner in ["clean","dish_queue"] and record.drink_owner=="cleared" and record.table_wiped and record.floor_cleaned

func _prepare_cleanup_step(staff:Dictionary,index:int):
	if staff.job_kind!="cleanup" or not service_guests.has(int(staff.job_guest_id)):return
	var record=service_guests[int(staff.job_guest_id)]
	var current_action=str(SERVICE_STEPS.cleanup[mini(int(staff.job_step),SERVICE_STEPS.cleanup.size()-1)].action)
	var held_dishes=record.plate_owner=="staff" and int(record.plate_staff_index)==index
	var held_trash=record.trash_owner=="staff" and int(record.trash_staff_index)==index
	var elapsed=float(staff.job_elapsed);var desired=int(staff.job_step)
	# A legacy cleaner may finish an already-started gesture/transport, but
	# every newly assigned table task belongs to a waiter.
	var legacy_table=staff.role=="cleaner" and int(staff.job_step)<3
	if held_dishes:
		if current_action!="collecting" or elapsed<=0.0:desired=1
	elif held_trash:
		if current_action!="sweeping" or elapsed<=0.0:desired=5
	elif legacy_table and elapsed>0.0:
		pass
	elif elapsed<=0.0:desired=_cleanup_role_step(record,str(staff.role))
	if desired!=int(staff.job_step):
		staff.job_step=desired;staff.job_elapsed=0.0;staff.path.clear();staff.index=0;staff.destination=Vector2i(-100,-100)
		staff.table_face_id=-1;staff.table_face_cell=Vector2i(-1,-1)
	if int(staff.job_step)>=SERVICE_STEPS.cleanup.size():
		_sync_cleanup_completion(record);_clear_service_job(staff);return
	var step=SERVICE_STEPS.cleanup[int(staff.job_step)]
	if int(staff.job_step) in [0,1] and (record.plate_owner not in ["dish_queue","clean"] or record.drink_owner=="table"):
		var sink=dishwashing.reserve(record,staff)
		if sink.is_empty():
			staff.station_id=-1;staff.blocked_guest_id=int(staff.job_guest_id);staff.blocked_target_id=-1
			staff.blocked_reason="Sinks full or blocked · waiting for space" if model.count_kind("sink")>0 else "Add a sink in Decorate"
			return
		staff.station_id=int(sink.id) if int(staff.job_step)==1 else -1
		staff.blocked_reason="";return
	if step.kind=="table":staff.station_id=-1;return
	var current=model.get_item(int(staff.station_id))
	if not current.is_empty() and current.kind==step.kind:return
	var station=_service_station(str(step.kind),Vector2i(floori(staff.pos.x),floori(staff.pos.y)),index)
	if not station.is_empty():staff.station_id=int(station.id);staff.blocked_reason="";return
	staff.station_id=-1;staff.blocked_guest_id=int(staff.job_guest_id);staff.blocked_target_id=-1
	for item in model.items:
		if item.kind==step.kind:staff.blocked_target_id=int(item.id);break
	staff.blocked_reason="Add the included trash bin in Decorate" if step.kind=="bin" and staff.blocked_target_id<0 else ("Bin sides blocked · clear any adjacent side in Decorate" if step.kind=="bin" else "%s front blocked · make space in Decorate"%str(step.kind).capitalize())

func _guest_waiting_for_meal(record:Dictionary)->bool:
	var guest:Dictionary=record.get("guest",{})
	# Ordering begins only when the arrival route reaches the actual seat.
	# Keep counting if that seat is relocated; its meal phase is preserved.
	return not bool(guest.get("meal_abandoned",false)) and str(guest.get("phase","")) in ["ordering","cooking"] and not bool(record.get("meal_done",false)) and str(record.get("plate_owner",""))!="table"

func _advance_meal_wait(delta:float):
	if not is_finite(delta) or delta<=0.0:return
	for record in service_guests.values():
		if _guest_waiting_for_meal(record):
			record.meal_wait_seconds=minf(1000000000.0,float(record.get("meal_wait_seconds",0.0))+minf(delta,60.0))

func _guest_bubble_symbol(guest:Dictionary)->String:
	var record:Dictionary=service_guests.get(int(guest.id),{})
	var waited=float(record.get("meal_wait_seconds",0.0))
	if bool(guest.get("meal_abandoned",false)) and str(guest.phase) not in ["dirty","cleaning"]:return "angry"
	if _guest_waiting_for_meal(record) and waited>=MEAL_IMPATIENCE_SECONDS:
		return "angry"
	return "…" if str(guest.phase)=="ordering" else ""

func _meal_prepared(record:Dictionary)->bool:
	var owner=str(record.plate_owner)
	if owner=="table" and int(record.plate_target_id)==int(record.guest.table_id):return true
	if owner=="counter" and int(record.plate_target_id)==int(record.meal_pass_id):
		if str(model.get_item(int(record.plate_target_id)).get("kind",""))=="counter":return true
	for worker in staff_states:
		if int(worker.job_guest_id)!=int(record.guest.id) or int(worker.job_token)!=int(record.token):continue
		# Cooking actually completed when the existing job entered plating.
		# This saved stage also covers plating and the chef's trip to the pass.
		if worker.job_kind=="cook" and int(worker.job_step)>=2:return true
		if worker.job_kind=="deliver_meal" and bool(record.meal_ready) and owner=="staff" and int(record.plate_staff_index)==staff_states.find(worker):return true
	return false

func _resolve_meal_deadlines():
	for record in service_guests.values():
		if _guest_waiting_for_meal(record) and float(record.get("meal_wait_seconds",0.0))>=MEAL_DEPARTURE_SECONDS and not _meal_prepared(record):
			_abandon_unfinished_meal(record)

func _abandon_unfinished_meal(record:Dictionary):
	var guest:Dictionary=record.guest
	if bool(guest.get("meal_abandoned",false)):return
	var old_token=int(record.token);var cleanup_workers=[]
	for worker in staff_states:
		if int(worker.get("blocked_guest_id",-1))==int(guest.id):
			worker.blocked_reason="";worker.blocked_guest_id=-1;worker.blocked_target_id=-1
		if int(worker.job_guest_id)!=int(guest.id) or int(worker.job_token)!=old_token:continue
		if worker.job_kind=="cleanup":
			# Existing real cleanup retains its work/payload under the new token.
			cleanup_workers.append(worker);continue
		_clear_service_job(worker)
		worker.path.clear();worker.index=0;worker.destination=Vector2i(-100,-100)
		worker.yield_time=0.0;worker.blocked_time=0.0;worker.stalled_time=0.0
		_set_staff_art(worker,"idle",{},0.0,"none")
	service_serial+=1;record.token=service_serial
	for worker in cleanup_workers:worker.job_token=record.token
	record.pass_reserved=false;record.meal_station_id=-1;record.meal_pass_id=-1;record.drink_station_id=-1
	record.meal_ready=false;record.meal_done=false
	# Discard only unfinished kitchen payloads. A delivered cup and existing
	# carried/queued dirty dishes still belong to the normal cleanup lifecycle.
	if record.plate_owner in ["kitchen","station"]:
		record.plate_owner="clean";record.plate_staff_index=-1;record.plate_target_id=-1
	if record.drink_owner!="table":
		record.drink_owner="cleared";record.drink_staff_index=-1;record.drink_target_id=-1
	else:
		record.dishes_collected=false;record.table_wiped=false
	if record.plate_owner=="clean" and record.drink_owner=="cleared":
		record.dishes_collected=true;record.table_wiped=true;record.dish_sink_id=-1
	_sync_cleanup_completion(record)
	model.abandon_meal(guest)
	_retire_service_station_references()

func _tick_live_service(delta: float):
	_sync_service_guests()
	# Advance before model movement: a guest reaching its seat this tick starts
	# at zero, and none of the arrival tick is mistaken for seated waiting.
	_advance_meal_wait(delta)
	# Preserve the model's phase lengths and save API. Only postpone a phase's
	# completion while its real service trip is unfinished; other guests keep
	# walking/eating. This prevents a plate teleport or a table cleaning itself.
	var held=[]
	for guest in model.customers:
		if not guest.get("mobility",{}).is_empty():continue
		var record=service_guests[int(guest.id)]
		var key={"ordering":"order_done","cooking":"meal_done","drinking":"drink_done","cleaning":"cleanup_done"}.get(str(guest.phase),"")
		if key=="" or bool(record[key]): continue
		held.append({"guest":guest,"phase":str(guest.phase),"duration":float(guest.duration)})
		guest.duration=1.0e12
	model.guest_obstacle_positions.clear()
	for staff in staff_states:model.guest_obstacle_positions.append(staff.pos)
	model.tick(delta)
	floor_tasks.observe_walks()
	var payroll=model.advance_payroll(delta,_staff_on_duty())
	if payroll.paid>0:
		if compact_ui!=null:compact_ui.show_wage_payment(int(payroll.paid))
	elif payroll.charged>0 and payroll.due>0:
		if compact_ui!=null:compact_ui.show_wages_due(int(payroll.due))
	for entry in held:
		if str(entry.guest.phase)==entry.phase:
			entry.guest.duration=entry.duration
			entry.guest.elapsed=0.0 if entry.phase=="drinking" else minf(float(entry.guest.elapsed),entry.duration)
	_sync_service_guests()

func _staff_walkable(cell: Vector2i) -> bool:
	if cell.x<1 or not model.is_floor_owned(cell): return false
	var item=model.item_at(cell.x,cell.y)
	return item.is_empty() or str(item.kind)=="rug"

func _static_service_path(from: Vector2i, to: Vector2i) -> Array:
	# Furniture-only reachability is stable while a layout is unchanged. Cache
	# it with a hard size cap; actor bodies are not part of navigation.
	if static_service_revision!=model.revision:
		static_service_paths.clear();static_service_revision=model.revision
	var key=Vector4i(from.x,from.y,to.x,to.y)
	if static_service_paths.has(key): return static_service_paths[key]
	if static_service_paths.size()>=4096: static_service_paths.clear()
	var path=model.path_between(from,to)
	static_service_paths[key]=path
	return path

func _service_cell(item: Dictionary, from=Vector2i(7,1), claimed=[], role="") -> Vector2i:
	if item.is_empty(): return Vector2i(-1,-1)
	if str(item.kind)=="table":
		var best=Vector2i(-1,-1);var shortest=1000000
		for side in model.table_service_cells(item):
			if claimed.has(side):continue
			var route=_static_service_path(from,side)
			if not route.is_empty() and route.size()<shortest:best=side;shortest=route.size()
		return best
	if str(item.kind)=="bin":
		var best=Vector2i(-1,-1);var shortest=1000000
		for cell in model.bin_service_cells(item):
			if claimed.has(cell):continue
			var route=_static_service_path(from,cell)
			if not route.is_empty() and route.size()<shortest:best=cell;shortest=route.size()
		return best
	# Directional stations have one designated rotated +z workface. A blocked
	# front is unavailable; no actor is silently sent around to work from behind.
	if str(item.kind) in ["stove","beverage","sink","counter","register"]:
		var face=model.workface_cell(item)
		if (str(item.kind)=="counter" and role=="chef") or (str(item.kind)=="register" and role=="cashier"): face=Vector2i(int(item.x),int(item.z))*2-face
		if not _staff_walkable(face) or claimed.has(face) or model.edge_blocked(Vector2i(int(item.x),int(item.z)),face): return Vector2i(-1,-1)
		return face if not _static_service_path(from,face).is_empty() else Vector2i(-1,-1)
	var front=[Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT][posmod(int(item.get("rot",0)),4)]
	var directions=[front,Vector2i(front.y,-front.x),Vector2i(-front.y,front.x),-front]
	for direction in directions:
		var cell=Vector2i(int(item.x),int(item.z))+direction
		if not _staff_walkable(cell) or claimed.has(cell) or model.edge_blocked(Vector2i(int(item.x),int(item.z)),cell): continue
		if not _static_service_path(from,cell).is_empty(): return cell
	return Vector2i(-1,-1)

func _item_service_locked(id: int) -> bool:
	if Checkout.busy(model,id) or dishwashing.busy(id):return true
	# The paused decorating UI cannot remove the surface currently holding an
	# action or a dish. Unused stations remain freely editable.
	for staff in staff_states:
		if staff.job_kind!="" and int(staff.station_id)==id: return true
		var target=_service_target(staff)
		if not target.is_empty() and int(target.id)==id: return true
	for record in service_guests.values():
		if bool(record.get("pass_reserved",false)) and int(record.get("meal_pass_id",-1))==id: return true
		if record.plate_owner in ["counter","station"] and int(record.plate_target_id)==id: return true
		if record.drink_owner=="station" and int(record.drink_target_id)==id: return true
		if record.plate_owner=="sink" and int(record.plate_target_id)==id: return true
		if str(record.get("trash_owner","none"))=="bin" and int(record.get("trash_target_id",-1))==id:return true
	return false

func _service_target(staff: Dictionary) -> Dictionary:
	if staff.job_kind=="wash":return dishwashing.target(staff)
	if staff.job_kind=="floor":return floor_tasks.target(staff)
	if staff.job_kind=="" or not service_guests.has(int(staff.job_guest_id)): return {}
	var steps=SERVICE_STEPS[staff.job_kind]
	if int(staff.job_step)<0 or int(staff.job_step)>=steps.size():return {}
	var kind=str(steps[int(staff.job_step)].kind)
	if staff.job_kind=="cleanup" and int(staff.job_step)==0 and int(service_guests[int(staff.job_guest_id)].get("dish_sink_id",-1))<0:return {}
	var guest=service_guests[int(staff.job_guest_id)].guest
	if kind=="counter" and staff.role=="chef": return model.get_item(int(service_guests[int(staff.job_guest_id)].meal_pass_id))
	return model.get_item(int(guest.table_id) if kind=="table" else int(staff.station_id))

func _clear_service_job(staff: Dictionary):
	if staff.job_kind=="cleanup" and service_guests.has(int(staff.job_guest_id)):
		var record=service_guests[int(staff.job_guest_id)]
		if record.plate_owner!="staff":record.dish_sink_id=-1
	staff.job_guest_id=-1; staff.job_mess_id=-1;staff.job_dish_id=-1;staff.job_token=-1; staff.job_kind=""; staff.job_step=0; staff.job_elapsed=0.0; staff.station_id=-1
	staff.table_face_id=-1;staff.table_face_cell=Vector2i(-1,-1)
	_retire_service_station_references()

func _retire_service_station_references():
	# These IDs locate unfinished physical work; completed meals do not keep
	# an idle stove, pass or beverage station alive as historical provenance.
	for record in service_guests.values():
		var needs_stove=record.plate_owner=="station"
		var needs_pass=bool(record.pass_reserved) or record.plate_owner=="counter"
		var needs_drink=record.drink_owner=="station"
		for worker in staff_states:
			if int(worker.job_guest_id)!=int(record.guest.id) or int(worker.job_token)!=int(record.token):continue
			match str(worker.job_kind):
				"cook":
					needs_stove=true
					if int(worker.job_step)==3:needs_pass=true
				"deliver_meal":needs_pass=true
				"brew","deliver_drink":needs_drink=true
		if not needs_stove:record.meal_station_id=-1
		if not needs_pass:record.meal_pass_id=-1
		if not needs_drink:record.drink_station_id=-1

func _service_station(kind: String, from: Vector2i, staff_index: int) -> Dictionary:
	for item in model.items:
		if str(item.kind)!=kind: continue
		var busy=false
		for record in service_guests.values():
			if (record.plate_owner=="station" and int(record.plate_target_id)==int(item.id)) or (record.drink_owner=="station" and int(record.drink_target_id)==int(item.id)): busy=true;break
		for index in staff_states.size():
			if index==staff_index: continue
			var other=staff_states[index]
			if other.job_kind!="" and int(other.station_id)==int(item.id) and not _service_target(other).is_empty() and int(_service_target(other).id)==int(item.id): busy=true; break
		if not busy and _service_cell(item,from)!=Vector2i(-1,-1): return item
	return {}

func _reserve_pass(staff: Dictionary):
	var record=service_guests[int(staff.job_guest_id)]
	if int(record.meal_pass_id)>=0: return
	var from=Vector2i(floori(staff.pos.x),floori(staff.pos.y))
	var any_counter=false
	var full=false
	for item in model.items:
		if str(item.kind)!="counter": continue
		any_counter=true;staff.blocked_target_id=int(item.id)
		if _service_cell(item,from,[],"chef")==Vector2i(-1,-1) or _service_cell(item,from,[],"waiter")==Vector2i(-1,-1): continue
		var reserved=false
		for other in service_guests.values():
			if bool(other.get("pass_reserved",false)) and int(other.get("meal_pass_id",-1))==int(item.id): reserved=true;break
		if reserved: full=true;continue
		record.meal_pass_id=int(item.id);record.pass_reserved=true;staff.blocked_reason="";return
	staff.blocked_reason="Pass counter full · waiting for the waiter" if full else ("Pass counter blocked · clear its back and front in Decorate" if any_counter else "Add a pass counter in Decorate")
	staff.blocked_guest_id=int(staff.job_guest_id)

func _mark_blocked_job(staff: Dictionary, guest: Dictionary, kind: String):
	staff.blocked_guest_id=int(guest.id);staff.blocked_target_id=-1
	var station_kind={"cook":"stove","brew":"beverage","cleanup":"sink","deliver_meal":"counter","deliver_drink":"beverage","order":"table","take_payment":"register"}[kind]
	var from=Vector2i(floori(staff.pos.x),floori(staff.pos.y))
	var has_usable=false
	for item in model.items:
		if str(item.kind)!=station_kind or (station_kind=="table" and int(item.id)!=int(guest.table_id)): continue
		staff.blocked_target_id=int(item.id)
		if _service_cell(item,from,[],str(staff.role))!=Vector2i(-1,-1): has_usable=true;break
	staff.blocked_reason="Waiting for a free %s"%station_kind if has_usable else ("Table service side blocked · make space beside the diner in Decorate" if station_kind=="table" else ("%s front blocked · make space in Decorate"%station_kind.capitalize() if staff.blocked_target_id>=0 else "Add a %s in Decorate"%station_kind))

func _cleanup_ready(guest: Dictionary) -> bool:
	if bool(guest.get("withdrawn",false)):return false
	if str(guest.phase) in ["dirty","cleaning"]: return true
	if str(guest.phase)!="leaving" or bool(guest.get("seated",false)): return false
	var chair=model.get_item(int(guest.chair_id))
	var table=model.get_item(int(guest.table_id))
	if chair.is_empty() or table.is_empty(): return false
	var position=Vector2(float(guest.x),float(guest.z))
	return position.distance_to(Vector2(chair.x+.5,chair.z+.5))>.9 and position.distance_to(Vector2(table.x+.5,table.z+.5))>1.3

func _assign_service_job(staff: Dictionary, index: int):
	if not bool(staff.get("on_duty",true)) or bool(staff.get("duty_pending",false)):return
	staff.blocked_reason="";staff.blocked_target_id=-1;staff.blocked_guest_id=-1
	var from=Vector2i(floori(staff.pos.x),floori(staff.pos.y))
	if dishwashing.assign(staff,index):return
	for kind in ROLE_JOBS[str(staff.role)]:
		for guest in model.customers:
			if bool(guest.get("withdrawn",false)):continue
			if bool(guest.get("meal_abandoned",false)) and kind!="cleanup":continue
			var record=service_guests[int(guest.id)]
			var phase=str(guest.phase)
			if kind=="take_payment" and not model.checkout_ready(guest,int(guest.get("checkout_register_id",-1))):continue
			if kind=="order" and (phase!="ordering" or record.order_done): continue
			if kind=="cook" and (phase!="cooking" or record.meal_ready): continue
			if kind=="brew" and (phase!="drinking" or record.drink_ready): continue
			if kind=="deliver_meal" and (phase!="cooking" or not record.meal_ready or record.meal_done): continue
			if kind=="deliver_drink" and (phase!="drinking" or not record.drink_ready or record.drink_done): continue
			if kind=="cleanup" and (not _cleanup_ready(guest) or record.cleanup_done or _cleanup_role_step(record,str(staff.role))>=SERVICE_STEPS.cleanup.size()): continue
			var assigned=false
			for other in staff_states:
				if int(other.job_guest_id)==int(guest.id) and int(other.job_token)==int(record.token): assigned=true;break
			if assigned: continue
			if kind=="cleanup":
				var cleanup_step=_cleanup_role_step(record,str(staff.role))
				if str(SERVICE_STEPS.cleanup[cleanup_step].action) in ["sweeping","mopping"] and floor_tasks.destination_for_record(record,staff,from,[])==Vector2i(-1,-1):
					staff.blocked_reason="Floor cleanup side blocked · make space beside the mess in Decorate";staff.blocked_target_id=int(guest.table_id);staff.blocked_guest_id=int(guest.id)
					continue
				# Floor work must not depend on a sink or a table-service face.
				staff.job_kind=kind;staff.job_guest_id=int(guest.id);staff.job_token=int(record.token)
				staff.job_step=_cleanup_role_step(record,str(staff.role));staff.job_elapsed=0.0;staff.station_id=-1
				staff.table_face_id=-1;staff.table_face_cell=Vector2i(-1,-1);staff.yield_time=0.0
				_prepare_cleanup_step(staff,index);return
			var station={}
			if kind=="take_payment":station=model.get_item(int(guest.checkout_register_id))
			elif kind=="order": station=model.get_item(int(guest.table_id))
			elif kind=="deliver_meal": station=model.get_item(int(record.meal_pass_id))
			elif kind=="deliver_drink": station=model.get_item(int(record.drink_station_id))
			else: station=_service_station({"cleanup":"sink","brew":"beverage","cook":"stove"}[kind],from,index)
			if station.is_empty() or _service_cell(station,from,[],str(staff.role))==Vector2i(-1,-1):
				_mark_blocked_job(staff,guest,kind);continue
			staff.blocked_reason="";staff.blocked_target_id=-1;staff.blocked_guest_id=-1
			staff.job_kind=kind;staff.job_guest_id=int(guest.id);staff.job_token=int(record.token)
			staff.job_step=0;staff.job_elapsed=0.0;staff.station_id=int(station.id)
			staff.table_face_id=-1;staff.table_face_cell=Vector2i(-1,-1);staff.yield_time=0.0
			if kind=="take_payment":guest.checkout_token=int(record.token)
			if kind=="cook": record.meal_station_id=int(station.id)
			if kind=="brew": record.drink_station_id=int(station.id)
			return

	floor_tasks.assign(staff,index)

func _is_door_landing(cell:Vector2i)->bool:
	var point=Vector2(cell.x+.5,cell.y+.5)
	for attachment in model.wall_attachments:
		if attachment.kind!="door":continue
		var opening=model.OpeningGeometry.aperture(attachment,model.built_walls,model.shell_material)
		if not opening.is_empty() and Geometry2D.get_closest_point_to_segment(point,opening.a,opening.b).distance_to(point)<.76:return true
	return false

func _standby_cell_static(cell:Vector2i)->bool:
	if not _staff_walkable(cell) or _is_station_workface(cell) or _is_door_landing(cell) or cell==Model.ENTRY_LANDING or cell==Model.ENTRANCE:return false
	# Keep the perimeter entry lanes, dining faces and narrow passages clear.
	if cell.x<=1 or cell.x>=model.width-1 or cell.y>=model.depth-1:return false
	var exits=0
	for direction in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		var neighbor=cell+direction
		if _staff_walkable(neighbor) and not model.edge_blocked(cell,neighbor):exits+=1
		var item=model.item_at(neighbor.x,neighbor.y)
		if not item.is_empty() and item.kind in ["table","chair","bench"]:return false
	if exits<3:return false
	return true

func _refresh_idle_homes():
	if idle_home_revision==model.revision and idle_home_count==staff_states.size():return
	idle_home_revision=model.revision;idle_home_count=staff_states.size()
	var reserved=[];var stoves=[]
	var reachable=model._sale_reachable_in(model.items)
	for item in model.items:
		if item.kind=="stove" and model._sale_station_usable_in(item,model.items,reachable):stoves.append(item)
	# Keep every still-usable home before assigning a replacement. Otherwise an
	# earlier blocked chef can steal a later chef's working stove by array order.
	var retained={}
	for index in range(staff_states.size()):
		var staff=staff_states[index]
		if staff.role!="chef" or not bool(staff.get("on_duty",true)):continue
		for stove in stoves:
			if int(stove.id)==int(staff.get("idle_home_id",-1)) and not reserved.has(model.workface_cell(stove)):
				retained[index]=stove;reserved.append(model.workface_cell(stove));break
	for index in range(staff_states.size()):
		var staff=staff_states[index]
		if staff.role!="chef" or not bool(staff.get("on_duty",true)):continue
		var home:Dictionary=retained.get(index,{})
		if home.is_empty():
			for stove in stoves:
				if not reserved.has(model.workface_cell(stove)):
					home=stove;reserved.append(model.workface_cell(stove));break
		staff.idle_home_id=int(home.id) if not home.is_empty() else -1
		staff.idle_home_cell=model.workface_cell(home) if not home.is_empty() else Vector2i(-1,-1)
	for index in range(staff_states.size()):
		var staff=staff_states[index]
		if staff.role=="chef" and bool(staff.get("on_duty",true)):continue
		if staff.role=="cashier":
			var register=model.checkout_register()
			staff.idle_home_id=int(register.get("id",-1));staff.idle_home_cell=model.checkout_rear(register) if not register.is_empty() else Vector2i(-1,-1)
			if not register.is_empty():reserved.append(staff.idle_home_cell)
			continue
		var anchor={}
		var anchor_kind="counter" if staff.role=="waiter" else "sink"
		for item in model.items:
			if item.kind==anchor_kind:anchor=item;break
		var focus=Vector2i(int(anchor.get("x",6)),int(anchor.get("z",1)))
		var candidates=[]
		for z in range(model.depth):
			for x in range(2,model.width-1):
				var cell=Vector2i(x,z)
				if not _standby_cell_static(cell) or reserved.has(cell):continue
				if _static_service_path(Model.ENTRY_LANDING,cell).is_empty():continue
				candidates.append(cell)
		candidates.sort_custom(func(a,b):
			var da=absi(a.x-focus.x)+absi(a.y-focus.y);var db=absi(b.x-focus.x)+absi(b.y-focus.y)
			return da<db if da!=db else (a.y<b.y if a.y!=b.y else a.x<b.x))
		staff.idle_home_id=int(anchor.get("id",-1));staff.idle_home_cell=candidates[0] if not candidates.is_empty() else Vector2i(-1,-1)
		if not candidates.is_empty():reserved.append(candidates[0])

func _idle_cell_clear(cell:Vector2i,_index:int,claimed:Array)->bool:
	# Keep distinct standing destinations, without moving aside for traffic.
	return _staff_walkable(cell) and not model.checkout_claims().has(cell) and not _is_door_landing(cell) and not claimed.has(cell)

func _idle_obstructs_guest(_point:Vector2,_guest:Dictionary)->bool:
	# Compatibility helper: people can pass through other people.
	return false

func _staff_idle_cell(index: int, claimed: Array, allow_home:bool=true) -> Vector2i:
	_refresh_idle_homes()
	var staff=staff_states[index]
	var from=Vector2i(floori(staff.pos.x),floori(staff.pos.y))
	var home:Vector2i=staff.get("idle_home_cell",Vector2i(-1,-1))
	var station=model.get_item(int(staff.get("idle_home_id",-1)))
	var physical_home_ok=allow_home and home!=Vector2i(-1,-1) and _staff_walkable(home) and not _static_service_path(from,home).is_empty()
	if staff.role=="chef" and bool(staff.get("on_duty",true)) and not station.is_empty():physical_home_ok=physical_home_ok and not model.edge_blocked(home,Vector2i(int(station.x),int(station.z)))
	if staff.role=="chef" and bool(staff.get("on_duty",true)) and staff.job_kind=="" and not physical_home_ok and staff.blocked_reason=="" and model.count_kind("stove")==0:
		staff.blocked_reason="Add a stove"
		staff.blocked_target_id=int(station.get("id",-1))
	if physical_home_ok and _idle_cell_clear(home,index,claimed):
		if float(staff.get("idle_return_delay",0.0))<=0.0:return home
	else:staff.idle_return_delay=1.5
	# Choose a free standing destination if the home is statically unavailable
	# or reserved for work. The designated home never follows traffic.
	var candidates=[]
	for z in range(model.depth):
		for x in range(1,model.width):
			var cell=Vector2i(x,z)
			if _is_station_workface(cell) or not _idle_cell_clear(cell,index,claimed):continue
			var another_home=false
			for peer in staff_states:
				if not is_same(peer,staff) and peer.get("idle_home_cell",Vector2i(-1,-1))==cell:another_home=true;break
			if another_home or _static_service_path(from,cell).is_empty():continue
			candidates.append(cell)
	candidates.sort_custom(func(a,b):
		var da=absi(a.x-from.x)+absi(a.y-from.y);var db=absi(b.x-from.x)+absi(b.y-from.y)
		return da<db if da!=db else (a.y<b.y if a.y!=b.y else a.x<b.x))
	return candidates[0] if not candidates.is_empty() else from

func _staff_route(index: int, destination: Vector2i) -> Array:
	var staff=staff_states[index]
	var start=Vector2i(floori(staff.pos.x),floori(staff.pos.y))
	# Transit is constrained only by owned floor, furniture and walls.
	var frontier=[start]
	var came={start:start}
	var cursor=0
	while cursor<frontier.size():
		var cell=frontier[cursor]; cursor+=1
		if cell==destination:
			var path=[cell]
			while path[-1]!=start: path.append(came[path[-1]])
			path.reverse()
			if staff.pos.distance_to(Vector2(start.x+.5,start.y+.5))<.015: path.pop_front()
			return path
		for direction in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
			var next=cell+direction
			if not _staff_walkable(next) or came.has(next) or model.edge_blocked(cell,next): continue
			came[next]=cell; frontier.append(next)
	return []

func _staff_in_transit(staff: Dictionary) -> bool:
	var center=Vector2(roundi(staff.pos.x-.5)+.5,roundi(staff.pos.y-.5)+.5)
	return staff.pos.distance_to(center)>.015

func _staff_cell_claimed(cell: Vector2i, index: int, _guest_yield=false) -> bool:
	# Destination ownership is separate from floor transit. This helper is
	# used only to pick a workface, never to stop someone crossing its tile.
	if model.checkout_claims().has(cell):return true
	for other_index in staff_states.size():
		if other_index==index:continue
		var other=staff_states[other_index]
		if other.job_kind!="" and (other.destination==cell or other.get("table_face_cell",Vector2i(-1,-1))==cell):return true
	return false

func _try_peer_retreat(_index: int) -> bool:
	# Legacy diagnostic hook. Pass-through actors never need a deadlock yield.
	return false

func _staff_payload(staff: Dictionary, index: int) -> String:
	if staff.job_kind=="floor":return floor_tasks.payload(staff,index)
	if not service_guests.has(int(staff.job_guest_id)): return "none"
	var record=service_guests[int(staff.job_guest_id)]
	if record.plate_owner=="staff" and int(record.plate_staff_index)==index: return "plate" if staff.job_kind in ["cook","deliver_meal"] else "dishes"
	if record.drink_owner=="staff" and int(record.drink_staff_index)==index: return "drink"
	if str(record.get("trash_owner","none"))=="staff" and int(record.get("trash_staff_index",-1))==index:return "trash"
	return "none"

func _service_contact(staff: Dictionary, index: int, action: String, target: Dictionary, phase: float):
	if staff.job_kind=="wash":dishwashing.contact(staff);return
	if staff.job_kind=="floor":floor_tasks.contact(staff,index,action,target,phase);return
	var record:Dictionary=service_guests.get(int(staff.job_guest_id),{})
	if record.is_empty() or int(staff.job_token)!=int(record.token):return
	if bool(record.guest.get("meal_abandoned",false)) and staff.job_kind!="cleanup":return
	if action=="plating" and phase>=.65:
		record.plate_owner="staff";record.plate_staff_index=index;record.plate_target_id=-1
	elif action=="placing_plate" and phase>=.65:
		record.plate_owner="counter";record.plate_staff_index=-1;record.plate_target_id=int(target.id)
	elif action=="preparing_drink" and phase>=1.0:
		record.drink_owner="station";record.drink_staff_index=-1;record.drink_target_id=int(target.id)
	elif action=="collecting_plate" and phase>=.65:
		record.plate_owner="staff";record.plate_staff_index=index;record.plate_target_id=-1
		record.pass_reserved=false
	elif action=="collecting_drink" and phase>=.65:
		record.drink_owner="staff";record.drink_staff_index=index;record.drink_target_id=-1
	elif action=="serving" and phase>=.65:
		if staff.job_kind=="deliver_meal":
			record.plate_owner="table";record.plate_staff_index=-1;record.plate_target_id=int(target.id)
		else:
			record.drink_owner="table";record.drink_staff_index=-1;record.drink_target_id=int(target.id)
	elif action=="collecting" and phase>=.65:
		record.dishes_collected=true
		record.plate_owner="staff";record.plate_staff_index=index;record.plate_target_id=-1
		record.drink_owner="cleared";record.drink_staff_index=-1;record.drink_target_id=-1
	elif action=="sweeping" and phase>=1.0:
		record.trash_owner="staff";record.trash_staff_index=index;record.trash_target_id=-1
	elif action=="disposing_trash" and phase>=.65:
		record.trash_owner="disposed" if phase>=1.0 else "bin"
		record.trash_staff_index=-1;record.trash_target_id=int(target.id) if phase<1.0 else -1
	elif action=="mopping":
		record.spill_remaining=minf(float(record.spill_remaining),1.0-smoothstep(0.0,1.0,phase))
		if phase>=1.0:record.spill_cleaned=true;record.spill_remaining=0.0
	elif action=="dropping_dishes" and phase>=.65:
		dishwashing.deposit(record,staff,index,target)

func _set_staff_art(staff: Dictionary, action: String, target: Dictionary, phase: float, payload="none"):
	staff.art_action=action; staff.art_phase=clampf(phase,0.0,1.0); staff.art_payload=payload
	staff.art_tool="broom" if action=="sweeping" else ("dustpan" if payload=="trash" or action=="disposing_trash" else ("cloth" if action=="wiping" else ("mop" if action=="mopping" else ("notepad" if action=="taking_order" else "none"))))
	staff.art_service_kind={"cook":"meal","deliver_meal":"meal","brew":"drink","deliver_drink":"drink"}.get(str(staff.job_kind),str(staff.job_kind))
	staff.art_role=str(staff.role)
	staff.art_block_reason=str(staff.blocked_reason)
	staff.art_contact=phase>=float({"serving":.65,"placing_plate":.65,"collecting":.65,"collecting_plate":.65,"collecting_drink":.65,"washing":.0,"dropping_dishes":.65,"plating":.65,"preparing_drink":1.0,"sweeping":1.0,"disposing_trash":.65,"mopping":1.0}.get(action,1.0))
	staff.art_guest_id=int(staff.job_guest_id)
	staff.art_guest_phase=str(service_guests[int(staff.job_guest_id)].guest.phase) if service_guests.has(int(staff.job_guest_id)) else ""
	staff.art_target=Vector2(target.x+.5,target.z+.5) if not target.is_empty() else staff.pos
	staff.art_target_id=int(target.id) if not target.is_empty() else -1
	if service_guests.has(int(staff.job_guest_id)):
		var record=service_guests[int(staff.job_guest_id)]
		if action in ["sweeping","mopping"]:staff.art_target=floor_tasks.contact_target(record,staff,action)
	if staff.job_kind=="floor":
		var floor_record=floor_tasks.record(staff)
		if not floor_record.is_empty():
			if action in ["sweeping","mopping"]:staff.art_target=floor_tasks.contact_target(floor_record,staff,action)
	staff.art_station=staff.art_target

func _animate_staff(delta: float):
	_sync_service_guests()
	_refresh_idle_homes()
	for staff in staff_states:staff.idle_return_delay=maxf(0.0,float(staff.get("idle_return_delay",0.0))-delta)
	# Drop only stale runtime jobs (guest removed/reset or its furnishing gone).
	for staff in staff_states:
		if staff.job_kind=="": continue
		if staff.job_kind=="wash":
			if dishwashing.entry(staff).is_empty():_clear_service_job(staff)
			continue
		if staff.job_kind=="floor":
			if floor_tasks.record(staff).is_empty():_clear_service_job(staff)
			else:floor_tasks.release_blocked(staff)
			continue
		if not service_guests.has(int(staff.job_guest_id)) or int(service_guests[int(staff.job_guest_id)].token)!=int(staff.job_token): _clear_service_job(staff)
		elif _is_floor_cleanup(staff) and float(staff.job_elapsed)<=0.0:
			# Legacy diner-owned floor work follows the same pre-contact rule.
			var record=service_guests[int(staff.job_guest_id)]
			var from=Vector2i(floori(staff.pos.x),floori(staff.pos.y))
			if str(record.trash_owner) not in ["staff","bin"] and floor_tasks.destination_for_record(record,staff,from,[])==Vector2i(-1,-1):_clear_service_job(staff)
		elif staff.job_kind=="take_payment" and bool(service_guests[int(staff.job_guest_id)].guest.paid):_clear_service_job(staff)
		elif staff.job_kind=="cook" and str(SERVICE_STEPS.cook[int(staff.job_step)].kind)=="counter": _reserve_pass(staff)
	for index in staff_states.size():
		if staff_states[index].job_kind=="": _assign_service_job(staff_states[index],index)
	for index in range(staff_states.size()):
		_prepare_cleanup_step(staff_states[index],index);floor_tasks.prepare(staff_states[index],index)
	active_staff_passages.clear() # Retained runtime field; no physical transit claims.
	var claimed=[]
	var worked_stations={}
	for index in range(staff_states.size()):
		var staff=staff_states[index]
		var target_item=_service_target(staff)
		var from=Vector2i(floori(staff.pos.x),floori(staff.pos.y))
		var destination=_service_destination(staff,target_item,from,claimed) if not target_item.is_empty() else _staff_idle_cell(index,claimed)
		var interaction_available=destination!=Vector2i(-1,-1)
		if not target_item.is_empty() and _service_destination(staff,target_item,from)==Vector2i(-1,-1):
			staff.blocked_reason="Waiting for the sink" if str(target_item.kind)=="sink" and not dishwashing.workface_available(staff,int(target_item.id)) else ("Floor cleanup side blocked · make space beside the mess in Decorate" if _is_floor_cleanup(staff) else ("Table service side blocked · make space beside the diner in Decorate" if str(target_item.kind)=="table" else "Work side blocked · make space in Decorate"));staff.blocked_target_id=int(target_item.id);staff.blocked_guest_id=int(staff.job_guest_id)
		elif not target_item.is_empty(): staff.blocked_reason=""
		if not interaction_available: destination=_staff_idle_cell(index,claimed,str(target_item.get("kind",""))!="stove")
		# v13 may restore an old avoidance timer; it has no effect on work now.
		staff.yield_time=0.0
		claimed.append(destination)
		var at_destination=staff.pos.distance_to(Vector2(destination.x+.5,destination.y+.5))<.03
		var route_invalid=false
		var route_point:Vector2=staff.pos
		for route_index in range(int(staff.index),staff.path.size()):
			var route_cell:Vector2i=staff.path[route_index]
			var next_point=Vector2(route_cell.x+.5,route_cell.y+.5)
			if not _staff_walkable(route_cell) or model.segment_blocked(route_point,next_point): route_invalid=true; break
			route_point=next_point
		if route_invalid or staff.destination!=destination or (not at_destination and (staff.blocked_time>.25 or (not staff.path.is_empty() and staff.index>=staff.path.size()))):
			staff.destination=destination
			staff.path=_staff_route(index,destination)
			staff.index=0; staff.blocked_time=0.0
		var payload=_staff_payload(staff,index)
		var travel_action={"plate":"carrying_to_pass" if staff.role=="chef" else "carrying_plate","drink":"carrying_drink","dishes":"carrying_dishes","trash":"carrying_trash"}.get(payload,"walking")
		_set_staff_art(staff,travel_action if not at_destination or payload!="none" else "idle",target_item,0.0,payload)
		var moved=false
		if staff.index<staff.path.size():
			var cell=staff.path[staff.index]
			var point=Vector2(cell.x+.5,cell.y+.5)
			var proposed=staff.pos.move_toward(point,delta*1.8)
			# Static obstacles remain solid; actor bodies and future legs do not.
			var blocked=not _staff_walkable(cell) or model.segment_blocked(staff.pos,point)
			if not blocked:
				var direction=point-staff.pos
				if direction.length()>.005:
					staff.node.rotation.y=atan2(direction.x,direction.y); staff.art_heading=direction
				moved=staff.pos.distance_to(proposed)>.0001; staff.pos=proposed; staff.blocked_time=0.0
				if staff.pos.distance_to(point)<.015: staff.index+=1
			else:
				staff.blocked_time+=delta
		elif not at_destination: staff.blocked_time+=delta
		staff.stalled_time=float(staff.get("stalled_time",0.0))+delta if not moved and not at_destination else 0.0
		staff.node.position=Vector3(staff.pos.x,abs(sin(animation_time*11+index))*.025 if moved else 0.0,staff.pos.y)
		if staff.blocked_reason!="" and (not moved or target_item.is_empty()):
			var blocked_item=model.get_item(int(staff.blocked_target_id))
			# An intentionally unavailable stove is quiet during service.
			var action="idle" if str(blocked_item.get("kind",""))=="stove" and not editing else "blocked"
			_set_staff_art(staff,action,blocked_item,0.0,payload)
			if staff.job_kind=="":
				staff.art_guest_id=int(staff.blocked_guest_id)
				staff.art_guest_phase=str(service_guests[int(staff.blocked_guest_id)].guest.phase) if service_guests.has(int(staff.blocked_guest_id)) else ""
		if staff.job_kind=="" and staff.yield_time<=0 and not moved and staff.blocked_reason=="":
			var home:Vector2i=staff.get("idle_home_cell",Vector2i(-1,-1))
			if staff.pos.distance_to(Vector2(home.x+.5,home.y+.5))<.03:
				var home_item=model.get_item(int(staff.get("idle_home_id",-1)))
				_set_staff_art(staff,"standby" if bool(staff.get("on_duty",true)) else "off_duty",home_item,fposmod(animation_time*.16+index*.17,1.0),"none")
		# Gestures run only adjacent to the intended item, while fully arrived and
		# not yielding. Travel never advances a preparation/serving/wiping clock.
		if staff.job_kind=="" or staff.yield_time>0 or target_item.is_empty() or not interaction_available: continue
		if staff.pos.distance_to(Vector2(destination.x+.5,destination.y+.5))>=.03: continue
		if not _is_floor_cleanup(staff) and absi(destination.x-int(target_item.x))+absi(destination.y-int(target_item.z))!=1: continue
		if not _is_floor_cleanup(staff) and model.edge_blocked(destination,Vector2i(int(target_item.x),int(target_item.z))):continue
		if destination!=_service_destination(staff,target_item,from):continue
		var step=SERVICE_STEPS[staff.job_kind][int(staff.job_step)]
		if service_guests.has(int(staff.job_guest_id)) and not service_guests[int(staff.job_guest_id)].guest.get("mobility",{}).is_empty() and str(step.kind) in ["table","register"]:continue
		var action_seconds=float(step.seconds)
		if str(step.action)=="cooking": action_seconds=Model.cooking_seconds(Model.stove_speed_multiplier(target_item))
		var station_busy=worked_stations.has(int(target_item.id))
		if str(step.kind) not in ["table","sink"]:
			for other_index in staff_states.size():
				if other_index==index: continue
				var other=staff_states[other_index]
				var other_target=_service_target(other)
				if other_target.is_empty() or int(other_target.id)!=int(target_item.id): continue
				if float(other.job_elapsed)>0.0 or (other_index<index and float(staff.job_elapsed)<=0.0): station_busy=true; break
		if station_busy: continue
		if str(step.kind)!="table": worked_stations[int(target_item.id)]=true
		if staff.job_kind=="take_payment":
			var paying_guest=service_guests[int(staff.job_guest_id)].guest
			if not model.begin_checkout_payment(int(paying_guest.id),int(paying_guest.checkout_ticket),int(target_item.id),int(staff.job_token)):continue
		staff.job_elapsed+=delta
		var phase=clampf(float(staff.job_elapsed)/action_seconds,0.0,1.0)
		if staff.job_elapsed+.000001>=action_seconds: phase=1.0
		_service_contact(staff,index,str(step.action),target_item,phase)
		payload=_staff_payload(staff,index)
		_set_staff_art(staff,str(step.action),target_item,phase,payload)
		staff.node.rotation.y=atan2(staff.art_target.x-staff.pos.x,staff.art_target.y-staff.pos.y)
		if staff.job_elapsed+0.000001<action_seconds: continue
		if staff.job_kind=="wash":dishwashing.complete(staff);continue
		if staff.job_kind=="floor":floor_tasks.complete_step(staff,index);continue
		var record=service_guests[int(staff.job_guest_id)]
		if staff.job_kind=="take_payment":
			var guest=record.guest;var token=int(staff.job_token);var register_id=int(staff.station_id)
			# Clear the completed runtime job before the model emits its atomic
			# settlement signal, so signal-triggered saves see one valid snapshot.
			if model.checkout_ready(guest,register_id):
				_clear_service_job(staff)
				model.commit_checkout_payment(int(guest.id),int(guest.checkout_ticket),register_id,token)
			continue
		if step.action=="wiping": record.table_wiped=true
		if step.action=="mopping":record.spill_cleaned=true;record.spill_remaining=0.0
		staff.job_step+=1; staff.job_elapsed=0.0
		if staff.job_kind=="cleanup":
			_prepare_cleanup_step(staff,index)
			if staff.job_kind=="":continue
		if int(staff.job_step)>=SERVICE_STEPS[staff.job_kind].size():
			if staff.job_kind=="brew":record.drink_done=true
			record[{"order":"order_done","cook":"meal_ready","brew":"drink_ready","deliver_meal":"meal_done","deliver_drink":"drink_done","cleanup":"cleanup_done"}[staff.job_kind]]=true
			_clear_service_job(staff)
	# The whole frame's real cooking and table contacts win ties at the deadline.
	if delta>0.0:_resolve_meal_deadlines()

func _find_path(start: Vector2i,goal: Vector2i) -> Array:
	# Compatibility route helper shares the authoritative partial-floor BFS.
	var path: Array = model.path_between(start,goal)
	if not path.is_empty(): path.pop_front()
	return path

func _update_service_props():
	var present={}
	for customer in model.customers:
		var record=service_guests.get(int(customer.id),{})
		if str(record.get("plate_owner","kitchen"))!="table": continue
		var id=int(customer.table_id)
		var phase="eating" if str(customer.phase) in ["cooking","drinking","eating"] else "dirty"
		present[id]=true
		if service_props.has(id) and service_props[id].phase==phase: continue
		if service_props.has(id): service_props[id].node.queue_free()
		var item=model.get_item(id)
		if item.is_empty(): continue
		var n=Node3D.new(); furnishings.add_child(n)
		n.position=Vector3(item.x+.5,0,item.z+.5)
		cylinder(n,Vector3(-.1,.87,-.04),.18,.025,CREAM)
		if phase=="eating":
			sphere(n,Vector3(-.1,.905,-.04),Vector3(.24,.07,.24),Color("d8944e"))
			for d in [Vector3(-.16,.93,-.04),Vector3(-.04,.93,0)]:sphere(n,d,Vector3(.07,.035,.06),SAGE)
		else:
			cylinder(n,Vector3(-.1,.89,-.04),.13,.005,Color("9d825c"))
			text3(n,"Clear dishes",Vector3(0,1.25,0),18,Color("826447"))
		service_props[id]={"node":n,"phase":phase}
	for id in service_props.keys():
		if not present.has(id): service_props[id].node.queue_free(); service_props.erase(id)

func _capture():
	if not "--capture-diagnostics" in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless" or "--visual-qa" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	# Exported resources are read-only. Diagnostics are an explicit local opt-in.
	if not _save(): return
	var directory="user://diagnostics"
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:
		push_error("Could not create diagnostic folder");return
	var path=directory+"/LittleLeaf_Runtime.png"
	if get_viewport().get_texture().get_image().save_png(path)!=OK:
		push_error("Could not save diagnostic screenshot");return
	var diagnostics={"engine":Engine.get_version_info().string,"rendered_frames":Engine.get_frames_drawn(),"served":model.served,"coins":model.coins,"expanded":model.expanded,"music_state":music_state,"music_enabled":music_enabled,"audio_streams":[]}
	for state in audio_players:
		var player=audio_players[state]
		diagnostics.audio_streams.append({"state":state,"playing":player.playing,"length_seconds":player.stream.get_length(),"loop":player.stream.loop})
	var diagnostics_path=directory+"/runtime_diagnostics.json"
	var file=FileAccess.open(diagnostics_path,FileAccess.WRITE)
	if file==null:
		push_error("Screenshot saved; diagnostic details could not be written");return
	var diagnostics_text=JSON.stringify(diagnostics,"\t")
	file.store_string(diagnostics_text);file.flush()
	var write_error=file.get_error();file.close()
	var details_saved=write_error==OK and FileAccess.get_file_as_string(diagnostics_path)==diagnostics_text
	print("Diagnostic screenshot saved" if details_saved else "Screenshot saved; diagnostic details could not be written")

func _toggle_wall_detail():
	wall_detail=not wall_detail
	settings.hide()
	if wall_detail:
		camera.size=7.8
		camera.position=Vector3(12,12,19)
		camera.look_at(Vector3(0.5,0.8,6.5))
	else:
		camera.size=16.5
		camera.position=Vector3(20,20,24)
		camera.look_at(Vector3(5.2,0,4.7))

func _blocked_guest_ids() -> Dictionary:
	# Compatibility diagnostic: staff bodies never pause guest movement.
	return {}

func _staff_blocks_guest() -> bool:
	# Diagnostic compatibility: this no longer pauses the whole simulation.
	return not _blocked_guest_ids().is_empty()

func _setup_music():
	var files={
		"service":"res://assets/audio/小叶食堂_门口的阳光_日常营业.mp3",
		"busy":"res://assets/audio/小叶食堂_午市轻快步_忙碌营业.mp3",
		"decorate":"res://assets/audio/小叶食堂_桌边的叶影_安静布置.mp3"
	}
	for state in files:
		# Imported MP3s are remapped inside exported packs; load the resource.
		var source=load(files[state]) as AudioStreamMP3
		if source==null:
			push_error("Could not load cafe music: "+str(files[state]));continue
		var stream=source.duplicate() as AudioStreamMP3
		stream.loop=true
		var player=AudioStreamPlayer.new()
		player.stream=stream
		player.bus="BGM"
		player.volume_db=-60
		add_child(player)
		audio_players[state]=player
	_switch_music("service")

func _toggle_music():
	if settings_controls!=null:
		settings_controls.set_audio_enabled("BGM",not music_enabled);return
	music_enabled=not music_enabled
	music_toggle.text="Music: on" if music_enabled else "Music: off"
	if is_instance_valid(music_tween): music_tween.kill()
	for state in audio_players:
		var p=audio_players[state]
		if not music_enabled: p.stop()
		elif state==music_state: p.volume_db=-17; p.play()

func _switch_music(state: String):
	if not audio_players.has(state): return
	music_state=state
	music_age=0
	if not music_enabled or DisplayServer.get_name()=="headless": return
	if is_instance_valid(music_tween): music_tween.kill()
	music_tween=create_tween().set_parallel(true)
	for key in audio_players:
		var p=audio_players[key]
		if key==state:
			if not p.playing: p.play()
			music_tween.tween_property(p,"volume_db",-17.0,1.2)
		else:
			music_tween.tween_property(p,"volume_db",-60.0,1.2)

func _music_tick(delta: float):
	# Decorating pauses service, not its soundtrack. Leave the active player,
	# playback position and any in-flight crossfade alone across mode changes.
	# Do not count decorating time toward the service-intensity switch delay.
	if editing:return
	music_age+=delta
	var wanted="busy" if model.customers.size()>=3 else "service"
	if wanted!=music_state and music_age>15: _switch_music(wanted)
