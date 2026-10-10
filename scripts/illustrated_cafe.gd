extends Node2D
const ChefPickupArt=preload("res://scripts/cafe_chef_pickup_art.gd")
const RenderVisibility=preload("res://scripts/cafe_render_visibility.gd")
# Comparison switch; normal gameplay always culls conservatively.
var use_screen_culling=true
var use_idle_retention=true
var use_background_cache=true
var shell_draw_cache=preload("res://scripts/cafe_shell_draw_cache.gd").new()
var background_cache=preload("res://scripts/cafe_background_cache.gd").new()
var render_idle=preload("res://scripts/cafe_render_idle.gd").new()

const CheckoutArt=preload("res://scripts/cafe_checkout_art.gd")
const SinkWashArt=preload("res://scripts/cafe_sink_wash_art.gd")
const FloorCleaningApproach=preload("res://scripts/floor_cleaning_approach.gd")
const FloorMessArt=preload("res://scripts/floor_mess_art.gd")
# Original procedural illustrated assets. Every item is independently drawn from
# its live model identity/position; this is not a baked scene or imported sprite.
const MovingAtlas=preload("res://scripts/moving_art_atlas.gd")
static var moving_atlas=MovingAtlas.new()
var use_cached_moving_art=true
const ExteriorGrassArt=preload("res://scripts/exterior_grass_art.gd")
const ExteriorTreeArt=preload("res://scripts/exterior_tree_art.gd")
static var exterior_tree_art=ExteriorTreeArt.new()
const MotionArt=preload("res://scripts/illustrated_motion.gd")
var motion=MotionArt.new()
var seat_blends={}
var stance_offsets={}
var floor_approach_cache={}
var carry_hand_offsets={}
var guest_motion_cleanup_elapsed := 0.0
const HeadAtlas=preload("res://scripts/character_head_atlas.gd")
static var head_atlas=HeadAtlas.new()
var use_cached_heads=true
var render_contacts=[]
const DiningPlacement=preload("res://scripts/dining_placement.gd")
var meal_chair_offsets={}
var table_dining_directions={}
const DirectionalCharacter=preload("res://scripts/directional_character_art.gd")
var directional_character=DirectionalCharacter.new()
var character_facings={}
const CompactPose=preload("res://scripts/compact_character_pose.gd")
const CameraBounds=preload("res://scripts/cafe_camera_bounds.gd")
const ARM_LENGTH=CompactPose.ARM_LENGTH
const LEG_LENGTH=CompactPose.LEG_LENGTH
var pan_offset=Vector2.ZERO
var _camera_view_size=Vector2.ZERO
var _camera_inspection_rect=Rect2()
var _camera_max_zoom=0.0
var _camera_safe_rect=Rect2()
var _camera_fit_zoom=0.0
const FurnitureArt=preload("res://scripts/illustrated_furniture.gd")
const LampArt=preload("res://scripts/lamp_art.gd")
const DiningStyles=preload("res://scripts/cafe_dining_sets.gd")
const DiningArt=preload("res://scripts/dining_style_art.gd")
var dining_art=DiningArt.new()
const OpeningArt=preload("res://scripts/illustrated_openings.gd")
const OpeningGeometry=preload("res://scripts/cafe_wall_openings.gd")
var render_wall_attachments:Array=[]
const WallArt=preload("res://scripts/illustrated_walls.gd")
const WallGeometry=preload("res://scripts/cafe_walls.gd")
const CameraLandmarks=preload("res://scripts/cafe_camera_landmarks.gd")
const ExteriorExtent=preload("res://scripts/exterior_world_extent.gd")
const StreetPedestrians=preload("res://scripts/street_pedestrians.gd")
var street_pedestrians=StreetPedestrians.new()
const Neighborhood=preload("res://scripts/exterior_environment.gd")
const RoadTraffic=preload("res://scripts/ambient_road_traffic.gd")
var road_traffic=RoadTraffic.new()
const BusStopPedestrians=preload("res://scripts/bus_stop_pedestrians.gd")
var bus_stop_pedestrians=BusStopPedestrians.new()
const GroundArt=preload("res://scripts/illustrated_ground.gd")
var ground_art=GroundArt.new()
# Test-only comparison switch; normal rendering always uses cached ground.
var use_batched_ground=true
var furniture_art=FurnitureArt.new()
var icon_rotation=0
var game: Node
var icon_kind = ""
var zoom = 1.0
var portrait_focus=Vector2.INF
var tile = Vector2(39,19.5)
var origin = Vector2(630,260)
var ink = Color("6d7859")
var opacity = 1.0
# Only submerged sink plates set this local-space aperture during their draw.
var _plate_clip = PackedVector2Array()
var _plate_transform=Transform2D.IDENTITY
var _art_transform := Transform2D.IDENTITY
var _stroke_to_raster := Transform2D.IDENTITY
var _stroke_from_raster := Transform2D.IDENTITY
var _stroke_raster_scale := 1.0
var ui_scale = 1.0
const PAVEMENT_EDGE = -3.26
const PAVEMENT_ROW_WIDTH = 1.0
const WALL_HEIGHT = 128.0
const DOOR_HEIGHT = 97.0
const PAVEMENT_INNER = -0.26
const DOOR_START = 4.75
const DOOR_END = 6.25
# Shared immutable circle samples keep the original 32-sided silhouette, but
# transform vertices in native code instead of allocating 32 scripted trig calls
# for every leaf, plate, face, eye, and furniture detail on every live frame.
static var _unit_circle: PackedVector2Array = _make_unit_circle()
var _grass_left = PackedVector2Array()
var _grass_right = PackedVector2Array()
var use_grass_mesh := true
var grass_mesh: ArrayMesh
var grass_mesh_rebuilds := 0
var _grass_opacity := -1.0

static func _make_unit_circle() -> PackedVector2Array:
	var vertices = PackedVector2Array()
	for i in range(32): vertices.append(Vector2(cos(i*TAU/32),sin(i*TAU/32)))
	return vertices

func _ellipse_vertices(p: Vector2,size: Vector2) -> PackedVector2Array:
	return Transform2D(Vector2(size.x,0),Vector2(0,size.y),p)*_unit_circle

func _ground_cell_visible(x: float,z: float,view: Rect2) -> bool:
	var center=iso(x+.5,z+.5)
	return Rect2(center-tile,tile*2).intersects(view)

func _ready():
	ground_art.use_stroke_mesh=not "--legacy-ground-strokes" in OS.get_cmdline_user_args()
	use_grass_mesh=not "--legacy-grass-strokes" in OS.get_cmdline_user_args()
	use_cached_moving_art=not "--legacy-moving-art" in OS.get_cmdline_user_args()
	if use_cached_moving_art:moving_atlas.request(self)
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	if icon_kind!="":
		furniture_art.cache_enabled=not "--legacy-furniture" in OS.get_cmdline_user_args()
		furniture_art.prepare_cache(self)
		return
	if icon_kind=="" and is_instance_valid(game):
		furniture_art.cache_enabled=not "--legacy-furniture" in OS.get_cmdline_user_args()
		texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		furniture_art.prepare_cache(self)
		use_cached_heads=not "--legacy-heads" in OS.get_cmdline_user_args()
		if use_cached_heads:head_atlas.request(self)

func _exit_tree():
	background_cache.release()

# Runtime accessibility preference, deliberately absent from save data.
var cooking_motion_strength=1.0
var cooking_reduce_motion=false
func _cooking_reduced_motion()->bool:
	if is_instance_valid(game) and game.has_meta("hud_reduce_motion"):return bool(game.get_meta("hud_reduce_motion"))
	return cooking_reduce_motion

func _update_cooking_motion(delta:float):
	if not is_instance_valid(game):return
	# Read accessibility once per frame, never once per stove/actor/layer.
	if game.compact_ui!=null and game.compact_ui.hud!=null:cooking_reduce_motion=game.compact_ui.hud._reduced_motion_requested()
	var previous=cooking_motion_strength
	var active=not game.paused and not game.editing and not game.save_recovery_blocked
	cooking_motion_strength=0.0 if _cooking_reduced_motion() else move_toward(cooking_motion_strength,1.0 if active else 0.0,maxf(delta,0.0)*4.0)
	if not is_equal_approx(previous,cooking_motion_strength):queue_redraw()

func _process(delta):
	_update_cooking_motion(delta)
	if is_instance_valid(game) and game.has_method("effective_frame_delta"):delta=game.effective_frame_delta(delta)
	# Shop artwork is static. CanvasItem already schedules its initial draw;
	# the retained commands stay valid when the tray is hidden/shown again.
	if icon_kind!="":
		# Shop thumbnails use the same original-art atlas. Retaining hundreds
		# of old polygon commands saved script time but not native draw cost.
		if furniture_art.cache_enabled and furniture_art.static_atlas.is_ready() and (not use_cached_moving_art or moving_atlas.is_ready()):queue_redraw()
		elif DisplayServer.get_name()!="headless" and ((furniture_art.cache_enabled and furniture_art.static_atlas.state in ["cold","warming"]) or (use_cached_moving_art and moving_atlas.state in ["cold","warming"])):
			furniture_art.prepare_cache(self);return
		set_process(false)
		return
	_update_street_pedestrians(delta)
	var motion_delta=delta
	if is_instance_valid(game) and game.cafe_intro!=null and game.cafe_intro.active:
		motion_delta=game.cafe_intro.motion_delta(delta)
		if game.save_recovery_blocked or (game.compact_ui!=null and game.compact_ui.viewport_too_small):motion_delta=0.0
	update_motion(motion_delta)
	if not use_idle_retention or render_idle.needs_redraw(self):queue_redraw()
func _update_street_pedestrians(delta:float):
	if not is_instance_valid(game):return
	var active=not game.editing and not game.paused and not game.save_recovery_blocked
	if game.cafe_intro!=null and game.cafe_intro.active:delta=game.cafe_intro.motion_delta(delta)
	if game.compact_ui!=null and game.compact_ui.viewport_too_small:active=false
	var step=delta if active else 0.0
	var queue_positions=[]
	for visitor in game.model.outside_queue:
		if float(visitor.x)>-2.4:queue_positions.append(Vector2(float(visitor.x),float(visitor.z)))
	street_pedestrians.advance(step,queue_positions)
	road_traffic.advance(step,origin,tile,get_viewport_rect())
	bus_stop_pedestrians.advance(step,origin,tile,get_viewport_rect())
	street_pedestrians.observe_customers(game.model.customers,step,game.model.WALK_SPEED,_parking_visits())
	street_pedestrians.update_motion(step,origin,tile,get_viewport_rect())

func _parking_owned()->bool:
	# Historical fixture controllers without parking retain the unbought lawn.
	var owned=game.model.get("parking_owned")
	return owned is bool and owned

func _parking_visits()->Array:
	if not _parking_owned():return []
	var visits=game.model.get("parking_visits")
	return visits if visits is Array else []

func _draw_street_people(show_service:bool):
	# Street traffic and exterior customers share the original scale and wall
	# occlusion. Sort their ground depth together before drawing the shell.
	var entries=street_pedestrians.entries(origin,tile,get_viewport_rect()) if show_service else []
	entries.append_array(Neighborhood.parking_cars(_parking_visits()))
	for guest in game.model.visual_customers():
		if not show_service:break
		if (float(guest.x)>=0 and float(guest.z)>=0) or str(guest.phase) in ["dirty","cleaning"]:continue
		var position=Vector2(float(guest.x),float(guest.z))
		if not StreetPedestrians.screen_bounds(position,origin,tile).intersects(get_viewport_rect()):continue
		entries.append({"position":position,"guest":guest})
	entries.sort_custom(func(a,b):return a.position.x+a.position.y<b.position.x+b.position.y)
	for entry in entries:
		if bool(entry.get("parking_car",false)):
			Neighborhood.draw_oriented_car(self,entry.position,entry.heading,entry.color)
			continue
		var is_guest=entry.has("guest")
		var actor=entry.guest if is_guest else entry
		var key="guest_%s"%actor.id if is_guest else str(actor.key)
		var pose=motion.sample(key) if is_guest else street_pedestrians.motion.sample(key)
		var heading=pose.heading if pose.blend>.02 else actor.get("heading",Vector2.ZERO)
		var facing=character_facings.get(key,{"back":heading.x+heading.y<0,"mirror":-1.0 if heading.x-heading.y<-.01 else 1.0})
		var face=float(facing.mirror)
		art_transform(iso(entry.position.x,entry.position.y),0,Vector2(face,1)*ui_scale*zoom*(1.55 if game.wall_detail else 1.0))
		pose["mirror"]=face;pose["view_back"]=bool(facing.back)
		character(Vector2.ZERO,int(actor.id if is_guest else actor.appearance),false,pose.blend>.02,false,"walking",0,Vector2(18,-28),heading,"none","none",pose)
		art_transform(Vector2.ZERO)

func _draw_bus_stop_people(under_roof:bool,show_people:bool=true):
	if not show_people:return
	for actor in bus_stop_pedestrians.entries(origin,tile,get_viewport_rect(),under_roof):
		var pose=bus_stop_pedestrians.motion.sample(actor.key)
		var heading=pose.heading if pose.blend>.02 else actor.heading
		var face=-1.0 if heading.x-heading.y<-.01 else 1.0
		art_transform(iso(actor.position.x,actor.position.y),0,Vector2(face,1)*ui_scale*zoom*(1.55 if game.wall_detail else 1.0))
		pose["mirror"]=face;pose["view_back"]=heading.x+heading.y<0
		character(Vector2.ZERO,actor.appearance,false,pose.blend>.02,false,"walking",0,Vector2(18,-28),heading,"none","none",pose)
		art_transform(Vector2.ZERO)

func _prune_departed_guest_motion():
	# Only rendering history is retired. Keep dirty-table/service/floor-effect
	# owners until their authoritative records are gone; staff keys never enter
	# this guest-only index. No actor, route, foot contact or ledger is mutated.
	var retained={}
	for guest in game.model.visual_customers():retained[int(guest.id)]=true
	for id in game.service_guests:retained[int(id)]=true
	for record in game.floor_tasks.messes.values():
		var id=int(record.get("source_guest_id",-1))
		if id>=0:retained[id]=true
	for id in seat_blends.keys():
		if retained.has(int(id)):continue
		var key="guest_%s"%id
		motion.remove(key)
		seat_blends.erase(id)
		stance_offsets.erase(key)
		character_facings.erase(key)
		carry_hand_offsets.erase(key)

func update_motion(delta: float):
	if not is_instance_valid(game):return
	# A bounded sweep avoids rebuilding the live-ID set every rendered frame.
	guest_motion_cleanup_elapsed+=maxf(0.0,delta)
	if guest_motion_cleanup_elapsed>=1.0:
		guest_motion_cleanup_elapsed=0.0
		_prune_departed_guest_motion()
	if game.editing or game.paused:
		_update_meal_docking(0.0) # Seed load-time presentation without advancing a paused transition.
		return
	_update_meal_docking(delta)
	for guest in game.model.visual_customers():
		var key="guest_%s"%guest.id
		var position=Vector2(float(guest.x),float(guest.z))
		var docking=Vector2.ZERO
		if bool(guest.get("seated",false)):
			docking=_guest_seated_offset(guest,position)
		elif guest.phase=="paying":
			var register=game.model.get_item(int(guest.get("checkout_register_id",-1)))
			if not register.is_empty():
				var toward=Vector2(register.x+.5,register.z+.5)-position
				docking=toward.normalized()*CheckoutArt.payment_inset(toward,int(register.rot),false)
		stance_offsets[key]=(stance_offsets.get(key,docking if bool(guest.get("seated",false)) else Vector2.ZERO) as Vector2).move_toward(docking,delta*1.5)
		motion.update(key,position+stance_offsets[key],delta)
		var target=_seat_blend_target(guest)
		seat_blends[int(guest.id)]=target if bool(guest.get("dismounting",false)) else move_toward(float(seat_blends.get(int(guest.id),0.0)),target,delta*(4.0 if target>0 else 8.0))
		var heading:Vector2=guest.get("heading",Vector2.RIGHT)
		if float(seat_blends[int(guest.id)])>.01 or bool(guest.get("dismounting",false)):
			var table=game.model.get_item(int(guest.table_id))
			if not table.is_empty():heading=Vector2(table.x+.5,table.z+.5)-position
		_update_character_facing(key,heading)
	for i in range(game.staff_states.size()):
		var staff=game.staff_states[i]
		var key="staff_%s"%i
		var docking=Vector2.ZERO
		if str(staff.get("art_action","")) in ["sweeping","mopping"]:
			if not floor_approach_cache.has(key):floor_approach_cache[key]={}
			docking=FloorCleaningApproach.cached_offset(staff.pos,staff.get("art_target",staff.pos),game.model,stance_offsets.get(key,Vector2.ZERO),floor_approach_cache[key])
		elif str(staff.get("art_action","")) in ["taking_order","preparing_food","cooking","plating","preparing_drink","placing_plate","dropping_dishes","collecting_plate","collecting_drink","serving","collecting","wiping","washing","disposing_trash","taking_payment"]:
			var target=staff.get("art_target",staff.pos)
			var station=game.model.get_item(int(staff.get("art_target_id",-1)))
			# A table has no tall cabinet: keep the worker on its aisle side so
			# the tabletop does not swallow its shoulders during the small gesture.
			var inset=.12 if str(station.get("kind",""))=="table" else .40
			if str(station.get("kind","")) in ["counter","sink","beverage"]:inset=.27
			# One planted approach for the whole owned stove job. Changing the
			# inset at the prep/cook boundary produces a short backwards step,
			# leaving the gait facing away from the stove after it settles.
			if str(station.get("kind",""))=="stove" and str(staff.get("job_kind",""))=="cook" and int(staff.get("station_id",-1))==int(station.get("id",-2)):inset=FurnitureArt.CookingFood.WORK_INSET
			if str(station.get("kind",""))=="stove" and str(staff.get("art_action","")) in ["placing_plate","collecting_plate"]:inset=ChefPickupArt.INSET
			if str(staff.get("art_action",""))=="washing":inset=SinkWashArt.work_inset(int(station.get("rot",0)))
			if str(staff.get("art_action",""))=="taking_payment":inset=CheckoutArt.payment_inset(target-staff.pos,int(station.get("rot",0)),true)
			# Wiping needs actual tabletop contact with the same short arms. Only
			# this job steps close to the edge; serving keeps its small aisle lean.
			if str(station.get("kind",""))=="table" and str(staff.get("art_action",""))=="wiping":inset=DirectionalCharacter.CleaningPose.table_inset(target-staff.pos)
			if target.distance_to(staff.pos)>.1:docking=(target-staff.pos).normalized()*inset
			if str(station.get("kind",""))=="stove" and str(staff.get("art_action","")) in ["placing_plate","collecting_plate"]:docking=ChefPickupArt.work_offset(int(station.rot))
		stance_offsets[key]=(stance_offsets.get(key,Vector2.ZERO) as Vector2).move_toward(docking,delta*1.5)
		motion.update(key,staff.pos+stance_offsets[key],delta)
		var direction=_staff_visual_heading(staff,motion.sample(key))
		_update_character_facing(key,direction)
		var facing=character_facings[key]
		var mirror=float(facing.mirror)
		var carry=DirectionalCharacter.carry_anchor(bool(facing.back))
		var carrying_pan=str(staff.get("art_tool",""))=="dustpan" or str(staff.get("art_payload",""))=="trash"
		if carrying_pan:carry=DirectionalCharacter.CleaningPose.relaxed_pan_hand(bool(facing.back))
		var target_hand=Vector2(carry.x*mirror,carry.y)
		var carrying=str(staff.get("art_action","")) in ["carrying_to_pass","carrying_plate","carrying_drink","carrying_dishes","carrying_trash"] or str(staff.get("art_payload","none"))!="none" or carrying_pan
		# A held cup/plate turns across the torso continuously when a walking
		# sprite changes facing. It must not flip instantaneously to the other hand.
		carry_hand_offsets[key]=(carry_hand_offsets.get(key,target_hand) as Vector2).move_toward(target_hand,delta*90.0) if carrying else target_hand
func _update_character_facing(key:String,heading:Vector2):
	if heading.length_squared()<.00001:return
	var d=heading.normalized();var next={"back":d.x+d.y<0.0,"mirror":-1.0 if d.x-d.y<0.0 else 1.0}
	if not character_facings.has(key):character_facings[key]=next;return
	# Four coherent directions; hysteresis prevents jitter around a diagonal.
	var previous=character_facings[key]
	if absf(d.x+d.y)<.30:next.back=previous.back
	if absf(d.x-d.y)<.30:next.mirror=previous.mirror
	character_facings[key]=next
func _seat_blend_target(guest:Dictionary) -> float:
	if bool(guest.get("dismounting",false)):
		# The short first segment lowers the feet over the chair edge. Keep
		# chair-facing through the sidestep, then turn once clear and upright.
		# Route, reservations, world speed and model clocks are unchanged.
		return 1.0-smoothstep(0.0,.35,float(guest.get("dismount_progress",0.0)))
	if bool(guest.get("seated",false)):return 1.0
	# Turn and lower into the chair during the final short side-entry segment,
	# not after walking upright through the back rail at its exact center.
	var route:Array=guest.get("route",[])
	if str(guest.get("phase",""))=="arriving" and not route.is_empty() and int(guest.get("route_index",0))>=route.size()-1:
		var remaining=Vector2(float(guest.x),float(guest.z)).distance_to(route[-1])
		return clampf(1.0-remaining/.40,0,1)
	return 0.0

func _update_meal_docking(delta:float):
	var visual_delta=maxf(delta,0)
	var active={}
	for guest in game.model.customers:
		var chair=game.model.get_item(int(guest.chair_id));var table=game.model.get_item(int(guest.table_id))
		if chair.is_empty() or table.is_empty():continue
		var id=int(chair.id);active[id]=true
		var toward=Vector2(table.x-chair.x,table.z-chair.z).normalized()
		table_dining_directions[int(table.id)]=-toward
		var eating=str(guest.phase)=="eating" and bool(guest.get("seated",false)) and not bool(guest.get("dismounting",false))
		var target=DiningPlacement.target_dock(toward,eating)
		meal_chair_offsets[id]=(meal_chair_offsets.get(id,target) as Vector2).move_toward(target,visual_delta*DiningPlacement.DOCK_SPEED)
	for id in meal_chair_offsets.keys():
		if active.has(id):continue
		meal_chair_offsets[id]=(meal_chair_offsets[id] as Vector2).move_toward(Vector2.ZERO,visual_delta*DiningPlacement.DOCK_SPEED)
		if (meal_chair_offsets[id] as Vector2).length_squared()<.000001:meal_chair_offsets.erase(id)
	for id in table_dining_directions.keys():
		if game.model.get_item(int(id)).is_empty():table_dining_directions.erase(id)

func _meal_chair_offset(entry:Dictionary)->Vector2:
	if not is_instance_valid(game) or game.editing or bool(entry.get("preview",false)) or str(entry.get("kind","")) not in ["chair","bench"]:return Vector2.ZERO
	var id=int(entry.id)
	if meal_chair_offsets.has(id):return meal_chair_offsets[id]
	# A paused/load-at-mealtime first frame starts at its state-derived pose.
	for guest in game.model.customers:
		if int(guest.chair_id)!=id or str(guest.phase)!="eating" or not bool(guest.get("seated",false)) or bool(guest.get("dismounting",false)):continue
		var table=game.model.get_item(int(guest.table_id))
		if not table.is_empty():return DiningPlacement.target_dock(Vector2(table.x-entry.x,table.z-entry.z),true)
	return Vector2.ZERO

func _guest_seated_offset(guest:Dictionary,position:Vector2)->Vector2:
	var table=game.model.get_item(int(guest.table_id));var chair=game.model.get_item(int(guest.chair_id))
	if table.is_empty():return Vector2.ZERO
	var anchor=position;var weight=1.0
	if bool(guest.get("dismounting",false)):
		if not chair.is_empty():anchor=Vector2(chair.x+.5,chair.z+.5)
		weight=1.0-smoothstep(.35,1.0,float(guest.get("dismount_progress",0)))
	return (Vector2(table.x+.5,table.z+.5)-anchor).normalized()*.12*weight+_meal_chair_offset(chair)

func _render_position(key:String,position:Vector2) -> Vector2:
	if stance_offsets.has(key):return position+stance_offsets[key]
	if is_instance_valid(game) and key.begins_with("guest_"):
		for guest in game.model.customers:
			if key=="guest_%s"%guest.id and bool(guest.get("seated",false)):return position+_guest_seated_offset(guest,position)
	return position

func camera_insets()->Vector4:
	if is_instance_valid(game) and game.get("compact_ui")!=null and game.compact_ui.hud!=null:
		return game.compact_ui.hud._safe_insets()
	return Vector4.ZERO

func camera_play_rect()->Rect2:
	var view=get_viewport_rect().size;var hud_top=104.0
	if is_instance_valid(game) and game.get("compact_ui")!=null and game.compact_ui.hud!=null:
		hud_top=game.compact_ui.hud.layout_host.get_global_rect().end.y+8.0
	return CameraBounds.play_rect(view,hud_top)

func camera_safe_rect(reserve_shop:bool=true)->Rect2:
	var view=get_viewport_rect().size;var insets=camera_insets()
	var browse_top=-1.0;var hud_top=camera_play_rect().position.y
	if is_instance_valid(game) and game.get("compact_ui")!=null:
		if game.compact_ui.hud!=null:
			hud_top=game.compact_ui.hud.layout_host.get_global_rect().end.y+CameraBounds.ViewportLayout.edge_gap(view,insets)
		if game.compact_ui.shop_ui!=null:browse_top=game.compact_ui.shop_ui.browse_rect().position.y
	return CameraBounds.safe_rect(view,hud_top,insets,browse_top,reserve_shop)

func camera_fit_rect()->Rect2:
	return camera_safe_rect(not is_instance_valid(game) or game.editing)

func camera_world_bounds()->Rect2:
	var width=12.0;var depth=17.0
	if is_instance_valid(game) and game.get("model")!=null:
		width=float(game.model.visible_land_width());depth=float(game.model.visible_land_depth())
		if not game.editing:
			width=float(game.model._width_for(game.model.owned_parcels))
			depth=float(game.model._depth_for(game.model.owned_parcels))
	return Rect2(Vector2(-depth*39,-128),Vector2((width+depth)*39,128+(width+depth)*19.5))

func camera_fit_zoom()->float:
	var safe=camera_fit_rect();var bounds=camera_world_bounds()
	var detail=1.55 if is_instance_valid(game) and game.wall_detail else 1.0
	return minf(safe.size.x/bounds.size.x,safe.size.y/bounds.size.y)/maxf(.000001,ui_scale*detail)

func camera_zoom_limits()->Vector2:
	var detail=1.55 if is_instance_valid(game) and game.wall_detail else 1.0
	var limits=CameraBounds.zoom_limits(get_viewport_rect().size,Vector2(39,19.5)*ui_scale*detail,camera_play_rect().position.y,camera_insets())
	# Fit is always reachable, including short landscape and inset displays.
	limits.x=minf(limits.x,camera_fit_zoom())
	return limits

func update_projection(clamp_camera:bool=true):
	var size=get_viewport_rect().size
	var safe=camera_safe_rect()
	var inspection=CameraBounds.inspection_rect(size,camera_play_rect().position.y,camera_insets())
	# HUD/shop controls can settle a frame after the viewport resize itself.
	var resized=_camera_view_size!=Vector2.ZERO and (_camera_view_size!=size or not _camera_safe_rect.is_equal_approx(safe) or not _camera_inspection_rect.is_equal_approx(inspection))
	var resize_anchor=Vector2.INF
	var keep_close=resized and is_equal_approx(zoom,_camera_max_zoom)
	var keep_fit=resized and is_equal_approx(zoom,_camera_fit_zoom)
	if resized and tile.x>0 and tile.y>0:
		resize_anchor=screen_to_world(_camera_inspection_rect.get_center())
	# Frame the finite expansion area at desktop sizes. The same framing is
	# retained in Play and Decorate so opening the tray never jumps the map.
	var map_depth=float(game.model.visible_land_depth()) if is_instance_valid(game) and game.get("model")!=null else 17.0
	var map_width=float(game.model.BASE_WIDTH) if is_instance_valid(game) and game.get("model")!=null else 12.0
	if is_instance_valid(game) and game.model.has_method("visible_land_width"):map_width=float(game.model.visible_land_width())
	var bounds=Rect2(Vector2(-map_depth*39,-128),Vector2((map_width+map_depth)*39,128+(map_width+map_depth)*19.5))
	var available=camera_play_rect()
	ui_scale=minf(available.size.x/bounds.size.x,available.size.y/bounds.size.y)
	var frame_center=available.get_center()
	var focus=bounds.get_center()
	# Portrait starts with its readable working-area view. Initial focus is
	# cached, so editing never pulls the map back to the furniture.
	if size.x<650 and size.y>size.x:
		ui_scale=maxf(.50,minf((size.x-36.0)/430.0,(size.y-300.0)/500.0))
		if not portrait_focus.is_finite():
			var focus_bounds=Rect2(Vector2(175,155),Vector2.ZERO);var first=true
			for item in game.model.items:
				if str(item.kind) not in game.model.SERVICE_KINDS:continue
				var q=Vector2((item.x-item.z)*39,(item.x+item.z+1)*19.5)
				var item_bounds=Rect2(q+Vector2(-30,-75),Vector2(60,83))
				focus_bounds=item_bounds if first else focus_bounds.merge(item_bounds);first=false
			portrait_focus=focus_bounds.get_center()
		frame_center=Vector2(size.x*.5,(130+size.y-220)*.5)
		focus=portrait_focus
	var limits=camera_zoom_limits()
	if not is_finite(zoom):zoom=1.0
	zoom=clampf(limits.y if keep_close else (camera_fit_zoom() if keep_fit else zoom),limits.x,limits.y)
	if not pan_offset.is_finite():pan_offset=Vector2.ZERO
	tile=Vector2(39,19.5)*ui_scale*zoom
	var base_origin=frame_center-focus*ui_scale*zoom
	if is_instance_valid(game) and game.wall_detail:
		tile*=1.55
		base_origin=Vector2(size.x*.80,130*ui_scale)
	origin=base_origin+pan_offset
	if keep_fit and not keep_close:
		var detail=1.55 if is_instance_valid(game) and game.wall_detail else 1.0
		pan_offset+=camera_fit_rect().get_center()-(origin+camera_world_bounds().get_center()*ui_scale*zoom*detail)
	elif resize_anchor.is_finite():
		pan_offset+=inspection.get_center()-iso(resize_anchor.x,resize_anchor.y)
	if clamp_camera:
		pan_offset=CameraBounds.clamp_pan(pan_offset,base_origin,tile,map_width,map_depth,size,available.position.y,safe,CameraLandmarks.inspection_bounds(tile))
	origin=base_origin+pan_offset
	_camera_view_size=size;_camera_inspection_rect=inspection;_camera_max_zoom=limits.y
	_camera_safe_rect=safe;_camera_fit_zoom=camera_fit_zoom()

func focus_fresh_start():
	var size=get_viewport_rect().size
	# Portrait already starts close. Apply the desktop framing only once;
	# normal pan/zoom and entering Decorate keep this same projection.
	if size.x<650:return
	zoom=1.15;update_projection()
	var depth=float(game.model.BASE_DEPTH);var width=float(game.model.BASE_WIDTH)
	var bounds=Rect2(Vector2(-depth*39,-WALL_HEIGHT),Vector2((width+depth)*39,WALL_HEIGHT+(width+depth)*19.5))
	var available=camera_play_rect()
	pan_offset+=available.get_center()-(origin+bounds.get_center()*ui_scale*zoom)
	update_projection()

func fit_overview():
	update_projection()
	zoom=camera_fit_zoom();update_projection(false)
	var detail=1.55 if is_instance_valid(game) and game.wall_detail else 1.0
	pan_offset+=camera_fit_rect().get_center()-(origin+camera_world_bounds().get_center()*ui_scale*zoom*detail)
	update_projection();queue_redraw()

func col(c):
	var color = Color(c) if c is String else c
	color.a *= opacity
	return color
# Godot builds its antialias fringe in the submitted point coordinates. If
# the draw transform magnifies those coordinates, the fringe magnifies too.
# Submit strokes in raster coordinates at close zoom and during the 4x atlas bake;
# authored centerlines, stroke widths, fill geometry and palette stay unchanged.
func art_transform(offset:Vector2,rotation:float=0.0,scale:Vector2=Vector2.ONE):
	_art_transform=Transform2D(rotation,scale,0.0,offset)
	var outer=get_global_transform_with_canvas()
	_stroke_to_raster=outer*_art_transform
	_stroke_raster_scale=art_stroke_scale(_stroke_to_raster)
	if is_zero_approx(outer.determinant()):
		_stroke_from_raster=Transform2D.IDENTITY
		_stroke_raster_scale=0.0
	else:_stroke_from_raster=outer.affine_inverse()
	draw_set_transform_matrix(_art_transform)

static func art_stroke_scale(transform:Transform2D)->float:
	var horizontal=transform.x.length()
	var vertical=transform.y.length()
	# One scalar width preserves circular strokes only for uniform scale.
	# Keep the original renderer for a future stretched/sheared drawing.
	if not is_equal_approx(horizontal,vertical) or horizontal<=.00001:return 0.0
	if absf(transform.x.dot(transform.y))>horizontal*vertical*.00001:return 0.0
	return horizontal

func art_cache_covers(bounds:Rect2,bake_scale:float)->bool:
	# Keep the bounded atlas for ordinary play and offscreen pieces. At the
	# closest inspection zoom, draw only visible magnified pieces from their
	# existing vector source instead of stretching a finite texture.
	if _stroke_raster_scale<=bake_scale:return true
	return not (_stroke_to_raster*bounds).intersects(get_viewport_rect())

func art_polyline(points:PackedVector2Array,tint:Color,width:float):
	var raster_scale=_stroke_raster_scale
	if raster_scale<=1.0:
		draw_polyline(points,tint,width,true)
		return
	draw_set_transform_matrix(_stroke_from_raster)
	draw_polyline(_stroke_to_raster*points,tint,width*raster_scale,true)
	draw_set_transform_matrix(_art_transform)

func art_arc(center:Vector2,radius:float,start:float,end:float,count:int,tint:Color,width:float):
	var points=PackedVector2Array()
	for index in range(count):
		var angle=lerpf(start,end,float(index)/float(count-1))
		points.append(center+Vector2(cos(angle),sin(angle))*radius)
	art_polyline(points,tint,width)

func art_line(start:Vector2,finish:Vector2,tint:Color,width:float):
	var raster_scale=_stroke_raster_scale
	if raster_scale<=1.0:
		draw_line(start,finish,tint,width,true)
		return
	draw_set_transform_matrix(_stroke_from_raster)
	draw_line(_stroke_to_raster*start,_stroke_to_raster*finish,tint,width*raster_scale,true)
	draw_set_transform_matrix(_art_transform)

func poly(points: Array,c):
	var vertices=PackedVector2Array(points)
	var tint=col(c)
	draw_colored_polygon(vertices,tint)
	vertices.append(vertices[0])
	art_polyline(vertices,tint,0.7)
func rounded_poly(points: Array,r: float,c):
	var smooth=[]
	for i in range(points.size()):
		var vertex:Vector2=points[i]
		var prev:Vector2=points[(i+points.size()-1)%points.size()]
		var next:Vector2=points[(i+1)%points.size()]
		var a=vertex+(prev-vertex).normalized()*minf(r,vertex.distance_to(prev)*.3)
		var b=vertex+(next-vertex).normalized()*minf(r,vertex.distance_to(next)*.3)
		for k in range(6):
			var t=float(k)/5.0
			smooth.append((1-t)*(1-t)*a+2*(1-t)*t*vertex+t*t*b)
	poly(smooth,c)
func line(a: Vector2,b: Vector2,c,width=1.0): art_line(a,b,col(c),width)
func _plate_clipped_shape(points:PackedVector2Array,fill:Color,border:Color,width:float):
	for polygon in Geometry2D.intersect_polygons(points,_plate_clip):
		draw_colored_polygon(polygon,fill)
		polygon.append(polygon[0]);art_polyline(polygon,border,width)

func ellipse(p: Vector2,size: Vector2,c):
	var points=_ellipse_vertices(p,size)
	if _plate_transform!=Transform2D.IDENTITY:points=_plate_transform*points
	if not _plate_clip.is_empty():_plate_clipped_shape(points,col(c),col(c),.7);return
	var tint=col(c)
	draw_colored_polygon(points,tint)
	points.append(points[0])
	art_polyline(points,tint,0.7)
func outlined_ellipse(p: Vector2,size: Vector2,c,edge,width=1.0):
	var points=_ellipse_vertices(p,size)
	if _plate_transform!=Transform2D.IDENTITY:points=_plate_transform*points
	if not _plate_clip.is_empty():_plate_clipped_shape(points,col(c),col(edge),width);return
	draw_colored_polygon(points,col(c))
	points.append(points[0])
	# The explicit border already supplies the antialiased silhouette. A
	# second same-fill-color border underneath it was redundant draw work.
	art_polyline(points,col(edge),width)
func iso(x: float,z: float,h=0.0) -> Vector2: return origin+Vector2((x-z)*tile.x,(x+z)*tile.y)-Vector2(0,h*ui_scale*zoom*(1.55 if is_instance_valid(game) and game.wall_detail else 1.0))
func screen_to_world(p:Vector2)->Vector2:
	var d=p-origin
	return Vector2((d.x/tile.x+d.y/tile.y)*.5,(d.y/tile.y-d.x/tile.x)*.5)
func screen_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(screen_to_world(p).floor())

func render_bounds_visible(bounds:Rect2)->bool:
	# Standalone/atlas artists and transformed inspection sheets retain artwork.
	return not use_screen_culling or not is_instance_valid(game) or icon_kind!="" or _art_transform!=Transform2D.IDENTITY or RenderVisibility.visible(bounds,get_viewport_rect(),6.0)
func _render_anchor_visible(anchor:Vector2,extra:Vector2=Vector2.INF)->bool:
	# Wide guard includes shadows, tall heads, bubbles and tools. Include the
	# target so reaching foregrounds survive when the owner's feet are outside.
	var scale=ui_scale*zoom*(1.55 if is_instance_valid(game) and game.wall_detail else 1.0)
	var bounds=RenderVisibility.local_bounds(anchor,scale,Rect2(-128,-192,256,272))
	if extra.is_finite():bounds=bounds.merge(RenderVisibility.local_bounds(extra,scale,Rect2(-128,-192,256,272)))
	return render_bounds_visible(bounds)

func objects_hidden()->bool:
	return is_instance_valid(game) and "compact_ui" in game and game.compact_ui!=null and "shop_ui" in game.compact_ui and game.compact_ui.shop_ui!=null and game.compact_ui.shop_ui.objects_hidden()

func _draw():
	render_contacts.clear()
	if icon_kind!="":
		background_cache.hide()
		ui_scale=1; tile=Vector2(39,19.5); origin=Vector2.ZERO
		art_transform(Vector2(49,57),0,Vector2(.80,.80))
		item(icon_kind,Vector2.ZERO,icon_rotation,0)
		art_transform(Vector2.ZERO)
		return
	if not is_instance_valid(game):
		background_cache.hide();return
	var size=get_viewport_rect().size
	var show_service=not game.editing
	var show_objects=not objects_hidden()
	render_wall_attachments=game.build_tools.get_render_attachments() if game.build_tools!=null and game.build_tools.has_method("get_render_attachments") else game.model.wall_attachments
	var openings=[]
	for attachment in render_wall_attachments if show_objects else []:
		var opening=OpeningGeometry.aperture(attachment,game.model.built_walls,game.model.shell_products)
		if not opening.is_empty():opening["preview"]=bool(attachment.get("preview",false));openings.append(opening)
	update_projection()
	var gameplay_origin = origin
	if game.cafe_intro!=null:origin+=game.cafe_intro.render_offset(size)
	var ground_view=Rect2(Vector2.ZERO,size).grow(3.0)
	ground_art.prepare(game.model)
	if not use_background_cache:background_cache.hide()
	if not use_background_cache or not background_cache.update(self):
		draw_rect(Rect2(Vector2.ZERO,size),Color("c6d5ad"))
		_grass(size)
		Neighborhood.draw_ground(self,_parking_owned())
		if use_batched_ground:ground_art.draw_pavement(self)
		else:_draw_legacy_pavement(ground_view)
		Neighborhood.draw_crossing(self,_parking_owned())
	Neighborhood.draw_props(self,_draw_bus_stop_people.bind(true,show_service),_draw_bus_stop_people.bind(false,show_service))
	road_traffic.draw(self)
	if use_batched_ground:ground_art.draw_floor(self)
	else:_draw_legacy_floor(ground_view)
	_parcel_ground()
	if game.interaction!=null:game.interaction.draw_floor_feedback(self)
	if game.build_tools!=null:game.build_tools.draw_floor_preview(self)
	if show_objects and game.editing and game.selected_id>=0 and not ("interaction" in game and game.interaction!=null and game.interaction.drag_active):
		var selected=game.model.get_item(game.selected_id)
		if not selected.is_empty():
			for member in game.model.logical_members(game.selected_id):
				var part=game.model.get_item(member);var x=float(part.x);var z=float(part.z)
				var corners=[iso(x+.04,z+.04),iso(x+.96,z+.04),iso(x+.96,z+.96),iso(x+.04,z+.96)]
				poly(corners,Color(.96,.92,.68,.38))
				for i in range(4):line(corners[i],corners[(i+1)%4],"90a072",1.2)
	for record in game.service_guests.values()+game.floor_tasks.messes.values():
		if not show_service:break
		_draw_floor_mess(record)
	for opening in openings:OpeningArt.threshold(self,opening)
	var interaction=game.interaction if "interaction" in game else null
	var preview=show_objects and interaction!=null and interaction.preview_active
	if preview:
		var outline=Color(.34,.50,.28,.80) if interaction.drag_valid else Color(.62,.37,.29,.80)
		for part in game.model.placement_parts(interaction.drag_kind,interaction.drag_cell.x,interaction.drag_cell.y,interaction.drag_rotation,interaction.drag_item_id):
			var c=Vector2i(int(part.x),int(part.z))
			var corners=[iso(c.x+.03,c.y+.03),iso(c.x+.97,c.y+.03),iso(c.x+.97,c.y+.97),iso(c.x+.03,c.y+.97)]
			poly(corners,Color("cad2b6") if interaction.drag_valid else Color("ddcbb6"))
			for i in range(4):line(corners[i],corners[(i+1)%4],outline,1.7)
	# Work tiles share the current ground projection and sit below all props.
	if show_objects and game.workface_guidance!=null:game.workface_guidance.draw_ground(self)
	# Exterior rear foliage sits behind the cafe shell and its furnishings.
	_scenery_tree(Vector2(13.5,-.5),1.10)
	_draw_street_people(show_service)
	# Existing shell and player walls share the same aperture geometry.
	if show_objects:
		shell_draw_cache.draw(self,game.build_tools.render_shell_host("shell:back"),render_wall_attachments,"e0e7d0","91a27d")
		shell_draw_cache.draw(self,game.build_tools.render_shell_host("shell:west"),render_wall_attachments,"cfdbc2","819874")
		var corner_height=minf(game.build_tools.render_shell_corner_height("shell:back"),game.build_tools.render_shell_corner_height("shell:west"))
		poly([iso(0,0,corner_height),iso(-.26,0,corner_height),iso(-.26,-.26,corner_height),iso(0,-.26,corner_height)],"fff1d0")
		game.build_tools.draw_shell_selection(self)
	var entities=[]
	# Corner foliage shares the ground-depth order of props and people.
	entities.append({"depth":26.0,"type":"scenery_tree","entry":{"id":-1},"position":Vector2(14.5,11.5),"scale":.78,"variant":"oak"})
	for i in range(Neighborhood.TREES.size()):
		var tree=Neighborhood.TREES[i]
		var world=Vector2(tree.x,tree.y)
		if _scenery_tree_visible_at(world):entities.append({"depth":tree.x+tree.y,"type":"scenery_tree","entry":{"id":str(world)},"position":world,"scale":tree.z,"variant":Neighborhood.TREE_VARIANTS[i]})
	for opening in openings:entities.append_array(OpeningArt.depth_entries(opening))
	for wall in game.model.built_wall_segments() if show_objects else []:
		for piece in WallArt.depth_entries(wall):entities.append(piece)
	if show_objects and game.build_tools!=null and game.build_tools.active() and not game.build_tools.paint_stroke.active and not game.build_tools.preview.is_empty():
		for piece in WallArt.depth_entries(game.build_tools.preview):
			piece["wall_preview"]=true;piece.depth+=.001;entities.append(piece)
	var render_items=[]
	var moving_members=game.model.logical_members(int(interaction.drag_item_id)) if preview and interaction.drag_active and int(interaction.drag_item_id)>=0 else []
	for actual in game.model.items if show_objects else []:
		if int(actual.id) not in moving_members:render_items.append(actual)
	if preview and (int(interaction.drag_item_id)<0 or interaction.drag_active):
		for part in game.model.placement_parts(interaction.drag_kind,interaction.drag_cell.x,interaction.drag_cell.y,interaction.drag_rotation,interaction.drag_item_id):
			var entry=part.duplicate();entry["preview"]=true
			if int(entry.x)>=0 and int(entry.x)<game.model.MAX_WIDTH and int(entry.z)>=0 and int(entry.z)<game.model.MAX_DEPTH:render_items.append(entry)
	for entry in render_items:
		var meal_offset=_meal_chair_offset(entry)
		if not _render_anchor_visible(iso(entry.x+.5+meal_offset.x,entry.z+.5+meal_offset.y)):continue
		var item_depth=float(entry.x+entry.z)+1+meal_offset.x+meal_offset.y
		entities.append({"depth":-100 if entry.kind=="rug" else item_depth,"type":"item","entry":entry,"meal_offset":meal_offset})
		if entry.kind in ["chair","bench"]:
			var r=_chair_rotation(entry)
			entities.append({"depth":item_depth+(.38 if r in [0,3] else -.38),"type":"chair_back","entry":entry,"rot":r,"meal_offset":meal_offset})
	for guest in game.model.customers:
		if not show_service:break
		var render_pos=_render_position("guest_%s"%guest.id,Vector2(float(guest.x),float(guest.z)))
		if float(guest.x)>=0 and float(guest.z)>=0 and not str(guest.phase) in ["dirty","cleaning"]:
			var dining=CheckoutArt.guest_action(guest,game.service_guests.get(int(guest.id),{}))=="eating"
			var surface=game.model.get_item(int(guest.table_id) if dining else int(guest.get("checkout_register_id",-1)))
			var target=Vector2.INF if surface.is_empty() else iso(float(surface.x)+.5,float(surface.z)+.5)
			if not _render_anchor_visible(iso(render_pos.x,render_pos.y),target):continue
			var body_depth=render_pos.x+render_pos.y+.15
			var surface_depth=float(surface.get("x",-100)+surface.get("z",-100))+1.0
			# Keep the torso behind the table, but its spoon above the real dish.
			var split=(guest.phase=="paying" or dining) and not surface.is_empty() and body_depth<surface_depth
			entities.append({"depth":body_depth,"type":"guest","entry":guest,"hide_reach":split})
			if split:entities.append({"depth":surface_depth+.02,"type":"guest","entry":guest,"reach_overlay":true})
	for i in range(game.staff_states.size()):
		if not show_service:break
		var staff=game.staff_states[i]
		var render_pos=_render_position("staff_%s"%i,staff.pos)
		var body_depth=render_pos.x+render_pos.y+.15
		var target=game.model.get_item(int(staff.get("art_target_id",-1)))
		var contact=staff.get("art_target",staff.get("art_station",staff.pos))
		if not _render_anchor_visible(iso(render_pos.x,render_pos.y),iso(contact.x,contact.y)):continue
		var staff_action=str(staff.get("art_action",""))
		var interacting=staff_action in ["preparing_food","cooking","plating","preparing_drink","placing_plate","dropping_dishes","collecting_plate","collecting_drink","serving","collecting","wiping","washing","disposing_trash","taking_payment"]
		var target_depth=float(target.get("x",-100)+target.get("z",-100))+1.0
		var split=interacting and body_depth<target_depth
		entities.append({"depth":body_depth,"type":"staff","entry":staff,"index":i,"hide_reach":split})
		if split:
			# Torso remains behind the cabinet. Its reaching forearm and held
			# order are above the actual worktop, not painted underneath it.
			entities.append({"depth":target_depth+.02,"type":"staff","entry":staff,"index":i,"reach_overlay":true})
			if str(target.get("kind",""))=="beverage" and posmod(int(target.get("rot",0)),4) in [1,2]:
				# The worktop sits below the reaching hand; the tall rear-facing
				# espresso unit stays in front until the cup is withdrawn clear.
				entities.append({"depth":target_depth+.04,"type":"beverage_foreground","entry":target})
		if staff_action in ["preparing_food","plating"] and str(target.get("kind",""))=="stove" and posmod(int(target.get("rot",0)),4) in [0,1]:
			# Preserve the pan/plate occlusion while the rear plate is lifted.
			entities.append({"depth":maxf(body_depth,target_depth)+.04,"type":"stove_foreground","entry":target})
	entities.sort_custom(func(a,b): return a.depth<b.depth if not is_equal_approx(a.depth,b.depth) else str(a.type)+str(a.entry.get("id",0))<str(b.type)+str(b.entry.get("id",0)))
	for e in entities:
		if e.type=="scenery_tree":
			if e.variant=="oak":_scenery_tree(e.position,float(e.scale))
			else:Neighborhood.greenery.draw_tree(self,iso(e.position.x,e.position.y),e.scale*ui_scale*zoom*(1.55 if game.wall_detail else 1.0),e.variant)
			continue
		if e.type=="opening_frame":
			OpeningArt.casing(self,e.entry,e.part,.65 if bool(e.entry.get("preview",false)) else 1.0,Color("c6e1ae") if bool(e.entry.get("preview",false)) else Color.WHITE);continue
		if e.type=="built_wall":
			var is_preview=bool(e.get("wall_preview",false))
			if not is_preview and game.build_tools!=null and game.build_tools.active() and (game.build_tools.mode in ["paint","remove"] or (game.build_tools.replacing and game.build_tools.preview_valid)) and WallGeometry.key_of(e.entry)==game.build_tools.selected_key and not game.build_tools.preview.is_empty():continue
			var tint=Color.WHITE
			if is_preview:
				tint=Color("eeb9a1") if not game.build_tools.preview_valid or game.build_tools.mode=="remove" else (Color("efd095") if game.build_tools.preview_warning!="" else Color("c6e1ae"))
			OpeningArt.draw_built_piece(self,e,render_wall_attachments,.68 if is_preview else 1.0,tint);continue
		if e.type=="door_front":
			_door_front(); continue
		if e.type in ["item","chair_back","beverage_foreground","stove_foreground"]:
			var d=e.entry
			var meal_offset:Vector2=e.get("meal_offset",Vector2.ZERO)
			var p=iso(d.x+.5+meal_offset.x,d.z+.5+meal_offset.y)
			opacity=.63 if bool(d.get("preview",false)) else 1.0
			art_transform(p,0,Vector2.ONE*ui_scale*zoom*(1.55 if game.wall_detail else 1.0))
			if e.type=="beverage_foreground":furniture_art.draw_beverage_foreground(self,Vector2.ZERO,int(d.rot))
			elif e.type=="stove_foreground":furniture_art.draw_stove_foreground(self,Vector2.ZERO,int(d.rot),int(d.id))
			elif e.type=="chair_back":
				if d.kind=="bench":furniture_art.draw_bench_part(self,Vector2.ZERO,int(e.rot),true)
				else:_chair(Vector2.ZERO,int(e.rot),true,_dining_style(int(d.id),str(d.get("dining_variant",""))))
			elif d.kind=="chair": _chair(Vector2.ZERO,_chair_rotation(d),false,_dining_style(int(d.id),str(d.get("dining_variant",""))))
			elif d.kind=="bench":furniture_art.draw_bench_part(self,Vector2.ZERO,_chair_rotation(d),false)
			else: item(d.kind,Vector2.ZERO,int(d.rot),int(d.id),str(d.get("dining_variant","")))
			if d.kind=="table" and show_service: _meal(d.id)
			if d.kind=="sink" and show_service: _sink_dishes(d.id)
			if d.kind=="counter" and show_service: _station_payloads(d.id,d.kind,int(d.rot))
			art_transform(Vector2.ZERO)
			opacity=1.0
		else:
			var d=e.entry
			var key=("staff_%s"%e.index) if e.type=="staff" else ("guest_%s"%d.id)
			var render_pos=_render_position(key,d.pos if e.type=="staff" else Vector2(float(d.x),float(d.z)))
			var p=iso(render_pos.x,render_pos.y)
			var pose=motion.sample(key)
			var moving=pose.blend>.02
			var seat_mix=float(seat_blends.get(int(d.get("id",-1)),1.0 if bool(d.get("seated",false)) else 0.0)) if e.type=="guest" else 0.0
			pose["seat_mix"]=seat_mix
			pose["dismounting"]=e.type=="guest" and bool(d.get("dismounting",false)) and seat_mix>.01
			var direction=Vector2.ZERO
			var seated=e.type=="guest" and (bool(d.get("seated",false)) or seat_mix>.01)
			if e.type=="guest":
				direction=d.get("heading",Vector2.ZERO)
				if seated and not bool(d.get("dismounting",false)):
					var table=game.model.get_item(int(d.table_id))
					direction=Vector2(float(table.x)+.5,float(table.z)+.5)-Vector2(float(d.x),float(d.z))
			else:direction=_staff_visual_heading(d,pose)
			if e.type=="guest" and moving and not seated and str(d.phase) not in ["checkout_wait","paying"]:direction=pose.heading
			var facing=character_facings.get(key,{"back":direction.x+direction.y<0,"mirror":-1.0 if direction.x-direction.y<-.01 else 1.0})
			var face=float(facing.mirror)
			pose["mirror"]=face;pose["view_back"]=bool(facing.back)
			if e.type=="staff":
				var held:Vector2=carry_hand_offsets.get(key,Vector2(17*face,-23))
				pose["carry_hand"]=Vector2(held.x*face,held.y)
				# Presentation reads the existing work clock; it never changes the
				# recipe duration, normalized completion progress, or saved state.
				pose["cooking_strength"]=0.0 if _cooking_reduced_motion() or _stove_heat_state(int(d.get("station_id",-1))).is_empty() else cooking_motion_strength
				pose["cooking_elapsed"]=float(d.get("job_elapsed",0.0))
				var cooking_progress=float(d.get("art_phase",0.0))
				pose["cooking_remaining"]=float(pose.cooking_elapsed)*(1.0-cooking_progress)/cooking_progress if cooking_progress>.000001 else -1.0
			pose["hide_reach"]=bool(e.get("hide_reach",false))
			pose["reach_overlay"]=bool(e.get("reach_overlay",false))
			art_transform(p,0,Vector2(face,1)*ui_scale*zoom*(1.55 if game.wall_detail else 1.0))
			var action=str(d.get("art_action","idle")) if e.type=="staff" else CheckoutArt.guest_action(d,game.service_guests.get(int(d.id),{}))
			var progress=float(d.get("art_phase",0.0)) if e.type=="staff" else clampf(float(d.get("elapsed",0.0))/maxf(.01,float(d.get("duration",1.0))),0.0,1.0)
			if e.type=="guest" and d.phase=="paying":progress=CheckoutArt.guest_progress(game,d)
			if (e.type=="guest" and d.phase in ["checkout_wait","paying"]) or action=="taking_payment":moving=false
			var payload=str(d.get("art_payload","none"))
			if e.type=="guest":
				var record=game.service_guests.get(int(d.id),{})
				if _drink_in_hand(d,record):payload="drink"
			var reach=Vector2(18,-28)
			var target=d.get("art_target",d.get("art_station",Vector2.ZERO)) if e.type=="staff" else Vector2.ZERO
			if e.type=="guest" and d.phase=="paying":
				var register=game.model.get_item(int(d.get("checkout_register_id",-1)))
				if not register.is_empty():target=Vector2(register.x+.5,register.z+.5)
			elif seated and not bool(d.get("dismounting",false)):
				var table=game.model.get_item(int(d.table_id));target=Vector2(table.x+.5,table.z+.5)
			if target!=Vector2.ZERO:
				var unit_scale=ui_scale*zoom*(1.55 if game.wall_detail else 1.0)
				var ground=(iso(target.x,target.y)-p)/unit_scale
				var target_item=game.model.get_item(int(d.get("art_target_id",-1))) if e.type=="staff" else game.model.get_item(int(d.get("checkout_register_id",-1)) if d.phase=="paying" else int(d.table_id))
				var kind=str(target_item.get("kind","table"))
				var drink_job="drink" in str(d.get("art_service_kind","")) or str(d.get("art_service_kind",""))=="brew" or action in ["collecting_drink","preparing_drink","drinking"]
				var surface=FurnitureArt.KitchenGeometry.surface(Vector2.ZERO,31) if kind in ["counter","sink"] else Vector2(0,-31)
				if kind=="table":
					surface=_table_surface_point(int(target_item.get("id",-1)),drink_job)
					if action=="wiping":
						# The compact arm aims toward the top and meets its near edge;
						# the character painter owns the fixed-length contact stroke.
						surface=Vector2(0,-DiningPlacement.TABLE_HEIGHT-1.0)
				elif kind=="sink" and action=="washing":
					var wash=SinkWashArt.state(game,int(target_item.id))
					if not wash.is_empty():
						var wash_geometry=SinkWashArt.geometry(int(target_item.rot),float(wash.seconds),int(wash.count))
						surface=wash_geometry.center
						var axes:Transform2D=wash_geometry.basis
						pose["washing_basis"]=Transform2D(Vector2(axes.x.x*face,axes.x.y),Vector2(axes.y.x*face,axes.y.y),Vector2.ZERO)
						pose["washing_seconds"]=float(wash.seconds)
						var ref=SinkWashArt.geometry(int(target_item.rot),1.0,int(wash.count));var ref_axes:Transform2D=ref.basis
						pose["washing_grip_reference"]={"center":(ground+ref.center)*Vector2(face,1),"basis":Transform2D(ref_axes.x*Vector2(face,1),ref_axes.y*Vector2(face,1),Vector2.ZERO)}
				elif kind=="register":surface=CheckoutArt.contact_surface(int(target_item.get("rot",0)),e.type=="staff")
				elif kind=="bin":surface=Vector2(0,-25)
				elif kind=="beverage":surface=_drink_surface_point(int(target_item.get("rot",0)))
				elif kind=="stove":
					surface=_stove_plate_point(int(target_item.get("rot",0)))
					if action=="cooking":
						surface=FurnitureArt.stove_handle_points(int(target_item.get("rot",0)))[1]+_stove_vessel_motion(int(target_item.get("id",-1))).pot
						pose["cooking_grip"]=true
				var anchor=Vector2(2,-2) if drink_job else Vector2(4,0 if payload=="dishes" or action in ["collecting","washing"] else -2)
				if action=="cooking":anchor=Vector2.ZERO
				elif action=="preparing_food":anchor=Vector2(4,6)
				elif action=="eating":anchor=Vector2.ZERO
				elif action in ["wiping","paying","taking_payment","washing"]:anchor=Vector2.ZERO
				elif payload=="trash" or action=="disposing_trash":anchor=Vector2(3,-3)
				if action in ["picking_litter","sweeping","mopping"]:surface=Vector2.ZERO;anchor=Vector2(3,-3)
				var contact=ground+surface
				reach=Vector2(contact.x*face,contact.y)-anchor
				if kind=="stove" and action in ["placing_plate","collecting_plate"]:
					pose["pickup_grip"]=(ground+ChefPickupArt.grip(int(target_item.rot)))*Vector2(face,1)
					pose["pickup_plate"]=(ground+game.ChefPickup.plate_anchor(int(target_item.rot)))*Vector2(face,1)
			character(Vector2.ZERO,int(e.get("index",d.get("id",1))),e.type=="staff",moving,seated,action,progress,reach,direction,payload,str(d.get("art_tool","none")),pose,str(d.get("art_role",d.get("role","chef"))))
			if e.type=="staff" and not bool(d.get("on_duty",true)):
				ellipse(Vector2(0,-80),Vector2(5.5,5.5),"f1eddc")
				line(Vector2(-1.7,-82.5),Vector2(-1.7,-77.5),"819071",1.4);line(Vector2(1.7,-82.5),Vector2(1.7,-77.5),"819071",1.4)
			var bubble_symbol="…" if e.type=="guest" and str(d.phase)=="ordering" else ("!" if e.type=="staff" and action=="blocked" else "")
			# Archived service fixtures keep their original ordering-only display.
			if e.type=="guest" and game.has_method("_guest_bubble_symbol"):bubble_symbol=game._guest_bubble_symbol(d)
			if not bool(e.get("reach_overlay",false)) and bubble_symbol!="":
				var bubble_id=int(e.get("index",d.get("id",1)))
				var anchor=_character_bubble_anchor(bubble_id,e.type=="staff",moving,pose,str(d.get("art_role",d.get("role","chef"))))
				# Text stays upright when the actor faces left. Position and gap use
				# the same local scale as the animal, including zoom/detail mode.
				art_transform(p,0,Vector2.ONE*ui_scale*zoom*(1.55 if game.wall_detail else 1.0))
				bubble(anchor,bubble_symbol)
			art_transform(Vector2.ZERO)
	if game.editing and game.build_tools!=null:
		for opening in openings:
			if int(opening.id)==game.build_tools.opening_source_id:OpeningArt.selection_outline(self,opening)
	if show_objects and game.build_tools!=null:game.build_tools.paint_stroke.draw_walls(self)
	# Plot boards are editing affordances. Keep their ground anchors centered
	# inside the actual purchase boundary and readable over retained foliage.
	if game.editing and game.model.has_method("expansion_parcels"):
		for parcel in game.model.expansion_parcels():
				if not parcel.owned and parcel.visible:_parcel_sign(parcel)
	# Do not expose the presentation offset to resize anchoring or input projection.
	origin = gameplay_origin
func _draw_legacy_pavement(ground_view: Rect2):
	for z in range(ExteriorExtent.PAVEMENT_Z_MIN,ExteriorExtent.PAVEMENT_Z_MAX):
		for x in [PAVEMENT_EDGE, PAVEMENT_EDGE+PAVEMENT_ROW_WIDTH, PAVEMENT_EDGE+PAVEMENT_ROW_WIDTH*2]:
			if not _ground_cell_visible(x,z,ground_view):continue
			poly([iso(x,z),iso(x+PAVEMENT_ROW_WIDTH,z),iso(x+PAVEMENT_ROW_WIDTH,z+1),iso(x,z+1)],"d7dcc2" if z%2 else "dfe0c8")
			line(iso(x,z),iso(x+PAVEMENT_ROW_WIDTH,z),"c7cbae",.7)
			line(iso(x,z),iso(x,z+1),"c7cbae",.7)
func _draw_legacy_floor(ground_view: Rect2):
	for z in range(game.model.MAX_DEPTH):
		for x in range(game.model.MAX_WIDTH):
			if not _ground_cell_visible(x,z,ground_view):continue
			if game.model.has_method("is_floor_owned") and not game.model.is_floor_owned(Vector2i(x,z)):continue
			var style=game.model.floor_style_at(Vector2i(x,z))
			if style=="":continue
			var palette=ground_art.floor_palette(style)
			poly([iso(x,z),iso(x+1,z),iso(x+1,z+1),iso(x,z+1)],palette[posmod(x+z,2)])
			line(iso(x,z),iso(x+1,z),ground_art.floor_line(style),.65)
			line(iso(x,z),iso(x,z+1),ground_art.floor_line(style),.65)
			if style=="warm_oak" and (x*7+z*13)%11==0:
				line(iso(x+.3,z+.4),iso(x+.56,z+.4),Color(.69,.56,.35,.13),.6)
func _grass(size: Vector2):
	prepare_grass(size)
	# Match the floor transform: a tuft stays on the same piece of land while
	# panning, zooming and resizing. Road, pavement and finishes cover it later.
	art_transform(origin,0,Vector2.ONE*(tile.x/39.0))
	if use_grass_mesh:
		draw_mesh(grass_mesh,null)
	else:
		draw_multiline(_grass_left,col(Color(.44,.57,.30,.33)),.75,true)
		draw_multiline(_grass_right,col(Color(.53,.64,.37,.30)),.70,true)
	art_transform(Vector2.ZERO)

func prepare_grass(_size: Vector2):
	if _grass_left.is_empty():
		# One finite field around the entire 18x18 map, with broad camera margins.
		# Integer hashes supply stable gaps, offset, height and occasional paired
		# tufts without RNG state, per-frame arrays, or physical/collision nodes.
		for z in range(ExteriorExtent.GRASS_MIN,ExteriorExtent.GRASS_MAX):
			for x in range(ExteriorExtent.GRASS_MIN,ExteriorExtent.GRASS_MAX):
				# Leave the fixed street/pavement strip and its AA edge clear.
				if x>=-6 and x<0:continue
				var seed=posmod((x*73856093) ^ (z*19349663) ^ 41717,104729)
				if seed%11!=0:continue
				var p=GroundArt.point(x+.20+float(seed%97)/162.0,z+.20+float((seed/97)%89)/149.0)
				var height=3.2+float(seed%29)*.065
				var spread=.80+float(seed%17)*.03
				var form=posmod(seed/11,3)
				if form==0:
					# Quiet three-blade fan.
					_grass_left.append(p);_grass_left.append(p+Vector2(-2.3*spread,-height*.80))
					_grass_left.append(p+Vector2(.35,0));_grass_left.append(p+Vector2(.10,-height))
					_grass_right.append(p);_grass_right.append(p+Vector2(2.4*spread,-height*.70))
				elif form==1:
					# A looser upright clump, with staggered roots and leaning tips.
					for j in range(4):
						var root=p+Vector2(j*.75,0)
						_grass_left.append(root);_grass_left.append(root+Vector2(-.9+j*.65,-height*(.65+j*.13)))
				else:
					# A low wind-swept pair; open space separates the two leaves.
					_grass_left.append(p);_grass_left.append(p+Vector2(-3.8*spread,-height*.36))
					_grass_right.append(p+Vector2(1.8,0));_grass_right.append(p+Vector2(5.2*spread,-height*.51))
				if seed%3==0:
					var nearby=p+Vector2(4.3*spread,1.2-float(seed%5)*.35)
					_grass_left.append(nearby);_grass_left.append(nearby+Vector2(-1.6*spread,-height*.60))
					_grass_right.append(nearby);_grass_right.append(nearby+Vector2(1.7*spread,-height*.55))
	# Geometry and feather widths live in world space. Camera changes only the
	# draw transform; the mesh rebuilds solely for an explicit opacity change.
	if use_grass_mesh and (grass_mesh==null or _grass_opacity!=opacity):
		# Retained tapered blades reuse the existing deterministic anchors. The
		# wider accents are confined outside the full buildable and walkway reserves.
		grass_mesh=ExteriorGrassArt.make_mesh(_grass_left,_grass_right,opacity)
		_grass_opacity=opacity
		grass_mesh_rebuilds+=1
func _wall(a: Vector2,b: Vector2,n: Vector2,c1,c2):
	var finish=str(game.model.shell_material)
	var end_color=Color("b8c7a8");var cap_color=Color("fff1d0")
	if finish=="original":
		poly([iso(a.x,a.y),iso(b.x,b.y),iso(b.x,b.y,WALL_HEIGHT),iso(a.x,a.y,WALL_HEIGHT)],c1)
		poly([iso(a.x,a.y),iso(b.x,b.y),iso(b.x,b.y,36),iso(a.x,a.y,36)],c2)
		line(iso(a.x,a.y,36),iso(b.x,b.y,36),"a9b797",2*ui_scale)
	else:
		var length=a.distance_to(b);var direction=(b-a).normalized()
		var texture=WallArt.texture_for(finish,"full")
		end_color=Color(WallArt.PALETTES[finish].end);cap_color=Color(WallArt.PALETTES[finish].cap)
		for index in range(ceili(length)):
			var p0=a+direction*index;var p1=a+direction*minf(index+1,length)
			draw_polygon(PackedVector2Array([iso(p0.x,p0.y),iso(p1.x,p1.y),iso(p1.x,p1.y,WALL_HEIGHT),iso(p0.x,p0.y,WALL_HEIGHT)]),PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE]),PackedVector2Array([Vector2(0,1),Vector2(p0.distance_to(p1),1),Vector2(p0.distance_to(p1),0),Vector2.ZERO]),texture)
	poly([iso(b.x,b.y),iso(b.x+n.x,b.y+n.y),iso(b.x+n.x,b.y+n.y,WALL_HEIGHT),iso(b.x,b.y,WALL_HEIGHT)],end_color)
	poly([iso(a.x,a.y,WALL_HEIGHT),iso(b.x,b.y,WALL_HEIGHT),iso(b.x+n.x,b.y+n.y,WALL_HEIGHT),iso(a.x+n.x,a.y+n.y,WALL_HEIGHT)],cap_color)

func hit_wall(screen:Vector2)->Dictionary:
	if objects_hidden():return {}
	update_projection()
	var walls=game.model.built_wall_segments()
	walls.sort_custom(func(a,b):return int(a.x+a.z)>int(b.x+b.z))
	for wall in walls:
		var ends=WallGeometry.endpoints(wall)
		var normal=(Vector2.DOWN if wall.axis=="x" else Vector2.RIGHT)*WallGeometry.THICKNESS*.5
		var a:Vector2=ends[0]+normal;var b:Vector2=ends[1]+normal
		var height=float(WallGeometry.HEIGHT_PIXELS[wall.height])
		var polygon=PackedVector2Array([iso(a.x,a.y),iso(b.x,b.y),iso(b.x,b.y,height),iso(a.x,a.y,height)])
		if Geometry2D.is_point_in_polygon(screen,polygon):return wall
	return {}

func _scenery_tree_visible_at(world:Vector2)->bool:
	# Render-only scenery. Sale signs need clear ground while their plots are
	# shown in Decorate; leaving that view restores trees on unowned land.
	var cell=Vector2i(floori(world.x),floori(world.y))
	if game.model.is_floor_owned(cell):return false
	if not game.editing:return true
	var parcel=game.model.parcel_at(cell)
	return parcel.is_empty() or not parcel.visible
func _scenery_tree(world:Vector2,scale:float):
	if _scenery_tree_visible_at(world):_tree(iso(world.x,world.y),scale)
func _tree(p: Vector2,s: float):
	# Stable authored variants use the existing tree identities (source scales).
	# The rear tree is mirrored; the corner sapling is slightly narrower. These
	# value-only transforms preserve ground anchors and add no draw calls.
	var horizontal_scale := -1.0 if is_equal_approx(s,.86) else (.92 if is_equal_approx(s,.78) else 1.0)
	s*=ui_scale*zoom*(1.55 if is_instance_valid(game) and game.wall_detail else 1.0)
	var crown_bounds=RenderVisibility.local_bounds(p,s,Rect2(-58,-145,116,152))
	var shadow_bounds=Rect2(p+Vector2(2,0)-Vector2(35,11)*s,Vector2(70,22)*s)
	if not render_bounds_visible(crown_bounds.merge(shadow_bounds)):return
	# Its old two-pixel shadow offset is screen-relative, so keep it live.
	ellipse(p+Vector2(2,0),Vector2(35,11)*s,Color(.45,.57,.32,.12))
	if use_cached_moving_art and is_equal_approx(opacity,1.0) and moving_atlas.is_ready():
		var rect:Rect2=moving_atlas.rectangles["tree"]
		var stretch:=Vector2(s*horizontal_scale,s)
		var destination:=Rect2(p+rect.position*stretch,rect.size*stretch)
		# Godot flips negative widths in place; it does not move their origin.
		# Supply the mirrored left edge while retaining the negative flip flag.
		if destination.size.x<0:destination.position.x+=destination.size.x
		if absf(s)<=MovingAtlas.BAKE_SCALE or not destination.abs().intersects(get_viewport_rect()):
			draw_texture_rect_region(moving_atlas.texture,destination,moving_atlas.regions["tree"])
			return
	_tree_crown_legacy(p,s,horizontal_scale)
func _tree_crown_legacy(p:Vector2,s:float,horizontal_scale:float=1.0):
	# Both the cached atlas and fallback share the same authored tree contours.
	exterior_tree_art.draw_tree(self,p,s,horizontal_scale)
func _parcel_ground():
	if not game.editing or not game.model.has_method("expansion_parcels"):return
	var pointer=get_viewport().get_mouse_position()
	var hovered=hit_parcel(pointer) if game.interaction!=null and not game.interaction._over_ui(pointer) else ""
	for parcel in game.model.expansion_parcels():
		if parcel.owned or not parcel.visible:continue
		var x=float(parcel.x);var z=float(parcel.z);var w=float(parcel.w);var h=float(parcel.h)
		var corners=[iso(x+.07,z+.07),iso(x+w-.07,z+.07),iso(x+w-.07,z+h-.07),iso(x+.07,z+h-.07)]
		poly(corners,("dce1bd" if parcel.unlocked else "d5d7bd") if str(parcel.id)==hovered else "cdd6b5")
		if str(parcel.id)==hovered:
			for i in range(4):line(corners[i],corners[(i+1)%4],"788f62",2.0*ui_scale)
		for i in range(4):
			var a=corners[i];var b=corners[(i+1)%4]
			var pieces=maxi(2,int(a.distance_to(b)/9))
			for j in range(pieces):
				if j%2==0:line(a.lerp(b,float(j)/pieces),a.lerp(b,float(j+1)/pieces),"8ea57c",1.1)
		for xx in range(int(x)+1,int(x+w)):line(iso(xx,z+.08),iso(xx,z+h-.08),Color(.57,.66,.46,.25),.7)
		for zz in range(int(z)+1,int(z+h)):line(iso(x+.08,zz),iso(x+w-.08,zz),Color(.57,.66,.46,.25),.7)
func _parcel_sign_point(parcel:Dictionary)->Vector2:
	# Every sign stays centered. Scenery on visible sale plots is hidden
	# temporarily by _scenery_tree_visible_at; hit testing shares this anchor.
	return iso(float(parcel.x)+float(parcel.w)*.5,float(parcel.z)+float(parcel.h)*.5)

func _parcel_sign(parcel):
	var center=_parcel_sign_point(parcel)
	var unit=ui_scale*zoom*(1.55 if game.wall_detail else 1.0)
	art_transform(center,0,Vector2.ONE*unit)
	ellipse(Vector2(0,1),Vector2(13,4),Color(.32,.42,.24,.13))
	line(Vector2(0,0),Vector2(0,-29),"a2885d",4)
	rounded_poly([Vector2(-44,-57),Vector2(44,-57),Vector2(44,-19),Vector2(-44,-19)],3,"dfc795" if parcel.unlocked else "d4c6a7")
	line(Vector2(-41,-54),Vector2(41,-54),"ecdbb2",1)
	var font=game.ArtFont
	draw_string(font,Vector2(-34,-39),"FOR SALE",HORIZONTAL_ALIGNMENT_CENTER,68,12,Color("617452"))
	draw_string(font,Vector2(-38,-25),preload("res://scripts/cafe_money.gd").amount(int(parcel.cost)),HORIZONTAL_ALIGNMENT_CENTER,76,13,Color("796746"))
	if not parcel.unlocked:
		# Small geometry-only lock, avoiding emoji/font fallback or extra words.
		poly([Vector2(32,-43),Vector2(39,-43),Vector2(39,-37),Vector2(32,-37)],"8b876b")
		line(Vector2(33,-43),Vector2(33,-46),"8b876b",1.4);line(Vector2(33,-46),Vector2(38,-46),"8b876b",1.4);line(Vector2(38,-46),Vector2(38,-43),"8b876b",1.4)
	art_transform(Vector2.ZERO)
func hit_parcel(screen:Vector2) -> String:
	if not is_instance_valid(game) or not game.editing or not game.model.has_method("expansion_parcels"):return ""
	update_projection()
	var unit=ui_scale*zoom*(1.55 if game.wall_detail else 1.0)
	var parcels=game.model.expansion_parcels();parcels.reverse()
	for parcel in parcels:
		if parcel.owned or not parcel.visible:continue
		var center=_parcel_sign_point(parcel)
		if Rect2(center+Vector2(-46,-59)*unit,Vector2(92,43)*unit).has_point(screen):return str(parcel.id)
	var parcel=game.model.parcel_at(screen_to_cell(screen))
	return str(parcel.id) if not parcel.is_empty() and not parcel.owned and parcel.visible else ""

func prism(p: Vector2,w: float,d: float,h: float,top,left,right):
	d=w*.5 # Same 2:1 projection as floor and wall edges.
	var a=p+Vector2(-w/2,-d/2);var b=p+Vector2(w/2,-d/2);var c=p+Vector2(w/2,d/2);var e=p+Vector2(-w/2,d/2)
	# Isometric local diamonds, independently shaded with pastel fills.
	a=p+Vector2(0,-d);b=p+Vector2(w,0);c=p+Vector2(0,d);e=p+Vector2(-w,0)
	rounded_poly([e,c,c-Vector2(0,h),e-Vector2(0,h)],1.8,left)
	rounded_poly([c,b,b-Vector2(0,h),c-Vector2(0,h)],1.8,right)
	rounded_poly([a-Vector2(0,h),b-Vector2(0,h),c-Vector2(0,h),e-Vector2(0,h)],2.4,top)

func _dining_style(id:int,variant:String="")->String:
	if variant=="" and is_instance_valid(game):variant=game.model.dining_variant_for(id)
	return DiningStyles.style_for_variant(variant)

func item(kind: String,p: Vector2,rot: int,id: int,variant:String=""):
	if DiningStyles.is_product(kind):
		variant=DiningStyles.variant_for_product(kind)
		var direction=Vector2.DOWN.rotated(rot*PI/2);var offset=Vector2((direction.x-direction.y)*28,(direction.x+direction.y)*14)
		var table_at=p-offset*.5;var seat_at=p+offset*.5
		if offset.y<0:item("chair",seat_at,rot,0,variant)
		item("table",table_at,rot,0,variant)
		if offset.y>=0:item("chair",seat_at,rot,0,variant)
		return
	if furniture_art.draw_item(self,kind,p,rot,id): return
	match kind:
		"table":
			if not dining_art.table(self,p,rot,_dining_style(id,variant)):_table_body(p)
			var vase=p+_table_vase_point(id)
			ellipse(vase,Vector2(3,1.5),"b37e4a")
			poly([vase+Vector2(-3,-8),vase+Vector2(3,-8),vase+Vector2(2,0),vase+Vector2(-2,0)],"e6dcb8")
			line(vase+Vector2(0,-7),vase+Vector2(0,-16),"6f9455",1.5)
			ellipse(vase+Vector2(2,-13),Vector2(3,1.7),"85a161")
		"chair":
			if rot in [1,2]: _chair(p,rot,true,_dining_style(id,variant))
			_chair(p,rot,false,_dining_style(id,variant))
			if rot in [0,3]: _chair(p,rot,true,_dining_style(id,variant))
		"stove":
			prism(p,30,11,27,"81998b","c3a068","ae8d55")
			line(p+Vector2(-26,-22),p+Vector2(-3,-13),"d5b57d",1.2)
			ellipse(p+Vector2(3,-27),Vector2(12,5.5),"526f64")
			ellipse(p+Vector2(3,-30),Vector2(10,4.8),"bdc3a4")
			ellipse(p+Vector2(3,-32),Vector2(8.4,3.8),"e4bc6c")
			line(p+Vector2(13,-31),p+Vector2(25,-29),"547167",2.8)
			ellipse(p+Vector2(-14,-32),Vector2(7.5,3.4),"607d70")
		"beverage":
			prism(p,30,11,28,"eee0b6","b6b99a","9aa98b")
			prism(p+Vector2(0,-28),16,7,15,"6f8b79","5b786b","446958")
			line(p+Vector2(-8,-35),p+Vector2(11,-29),"b8a66d",2)
			for d in [Vector2(-5,-21),Vector2(8,-17)]:
				poly([p+d+Vector2(-3,-6),p+d+Vector2(3,-6),p+d+Vector2(2,0),p+d+Vector2(-2,0)],"fff1cf")
				ellipse(p+d+Vector2(0,-6),Vector2(3,1.5),"b29466")
			prism(p+Vector2(-18,-34),4,3,13,"e8d7a0","d3ae68","c19a55")
		"sink":
			prism(p,29,11,27,"91aaa0","b2b295","9da68b")
			outlined_ellipse(p+Vector2(0,-27),Vector2(18,9),"abc9be","6c978d",3)
			ellipse(p+Vector2(0,-27),Vector2(13,6),"7da79c")
			line(p+Vector2(5,-33),p+Vector2(5,-45),"d4e4cf",2.5)
			art_arc(p+Vector2(1,-45),4,PI,TAU,12,col("d4e4cf"),2.5)
			line(p+Vector2(-3,-45),p+Vector2(-3,-41),"d4e4cf",2.5)
		"bin": _bin(p,rot,id)
		"counter":
			prism(p,29,11,28,"e5c78f","c3a168","b3925b")
			line(p+Vector2(-24,-23),p+Vector2(-3,-14),"a17e4b",1.2)
			line(p+Vector2(-24,-23),p+Vector2(-24,-3),"a17e4b",1.2)
			line(p+Vector2(-3,-14),p+Vector2(-3,6),"a17e4b",1.2)
			line(p+Vector2(-16,-12),p+Vector2(-10,-9),"8f7950",1.5)
			line(p+Vector2(5,-11),p+Vector2(24,-21),"a98b55",1)
			line(p+Vector2(5,-11),p+Vector2(5,9),"a98b55",1)
			line(p+Vector2(24,-21),p+Vector2(24,-2),"a98b55",1)
			line(p+Vector2(11,-9),p+Vector2(17,-12),"8f7950",1.5)
		"plant": _plant(p)
		"lamp": _lamp(p)
		"bookshelf":
			prism(p,22,11,61,"c7a169","a5804b","b58d51")
			for row in range(2):
				var y=-18-row*24
				poly([p+Vector2(-19,y-24),p+Vector2(-1,y-15),p+Vector2(-1,y+4),p+Vector2(-19,y-5)],"7c724b")
				for i in range(4):
					var x=-16+i*4;var yy=y-18+i*2
					line(p+Vector2(x,yy),p+Vector2(x,yy+15),["e2dcb5","8da077","d0b17a","b9c29a"][i],2.7)
			ellipse(p+Vector2(0,-71),Vector2(7,4),"94a269")
			poly([p+Vector2(-4,-69),p+Vector2(4,-69),p+Vector2(3,-61),p+Vector2(-3,-61)],"b99867")
		"rug":
			poly([p+Vector2(0,-19),p+Vector2(35,0),p+Vector2(0,19),p+Vector2(-35,0)],"cfaa70")
			for i in range(-2,3):
				line(p+Vector2(-25+i*4, -i*2),p+Vector2(i*4,13-i*2),"eddbac",2)
				line(p+Vector2(i*5,-13+i*2.5),p+Vector2(25+i*5,i*2.5),"eddbac",2)
		"bench":
			prism(p,25,12,19,"b4bd92","96a577","91a174")
			poly([p+Vector2(-25,-20),p+Vector2(0,-7),p+Vector2(0,-32),p+Vector2(-25,-45)],"a1b28b")
			for x in [-18,18]: line(p+Vector2(x,2),p+Vector2(x,-13),"a2824f",3)
		"divider":
			prism(p,27,5,57,"e6ddb8","9baa85","889d7a")
			line(p+Vector2(-25,-53),p+Vector2(0,-40),"b3c09d",2)
		_: pass

func _table_body(p:Vector2):
	if furniture_art.try_draw_static(self,"table_body",p,0):return
	ellipse(p+Vector2(1,1),Vector2(25,10),Color(.45,.39,.23,.09))
	for d in [Vector2(-17,-5),Vector2(18,-5),Vector2(-16,6),Vector2(17,6)]:
		line(p+d,p+d+Vector2(0,-DiningPlacement.table_height(30)),"947340",3)
		line(p+d+Vector2(1,-1),p+d+Vector2(1,-DiningPlacement.table_height(29)),"b3915b",1)
	ellipse(p+Vector2(0,-DiningPlacement.table_height(29)),DiningPlacement.ROUND_TOP,"b38c55")
	outlined_ellipse(p+Vector2(0,-DiningPlacement.table_height(33)),DiningPlacement.ROUND_TOP,"d1ad74","bb9966",1.0)
	ellipse(p+Vector2(0,-DiningPlacement.table_height(34)),Vector2(22,9.5),"dbb984")

func _lamp(p:Vector2):
	if furniture_art.try_draw_static(self,"lamp",p,0):return
	LampArt.draw_lamp(self,p)

func _plant(p: Vector2):
	if furniture_art.try_draw_static(self,"plant",p,0):return
	ellipse(p+Vector2(1,1),Vector2(12,5),Color(.45,.39,.23,.08))
	rounded_poly([p+Vector2(-10,-17),p+Vector2(10,-17),p+Vector2(7,-1),p+Vector2(-7,-1)],1.5,"bc8958")
	ellipse(p+Vector2(0,-17),Vector2(10,4),"d0a472")
	ellipse(p+Vector2(0,-18),Vector2(7,2.5),"947345")
	line(p+Vector2(0,-18),p+Vector2(1,-35),"849255",1.8)
	line(p+Vector2(1,-35),p+Vector2(-1,-67),"849255",1.8)
	var leaves=[[-11,-49,-.56,9,4.3],[11,-44,.60,10,4.5],[-10,-32,-.48,8.8,4.1],[9,-60,.30,8.5,4.3],[-3,-67,-.15,7.3,4.2]]
	for i in range(leaves.size()):
		var d=leaves[i]
		var q=p+Vector2(d[0],d[1])
		line(p+Vector2(0,d[1]+4),q,"849255",1.3)
		var points=[]
		for k in range(24): points.append(q+Vector2(cos(k*TAU/24)*d[3],sin(k*TAU/24)*d[4]).rotated(d[2]))
		poly(points,"73924f" if i%2 else "88a15e")
		line(q+Vector2(-d[3]*.6,0).rotated(d[2]),q+Vector2(d[3]*.6,0).rotated(d[2]),Color(.65,.73,.43,.65),.7)

func _staff_visual_heading(staff:Dictionary,pose:Dictionary) -> Vector2:
	# Feet track the rendered body (including a short within-cell work lean),
	# but a traveller looks along its actual route. Retreating from a work lean
	# must not turn a north-west walk into a one-frame front-facing diagonal.
	var travelling=str(staff.get("art_action","idle")) in ["walking","carrying_to_pass","carrying_plate","carrying_drink","carrying_dishes","carrying_trash"]
	if travelling:
		var path:Array=staff.get("path",[])
		for index in range(int(staff.get("index",0)),path.size()):
			var cell=path[index]
			var heading=Vector2(cell.x+.5,cell.y+.5)-staff.pos
			if heading.length_squared()>.000025:return heading.normalized()
		var last:Vector2=staff.get("art_heading",Vector2.ZERO)
		if last.length_squared()>.000025:return last.normalized()
	var direction:Vector2=staff.get("art_station",staff.pos+Vector2(1,-1))-staff.pos
	if str(staff.get("art_action","")) in ["sweeping","mopping"]:direction=staff.get("art_target",staff.pos)-staff.pos
	if direction.length_squared()<.01:direction=staff.get("art_heading",Vector2(1,-1))
	# Once a work action begins, face its station immediately. A decaying walk
	# blend must not flip the body/held order halfway through the .65 handoff.
	var working=str(staff.get("art_action","")) in ["taking_order","preparing_food","cooking","plating","preparing_drink","placing_plate","dropping_dishes","collecting_plate","collecting_drink","serving","collecting","wiping","washing","disposing_trash","sweeping","mopping","taking_payment"]
	if not working and float(pose.get("blend",0))>.02:direction=pose.get("heading",direction)
	# Rendering reads these values; it never writes the routing heading back.
	return direction

static func _kitchen_visual_action(action:String,staff:bool,role:String)->String:
	return "idle" if staff and role=="chef" and action=="plating" else action

func character(p:Vector2,id:int,staff=false,moving=false,seated=false,action="idle",progress=0.0,reach=Vector2(18,-28),look=Vector2(1,0),payload="none",tool="none",pose={},role="chef"):
	var species=posmod(id,3);var away=bool(pose.get("view_back",look.x+look.y<-.5))
	var shirt=["9cbbbd","c98e83","d6b16b","a9b78a"][id%4] if not staff else {"chef":"739c7f","waiter":"b99578","cleaner":"91b2ad","cashier":"b68b92"}.get(role,"739c7f")
	var options=pose.duplicate()
	# Keep the existing ready-meal handoff timing, without a plating gesture.
	var visual_action=_kitchen_visual_action(action,staff,role)
	options.merge({"role":role if staff else "customer","shirt":shirt,"action":visual_action,"progress":progress,"payload":payload,"tool":tool,"reach":reach,"seat_mix":float(pose.get("seat_mix",1.0 if seated else 0.0)),"blink":is_instance_valid(game) and fposmod(game.animation_time+id*1.73,4.6)<.13,"chef_hat":staff and role=="chef"},true)
	var geometry=directional_character.draw(self,p,species,away,moving,float(pose.get("phase",0)),staff,false,options)
	var payment_pose=geometry.get("payment_pose",{})
	var cooking_pose=geometry.get("cooking_pose",{})
	var dining_pose=geometry.get("dining_pose",{})
	if is_instance_valid(game):render_contacts.append({"id":id,"staff":staff,"action":action,"progress":progress,"payload":payload,"arm_length":12.0 if not cooking_pose.is_empty() else 10.5,"leg_length":9.5,"limb_segments":2 if not cooking_pose.is_empty() else 1,"target_error":geometry.near_hand.distance_to(reach),"prop_target_error":geometry.carry.distance_to(reach),"pickup_pose":geometry.get("pickup_pose",{}),"washing_pose":geometry.get("washing_pose",{}),"dining_pose":dining_pose,"payment_pose":payment_pose,"payment_target_error":payment_pose.hand.distance_to(payment_pose.target) if not payment_pose.is_empty() else -1.0,"lean":0.0})

func _character_r13_rejected(p: Vector2,id: int,staff=false,moving=false,seated=false,action="idle",progress=0.0,reach=Vector2(18,-28),look=Vector2(1,0),payload="none",tool="none",pose={},role="chef"):
	var species=id%3
	var direction_unit=look.normalized()
	var away=direction_unit.x+direction_unit.y<-.55
	var head_view=3 if away else (1 if absf(direction_unit.x-direction_unit.y)<.35 else (2 if absf(direction_unit.x+direction_unit.y)<.35 else 0))
	var fur="efe5c7" if species!=1 else "c68b46"
	var shirt=["9cbbbd","c98e83","d6b16b","a9b78a"][id%4] if not staff else {"chef":"739c7f","waiter":"b99578","cleaner":"91b2ad","barista":"d2b485"}.get(role,"739c7f")
	var reach_overlay=bool(pose.get("reach_overlay",false))
	var hide_reach=bool(pose.get("hide_reach",false))
	var phase=float(pose.get("phase",0.0))
	var blend=float(pose.get("blend",0.0))
	var mirror=float(pose.get("mirror",1.0))
	var seat_mix=float(pose.get("seat_mix",1.0 if seated else 0.0))
	var swing=sin(phase*TAU)*2.1*blend*(1.0-seat_mix)
	var forward=look.normalized()
	if forward.length_squared()<.01:forward=Vector2(0,-1)
	var across=Vector2(-forward.y,forward.x)
	var fwd=Vector2((forward.x-forward.y)*25*mirror,(forward.x+forward.y)*12.5)
	var side=Vector2((across.x-across.y)*25*mirror,(across.x+across.y)*12.5)
	var carry:Vector2=pose.get("carry_hand",CompactPose.CARRY)
	var gesture=CompactPose.gesture(action,progress,swing,seated,payload,carry)
	var weight:Vector2=pose.get("body_offset",Vector2.ZERO)
	var bob=float(pose.get("body_bob",0.0))*(1.0-seat_mix)
	var shift=Vector2(weight.x*mirror*(1.0-seat_mix),bob+float(gesture.nod))
	var body=p+shift
	if not reach_overlay:
		_person_shadow(p)
		if species==1:_fox_tail(body,fur)
		for index in range(2):
			var x=-4.0 if index==0 else 4.0
			var sign=-1.0 if index==0 else 1.0
			var hip=Vector2(x,-11.5).lerp(side*(sign*.12)+fwd*.29-Vector2(0,17),seat_mix)
			var angle=sin(phase*TAU)*.22*sign*blend*(1.0-seat_mix)
			var direction=Vector2(sin(angle),cos(angle)).lerp(Vector2(.08,-.02)+Vector2.DOWN,seat_mix).normalized()
			var foot=hip+direction*LEG_LENGTH
			_round_limb(body+hip,body+foot,"858366",4.0)
			_foot(body+foot+Vector2(1,-.25))
		_body_shape(body,shirt,seated,fwd,side)
		_round_limb(body+gesture.left.pivot,body+gesture.left.tip,fur,4.8)
	var hand:Vector2=gesture.right.tip
	var work_hand:Vector2=gesture.left.tip if tool=="cloth" or (tool in ["mop","broom"] and payload!="none") else hand
	var prop=CompactPose.prop_offset(action,progress,reach-shift,carry,payload)
	if tool=="cloth":work_hand=reach-shift+Vector2(sin(progress*TAU*2)*2.5,0)
	var tool_floor=reach-shift+Vector2(3,-3) if action in ["sweeping","mopping"] else Vector2(22,2)
	var foreground_sip=not staff and seated and not away and action=="drinking" and payload=="drink"
	if is_instance_valid(game):render_contacts.append({"id":id,"staff":staff,"action":action,"progress":progress,"payload":payload,"arm_length":ARM_LENGTH,"leg_length":LEG_LENGTH,"limb_segments":1,"target_error":(hand+shift).distance_to(reach),"prop_target_error":(prop+shift).distance_to(reach),"lean":0.0})
	if not hide_reach:
		_round_limb(body+gesture.right.pivot,body+hand,fur,4.8)
		_action_prop(body,prop,action,progress,"none" if foreground_sip else payload,tool,work_hand,hand,tool_floor)
	if reach_overlay:return
	if staff and not away:_apron(body)
	var head=body+Vector2(3,3)*seat_mix
	var blink=is_instance_valid(game) and fposmod(game.animation_time+id*1.73,4.6)<.13
	_draw_head(head,species,away,blink,staff and role=="chef",action=="blocked",head_view)
	if foreground_sip:
		_action_prop(body,prop,action,progress,payload,tool,work_hand,hand,tool_floor)

func _round_limb(start:Vector2,finish:Vector2,color,width:float):
	if use_cached_moving_art and is_equal_approx(opacity,1.0) and moving_atlas.is_ready():
		var key=moving_atlas.limb_key(start.distance_to(finish),color,width)
		if key!="" and art_cache_covers(Rect2(start,Vector2.ZERO).expand(finish).grow(width),MovingAtlas.BAKE_SCALE):moving_atlas.draw_limb(self,key,start,finish);return
	_round_limb_legacy(start,finish,color,width)

func _round_limb_legacy(start:Vector2,finish:Vector2,color,width:float):
	# One rounded piece: no elbow, knee, extra joint or target-driven length.
	line(start,finish,color,width)
	ellipse(start,Vector2.ONE*width*.5,color)
	ellipse(finish,Vector2.ONE*width*.5,color)

func _rigid_part(key:String,p:Vector2)->bool:
	if use_cached_moving_art and is_equal_approx(opacity,1.0) and moving_atlas.is_ready() and art_cache_covers(Rect2(p+moving_atlas.rectangles[key].position,moving_atlas.rectangles[key].size),MovingAtlas.BAKE_SCALE):moving_atlas.draw_part(self,key,p);return true
	return false
func _person_shadow(p:Vector2):
	if not _rigid_part("shadow",p):_person_shadow_legacy(p)
func _person_shadow_legacy(p:Vector2):ellipse(p,Vector2(8.5,3.2),Color(.36,.43,.27,.17))
func _foot(p:Vector2):
	if not _rigid_part("foot",p):_foot_legacy(p)
func _foot_legacy(p:Vector2):ellipse(p,Vector2(3.8,2.3),"817657")
func _fox_tail(body:Vector2,fur):
	if not _rigid_part("fox_tail",body):_fox_tail_legacy(body,fur)
func _fox_tail_legacy(body:Vector2,fur):
	rounded_poly([body+Vector2(-7,-20),body+Vector2(-17,-16),body+Vector2(-23,-22),body+Vector2(-20,-27),body+Vector2(-14,-23),body+Vector2(-7,-26)],2.5,fur)
	rounded_poly([body+Vector2(-23,-22),body+Vector2(-20,-27),body+Vector2(-16,-24),body+Vector2(-18,-20)],1.2,"f3e7ca")
func _body_shape(body:Vector2,shirt:String,seated:bool,fwd:Vector2,side:Vector2):
	if use_cached_moving_art and is_equal_approx(opacity,1.0) and moving_atlas.is_ready():
		var key=moving_atlas.body_key(shirt,seated,fwd,side)
		if key!="" and art_cache_covers(Rect2(body+moving_atlas.rectangles[key].position,moving_atlas.rectangles[key].size),MovingAtlas.BAKE_SCALE):moving_atlas.draw_part(self,key,body);return
	_body_shape_legacy(body,shirt,seated,fwd,side)
func _body_shape_legacy(body:Vector2,shirt:String,seated:bool,fwd:Vector2,side:Vector2):
	if seated:
		rounded_poly([body+Vector2(-8,-27),body+Vector2(8,-27),body+Vector2(10,-17),body+Vector2(-9,-17)],4.0,shirt)
		rounded_poly([body-side*.16-Vector2(0,19),body+side*.16-Vector2(0,19),body+fwd*.33+side*.16-Vector2(0,16),body+fwd*.33-side*.16-Vector2(0,16)],3.5,shirt)
	else:
		rounded_poly([body+Vector2(-8,-28),body+Vector2(8,-28),body+Vector2(10,-12),body+Vector2(-10,-12)],4.3,shirt)
	line(body+Vector2(-6,-14),body+Vector2(6,-14),Color(.96,.91,.76,.28),1.0)
func _apron(body:Vector2):
	if not _rigid_part("apron",body):_apron_legacy(body)
func _apron_legacy(body:Vector2):
	rounded_poly([body+Vector2(-5,-25),body+Vector2(5,-25),body+Vector2(7,-13),body+Vector2(-7,-13)],2,"efe5c5")
	line(body+Vector2(-4,-28),body+Vector2(-3,-21),"d4cdae",1.4)
	line(body+Vector2(4,-28),body+Vector2(3,-21),"d4cdae",1.4)
	rounded_poly([body+Vector2(-3,-19),body+Vector2(3,-19),body+Vector2(2.5,-15),body+Vector2(-2.5,-15)],1,"d5d8b9")

func _draw_head(p:Vector2,species:int,away:bool,blink:bool,chef_hat:bool,blocked:bool,view:int=-1):
	if use_cached_heads and is_equal_approx(opacity,1.0) and head_atlas.is_ready() and art_cache_covers(Rect2(p+HeadAtlas.ART_RECT.position,HeadAtlas.ART_RECT.size),HeadAtlas.BAKE_SCALE):
		head_atlas.draw_head(self,p,species,away,blink,chef_hat,blocked,view)
	else:_draw_head_legacy(p,species,away,blink,chef_hat,blocked,view)

func _face_ellipse(p:Vector2,size:Vector2,c):
	# Facial marks must not inherit the general helper's0.7px AA outline.
	# At play scale that outline made a tiny catchlight fill the entire eye.
	draw_colored_polygon(_ellipse_vertices(p,size),col(c))
func _face_line(a:Vector2,b:Vector2,c,width:float):draw_line(a,b,col(c),width,false)

func _draw_head_legacy(p:Vector2,species:int,away:bool,blink:bool,chef_hat:bool,blocked:bool,view:int=-1):
	var artist=DirectionalCharacter.new();artist.a=self;artist.origin=p;artist.back=away;artist.profile=view==2;artist.blink=blink;artist.chef_hat=chef_hat;artist.blocked=blocked;artist.head(species)

func _draw_head_r13_rejected(p:Vector2,species:int,away:bool,blink:bool,chef_hat:bool,blocked:bool,view:int=-1):
	# Original rounded silhouettes. Face features share a single low facial
	# plane; three-quarter, front, profile and back are separate readable views.
	if view<0:view=3 if away else 0
	var fur="efe5c7" if species!=1 else "c68b46"
	var cream="f7ecd2"
	var eye_ink="516248"
	var front=view==1
	var profile=view==2
	var near_x=5.0 if front else (5.5 if profile else 4.0)
	var far_x=-5.0 if front else (-6.0 if profile else -6.5)
	if species==0:
		rounded_poly([p+Vector2(far_x-3,-47),p+Vector2(far_x-4.5,-66),p+Vector2(far_x-1.0,-69),p+Vector2(far_x+2.4,-65),p+Vector2(far_x+3,-48)],3.0,fur)
		rounded_poly([p+Vector2(near_x-3,-47),p+Vector2(near_x-2.8,-69),p+Vector2(near_x+.8,-72),p+Vector2(near_x+3.5,-68),p+Vector2(near_x+3,-46)],3.1,fur)
		if not away:
			line(p+Vector2(far_x-.8,-63),p+Vector2(far_x,-51),"dfc6ae",1.8)
			line(p+Vector2(near_x+.1,-65),p+Vector2(near_x+.1,-51),"dfc6ae",1.8)
	elif species==1:
		rounded_poly([p+Vector2(-12,-42),p+Vector2(-12.5,-57),p+Vector2(-3,-49)],2.0,fur)
		rounded_poly([p+Vector2(2,-49),p+Vector2(9,-59),p+Vector2(12,-41)],2.0,fur)
		if not away:
			rounded_poly([p+Vector2(-10,-46),p+Vector2(-10,-53),p+Vector2(-5,-49)],1,"b57b52")
			rounded_poly([p+Vector2(5,-49),p+Vector2(8,-55),p+Vector2(10,-46)],1,"b57b52")
	else:
		ellipse(p+Vector2(-9,-47),Vector2(5.6,5.9),fur)
		ellipse(p+Vector2(8,-49),Vector2(5.2,5.7),fur)
		if not away:
			ellipse(p+Vector2(-9,-47),Vector2(2.8,3.2),"d7c4a2")
			ellipse(p+Vector2(8,-49),Vector2(2.5,3.1),"d7c4a2")
	ellipse(p+Vector2(0,-37.8),Vector2(13.5 if not profile else 12.5,13.0),fur)
	if away:
		ellipse(p+Vector2(8,-32.5),Vector2(4.8,4.0),fur)
		if species==1:ellipse(p+Vector2(7,-31),Vector2(3.6,2.2),"e5c197")
	else:
		var center_x=0.0 if front else (8.0 if profile else 4.5)
		if species==1:
			# Cream cheek mask joins the chin; no pointed tube-like muzzle.
			rounded_poly([p+Vector2(-11,-37),p+Vector2(-5,-35),p+Vector2(center_x,-38),p+Vector2(13,-35),p+Vector2(9,-28),p+Vector2(0,-25.5),p+Vector2(-9,-29)],3.8,cream)
		else:ellipse(p+Vector2(center_x,-32.5),Vector2(8.8 if not profile else 6.8,5.6),cream)
		var eye_positions=[Vector2(-5.0,-39.6),Vector2(5.0,-39.6)] if front else ([Vector2(7.0,-40)] if profile else [Vector2(-3.6,-40.7),Vector2(5.7,-40.0)])
		for eye in eye_positions:
			if blink:
				_face_line(p+eye+Vector2(-1.6,.2),p+eye+Vector2(0,-.6),eye_ink,1.0)
				_face_line(p+eye+Vector2(0,-.6),p+eye+Vector2(1.6,.2),eye_ink,1.0)
			else:
				_face_ellipse(p+eye,Vector2(1.45,1.8),eye_ink)
				_face_ellipse(p+eye+Vector2(.25,-.7),Vector2(.35,.40),"f5efd8")
			if blocked:_face_line(p+eye+Vector2(-1.5,-3),p+eye+Vector2(1.3,-2.3),eye_ink,.8)
		var nose=p+Vector2(0 if front else (12 if profile else 7.4),-34.5)
		_face_ellipse(nose,Vector2(1.7,1.2),"b28c7d" if species==0 else "6f654b")
		_face_line(nose+Vector2(0,.9),nose+Vector2(-.15,2.0),"948369",.75)
		_face_line(nose+Vector2(-1.8,2),nose+Vector2(-.4,2.8),"948369",.72)
		_face_line(nose+Vector2(-.4,2.8),nose+Vector2(1.3,2.2),"948369",.72)
		_face_ellipse(p+Vector2(-5 if front else 1,-33),Vector2(2.0,1.2),Color(.82,.49,.40,.16))
		if front:_face_ellipse(p+Vector2(6,-33),Vector2(2,1.2),Color(.82,.49,.40,.16))
	if chef_hat:
		rounded_poly([p+Vector2(-10,-49),p+Vector2(10,-49),p+Vector2(10,-54),p+Vector2(-10,-54)],1.5,"fff5dd")
		for x in [-7,0,7]:ellipse(p+Vector2(x,-56),Vector2(5.3,4.8),"fff5dd")

func _arm_pose(target:Vector2,shoulder:Vector2=Vector2(7,-28),_side=1) -> Dictionary:
	var limb=CompactPose.limb(target,shoulder,ARM_LENGTH)
	return {"shoulder":limb.pivot,"hand":limb.tip,"length":ARM_LENGTH,"segments":1,"target_error":limb.target_error}

func _table_guest_direction(table_id:int) -> Vector2:
	if not is_instance_valid(game):return Vector2.DOWN
	var table=game.model.get_item(table_id)
	if table.is_empty():return Vector2.DOWN
	var center=Vector2(table.x+.5,table.z+.5)
	for guest in game.model.customers:
		if int(guest.table_id)==table_id:
			var chair=game.model.get_item(int(guest.chair_id))
			if not chair.is_empty():return (Vector2(chair.x+.5,chair.z+.5)-center).normalized()
	if table_dining_directions.has(table_id):return table_dining_directions[table_id]
	for chair in game.model.items:
		if str(chair.kind) in ["chair","bench"] and abs(int(chair.x)-int(table.x))+abs(int(chair.z)-int(table.z))==1:
			return Vector2(int(chair.x)-int(table.x),int(chair.z)-int(table.z))
	return Vector2.DOWN
func _table_surface_point(table_id:int,drink=false) -> Vector2:
	var layout=DiningPlacement.layout(_table_guest_direction(table_id))
	return layout.cup if drink else layout.plate
func _table_vase_point(table_id:int) -> Vector2:
	return DiningPlacement.layout(_table_guest_direction(table_id)).vase

func _character_bubble_anchor(id:int,staff:bool,moving:bool,pose:Dictionary,role="chef") -> Vector2:
	var bounds=DirectionalCharacter.head_bounds(posmod(id,3),false,staff and role=="chef")
	var body=DirectionalCharacter.body_offset(pose,moving,float(pose.get("phase",0)))
	# The oval sits beside the upper-right ear/hat, not directly overhead.
	# Mirror only the owner's body offset; this UI placement stays screen-right.
	return Vector2((body.x+bounds.get_center().x)*float(pose.get("mirror",1.0))+32.0,body.y+bounds.position.y-7.0)

func bubble(p: Vector2,words: String):
	ellipse(p,Vector2(13,10),"fff6d9")
	# The leftward tail returns to the owner's upper-right head edge, with
	# clear space beside the ear/hat rather than moving the old tail wholesale.
	poly([p+Vector2(-11,4),p+Vector2(-7,8),p+Vector2(-16,12)],"fff6d9")
	var mark=bubble_symbol_geometry(words)
	if mark.is_empty():
		draw_string(ThemeDB.fallback_font,p+Vector2(-6,3),words,HORIZONTAL_ALIGNMENT_LEFT,-1,13,col("829270"))
		return
	# Optically centered vector marks replace the old left-aligned font glyphs.
	# Submit in final raster coordinates so AA remains one pixel at any zoom.
	var raster=_stroke_raster_scale>0.0
	if raster:draw_set_transform_matrix(_stroke_from_raster)
	var scale=_stroke_raster_scale if raster else 1.0
	var tint=col(str(mark.get("color","829270")))
	if mark.has("face_radius"):
		var center=_stroke_to_raster*p if raster else p
		draw_circle(center,float(mark.face_radius)*scale,col(str(mark.face_fill)),true,-1.0,true)
	for point in mark.dots:
		var center=_stroke_to_raster*(p+point) if raster else p+point
		draw_circle(center,float(mark.radius)*scale,tint,true,-1.0,true)
	if mark.has("stem"):
		var start=_stroke_to_raster*(p+mark.stem[0]) if raster else p+mark.stem[0]
		var finish=_stroke_to_raster*(p+mark.stem[1]) if raster else p+mark.stem[1]
		draw_line(start,finish,tint,float(mark.width)*scale,true)
	for stroke in mark.get("strokes",[]):
		var points=PackedVector2Array()
		for point in stroke:points.append(_stroke_to_raster*(p+point) if raster else p+point)
		var width=float(mark.width)*scale
		draw_polyline(points,tint,width,true)
		for endpoint in [points[0],points[-1]]:draw_circle(endpoint,width*.5,tint,true,-1.0,true)
	if raster:draw_set_transform_matrix(_art_transform)

static func bubble_symbol_geometry(words:String)->Dictionary:
	if words=="…":return {"dots":[Vector2(-3.5,0),Vector2(0,0),Vector2(3.5,0)],"radius":.85}
	if words=="!":return {"dots":[Vector2(0,4.0)],"radius":.8,"stem":[Vector2(0,-4.0),Vector2(0,1.5)],"width":1.5}
	if words=="angry":return {"face_radius":7.0,"face_fill":"e6b079","color":"57674d",
		"dots":[Vector2(-2.6,-.45),Vector2(2.6,-.45)],"radius":.8,"width":1.15,
		"strokes":[[Vector2(-4.2,-3.0),Vector2(-1.1,-1.6)],[Vector2(1.1,-1.6),Vector2(4.2,-3.0)],
			[Vector2(-2.8,3.65),Vector2(-2.2,3.15),Vector2(-1.5,2.8),Vector2(-.75,2.57),Vector2(0,2.5),Vector2(.75,2.57),Vector2(1.5,2.8),Vector2(2.2,3.15),Vector2(2.8,3.65)]]}
	return {}
func _meal(table_id: int):
	if game==null: return
	for guest in game.model.customers:
		if int(guest.table_id)!=table_id: continue
		var record=game.service_guests.get(int(guest.id),{}) if "service_guests" in game else {}
		var dirty=str(guest.phase) in ["checkout_wait","checkout_walk","paying","leaving","dirty","cleaning"]
		var plate=str(record.get("plate_owner","table" if str(guest.phase) in ["eating","checkout_wait","checkout_walk","paying","leaving","dirty","cleaning"] else "kitchen"))=="table"
		var drink=str(record.get("drink_owner",""))=="table" and not bool(record.get("dishes_collected",false)) and not _drink_in_hand(guest,record)
		var meal_at=_table_surface_point(table_id)
		var cup_at=_table_surface_point(table_id,true)
		if plate:
			var remaining=DirectionalCharacter.DiningPose.remaining(float(guest.elapsed)/maxf(.01,float(guest.duration))) if str(guest.phase)=="eating" else 1.0
			_plate(meal_at,remaining,dirty)
		if drink:_cup(cup_at)

func _doorway():
	# Solid doorway assembly, with back-facing soffit/near reveal culled.
	# The threshold is in the ground pass; only the far jamb reveal is visible.
	# Its outside edge uses the same -0.26 plane as both adjoining wall caps.
	var a=DOOR_START; var b=DOOR_END; var h=DOOR_HEIGHT; var n=-.26
	poly([iso(0,a),iso(n,a),iso(n,a,h),iso(0,a,h)],"dce2c9")
	poly([iso(0,a,WALL_HEIGHT),iso(0,b,WALL_HEIGHT),iso(0,b,h),iso(0,a,h)],"cfdbc2")
	poly([iso(0,a,WALL_HEIGHT),iso(0,b,WALL_HEIGHT),iso(n,b,WALL_HEIGHT),iso(n,a,WALL_HEIGHT)],"fff1d0")
	# Slim solid sage casing on the room face, not disconnected green strokes.
	var w=.085
	poly([iso(.01,a-w),iso(.01,a+w),iso(.01,a+w,h+4),iso(.01,a-w,h+4)],"597d60")
	poly([iso(.01,b-w),iso(.01,b+w),iso(.01,b+w,h+4),iso(.01,b-w,h+4)],"597d60")
	poly([iso(.01,a-w,h+4),iso(.01,b+w,h+4),iso(.01,b+w,h-1),iso(.01,a-w,h-1)],"597d60")
	# Threshold joins the pavement and indoor floor without another paving lane.

func _chair_rotation(entry) -> int:
	# Occupied chairs face the table they actually serve; other placed chairs
	# retain their independently editable four-way orientation.
	for guest in game.model.customers:
		if int(guest.chair_id)==int(entry.id) and (bool(guest.get("seated",false)) or float(seat_blends.get(int(guest.id),0))>.01):
			var table=game.model.get_item(int(guest.table_id))
			var d=Vector2i(int(table.x-entry.x),int(table.z-entry.z))
			if d.y<0: return 0
			if d.x<0: return 3
			if d.y>0: return 2
			return 1
	return int(entry.rot)%4

func _chair_point(p: Vector2,x: float,z: float,h: float,r: int) -> Vector2:
	var v=Vector2(x,z).rotated(r*PI/2)
	return p+Vector2((v.x-v.y)*25,(v.x+v.y)*12.5-h)

func _chair(p: Vector2,r: int,back_only: bool,style:String="basic"):
	if dining_art.chair(self,p,r,back_only,style):return
	if furniture_art.try_draw_static(self,"chair_back" if back_only else "chair_seat",p,r):return
	if back_only:
		for x in [-.30,.30]:
			line(_chair_point(p,x,.28,17,r),_chair_point(p,x,.28,34,r),"ad8c55",2.6)
		var a=_chair_point(p,-.34,.28,33,r);var b=_chair_point(p,.34,.28,33,r)
		rounded_poly([a,b,b+Vector2(0,5),a+Vector2(0,5)],1.6,"d4b882")
		line(a,b,"b89964",1)
		return
	ellipse(p+Vector2(0,1),Vector2(14,6),Color(.45,.39,.23,.06))
	# Ground contacts belong to this chair-local transform, so a visual dining
	# dock carries its feet and shadows together without changing the model cell.
	for d in [Vector2(-.28,-.28),Vector2(.28,-.28),Vector2(-.28,.28),Vector2(.28,.28)]:
		ellipse(_chair_point(p,d.x*1.1,d.y*1.1,0,r),Vector2(2.2,1.1),Color(.45,.39,.23,.14))
	for d in [Vector2(-.28,-.28),Vector2(.28,-.28),Vector2(-.28,.28),Vector2(.28,.28)]:
		line(_chair_point(p,d.x*1.1,d.y*1.1,0,r),_chair_point(p,d.x,d.y,17,r),"ad8c55",2.6)
	var points=[]
	for d in [Vector2(-.35,-.35),Vector2(.35,-.35),Vector2(.35,.35),Vector2(-.35,.35)]: points.append(_chair_point(p,d.x,d.y,18,r))
	var lower=[]
	for q in points: lower.append(q+Vector2(0,2.5))
	rounded_poly(lower,2,"b79965")
	rounded_poly(points,2.5,"d7bd89")

func hit_item(screen: Vector2) -> int:
	if objects_hidden():return -1
	var ordered=game.model.items.duplicate()
	ordered.sort_custom(func(a,b):
		if (a.kind=="rug")!=(b.kind=="rug"): return b.kind=="rug"
		return (a.x+a.z)>(b.x+b.z) if a.x+a.z!=b.x+b.z else a.id>b.id)
	var scale=ui_scale*zoom*(1.55 if game.wall_detail else 1.0)
	for d in ordered:
		var local=(screen-iso(d.x+.5,d.z+.5))/scale
		var height={"table":52,"chair":47,"plant":74,"lamp":86,"bookshelf":80,"divider":64,"beverage":62,"stove":48,"sink":55,"counter":43,"bench":49,"rug":19,"bin":33}.get(d.kind,45)
		var width={"table":30,"chair":19,"plant":23,"lamp":19,"bookshelf":24,"rug":35,"bin":19}.get(d.kind,31)
		if Rect2(Vector2(-width,-height),Vector2(width*2,height+9)).has_point(local): return int(d.id)
	return -1

func _door_front():
	var b=DOOR_END;var h=DOOR_HEIGHT;var w=.085
	poly([iso(.01,b-w),iso(.01,b+w),iso(.01,b+w,h+4),iso(.01,b-w,h+4)],"597d60")

func _cup(bottom:Vector2,filled=true):
	# One small clear tumbler, amber juice, planted base and quiet highlight.
	ellipse(bottom+Vector2(.5,.5),Vector2(4.2,1.6),Color(.34,.39,.25,.14))
	rounded_poly([bottom+Vector2(-3.7,-9),bottom+Vector2(3.7,-9),bottom+Vector2(2.8,0),bottom+Vector2(-2.8,0)],1,"e1e9d1")
	var level=clampf(float(filled),0,1)
	if level>.01:
		var surface=-.8-5.8*level;var wide=2.3+.7*level
		rounded_poly([bottom+Vector2(-wide,surface),bottom+Vector2(wide,surface),bottom+Vector2(2.3,-.8),bottom+Vector2(-2.3,-.8)],.7,"e7bd68")
		ellipse(bottom+Vector2(0,surface),Vector2(wide,1.1),"f3ce80")
	art_polyline(PackedVector2Array([bottom+Vector2(-3.7,-8.5),bottom+Vector2(-2.8,0),bottom+Vector2(2.8,0),bottom+Vector2(3.7,-8.5)]),col("a8b7a1"),.7)
	outlined_ellipse(bottom+Vector2(0,-9),Vector2(3.7,1.4),"d4ddc6","f4efd7",.8)
	line(bottom+Vector2(-2.3,-7.4),bottom+Vector2(-1.8,-2.3),Color(1,1,.92,.6),.8)

func _action_prop(p: Vector2,hand_offset: Vector2,action: String,t: float,payload: String,tool: String,work_hand=Vector2.ZERO,gesture_hand=Vector2.ZERO,tool_floor=Vector2(22,2)):
	var hand=p+hand_offset
	if payload=="plate":_plate(hand+Vector2(4,-2),1.0,false)
	elif payload=="drink":_cup(hand+Vector2(2,-2))
	elif payload=="dishes":
		_plate(hand+Vector2(4,0),0.0,true)
		rounded_poly([hand+Vector2(0,-7),hand+Vector2(5,-7),hand+Vector2(4,-1),hand+Vector2(1,-1)],1,"eee2bf")
	elif payload=="trash" and action!="sweeping":_dustpan(p+gesture_hand+Vector2(3,10),p+gesture_hand,Vector2(1,.45).normalized(),true)
	# Working utensils follow the compact gesture; held dishes follow prop path.
	hand=p+gesture_hand if gesture_hand!=Vector2.ZERO else hand
	if tool=="cloth":
		var cloth=p+work_hand
		rounded_poly([cloth+Vector2(-4,0),cloth+Vector2(3,-3),cloth+Vector2(7,1),cloth+Vector2(0,4)],1.5,"c2d1b2")
	elif action=="washing":
		pass # Sink-anchored water/foam and solved hand contact own this action.
	elif action=="cooking":
		line(hand,hand+Vector2(2,5),"a78c58",1.7)
		ellipse(hand+Vector2(2,5),Vector2(2.4,1.3),"b69b64")
	elif action=="taking_order":
		rounded_poly([p+Vector2(7,-31),p+Vector2(16,-30),p+Vector2(16,-19),p+Vector2(7,-20)],1,"eee0bc")
		line(p+Vector2(10,-28),p+Vector2(14,-27),"a9a380",.7)
		line(p+Vector2(8,-24),p+Vector2(13,-31),"8c8058",1)
	elif action in ["sweeping","mopping"]:
		var grip=p+work_hand
		var tip=p+tool_floor+Vector2(sin(t*TAU*2)*2.0,0)
		line(grip,tip,"ac9764",1.9)
		if action=="mopping":
			ellipse(tip,Vector2(6,2.3),"aac0b5")
			for i in range(4):line(tip+Vector2(-4+i*2,-1),tip+Vector2(-5+i*2,3),"d1dccb",1.5)
		else:rounded_poly([tip+Vector2(-5,-2),tip+Vector2(4,-2),tip+Vector2(6,3),tip+Vector2(-7,3)],1,"c9b57a")
	elif action=="preparing_food":
		line(hand,hand+Vector2(4,6),"d5cfad",2)


func _dustpan(at:Vector2,grip:Vector2,axis:Vector2,loaded:bool):
	# A tall handle and shallow scooped tray are distinct from a plate or a bag.
	var across=Vector2(-axis.y,axis.x)*Vector2(1,.42)
	var mouth=at-axis*3.5;var back=at+axis*3.5
	line(grip,back+Vector2(0,-2),"809c8e",1.8)
	poly([mouth-across*6,mouth+across*6,back+across*4+Vector2(0,-2),back-across*4+Vector2(0,-2)],"78958a")
	poly([mouth-across*5,mouth+across*5,back+across*3+Vector2(0,-1.2),back-across*3+Vector2(0,-1.2)],"a7beb0")
	line(mouth-across*6,mouth+across*6,"d2d9bf",1.0)
	line(back-across*4+Vector2(0,-2),back+across*4+Vector2(0,-2),"668277",1.3)
	if loaded:
		for offset in [Vector2(-2,0),Vector2(1,-.5),Vector2(3,.5)]:ellipse(at+offset+Vector2(0,-1),Vector2(1.45,.95),"aa895d")

func _draw_floor_tools(at:Vector2,pose:Dictionary,action:String,payload:String):
	var axis:Vector2=pose.axis;var across=Vector2(-axis.y,axis.x)*Vector2(1,.42)
	var brush:Vector2=at+pose.brush
	if action=="sweeping":_dustpan(at+pose.pan,at+pose.far_hand,axis,payload=="trash")
	line(at+pose.shaft_top,brush,"aa9161",1.9)
	if action=="mopping":
		ellipse(brush,Vector2(6,2.3),"aac0b5")
		for i in range(4):line(brush+across*(-4+i*2)-axis,brush+across*(-5+i*2)+axis*3,"d1dccb",1.5)
	else:
		# Bristles spread across the floor, perpendicular to the sweeping stroke.
		var heel=brush-axis*1.5;var edge=brush+axis*2.5
		poly([heel-across*4.5,heel+across*4.5,edge+across*6,edge-across*6],"c4aa6b")
		line(heel-across*4.5,heel+across*4.5,"947957",2.0)
		for i in range(6):line(heel+across*(-3.75+i*1.5),edge+across*(-5+i*2),"ddc68d",.7)


func _sink_dishes(sink_id: int):
	var sink=game.model.get_item(sink_id)
	var count=game.dishwashing.count_at(sink_id) if "dishwashing" in game else 0
	if not "dishwashing" in game:
		for record in game.service_guests.values():
			if record.plate_owner=="sink" and int(record.plate_target_id)==sink_id:count+=1
	if count<=0:return
	var rotation=int(sink.get("rot",0));var geometry=FurnitureArt.KitchenGeometry
	var aperture=geometry.sink_outline(geometry.SINK_BASIN_INNER,geometry.SINK_OPENING_HEIGHT,rotation)
	var at=geometry.sink_plate_anchor(rotation)
	var wash=SinkWashArt.state(game,sink_id)
	var stored=count-1 if not wash.is_empty() else count
	for index in range(stored):
		_plate_clip=aperture if geometry.height(geometry.SINK_STACK_HEIGHT)+index*2.2<geometry.height(geometry.SINK_OPENING_HEIGHT) else PackedVector2Array()
		_plate(at+Vector2(0,-index*2.2),0.0,true)
	_plate_clip=PackedVector2Array()
	if not wash.is_empty():
		var action_geometry=SinkWashArt.geometry(rotation,float(wash.seconds),count)
		_plate_transform=action_geometry.transform
		_plate_clip=aperture if float(action_geometry.height)<geometry.height(geometry.SINK_OPENING_HEIGHT) else PackedVector2Array()
		_plate(Vector2.ZERO,-1.0,false)
		var dirt=float(action_geometry.dirt)
		if dirt>.001:
			for q in [Vector2(-4,1),Vector2(5,1),Vector2(-1,-2)]:ellipse(q,Vector2(.9,.6),Color(.70,.64,.46,dirt))
		_plate_transform=Transform2D.IDENTITY;_plate_clip=PackedVector2Array()
		SinkWashArt.draw_water(self,wash,action_geometry)
		SinkWashArt.draw_foam(self,action_geometry)
	furniture_art.draw_sink_foreground(self,Vector2.ZERO,rotation)

func _drink_in_hand(_guest,_record) -> bool:
	# Dining uses a tiny nod/gesture. The cup stays on its tabletop anchor.
	return false

func _station_payloads(item_id: int,kind: String,rotation: int=0):
	if game==null or ("editing" in game and game.editing):return
	# Only the authoritative output owner paints a ready plate. Pickup moves
	# ownership to the waiter at contact, so the dish is never drawn twice.
	for record in game.service_guests.values()+game.floor_tasks.messes.values():
		if kind=="stove" and str(record.get("plate_owner",""))=="station" and int(record.get("plate_target_id",-1))==item_id:
			_plate(game.ChefPickup.plate_anchor(rotation),1.0,false)
		if kind=="counter" and str(record.get("plate_owner",""))=="counter" and int(record.get("plate_target_id",-1))==item_id:
			_plate(FurnitureArt.KitchenGeometry.surface(Vector2.ZERO,31),1.0,false)
		if kind=="beverage" and str(record.get("drink_owner","")) in ["beverage","station"] and int(record.get("drink_station_id",-1))==item_id:
			var surface=_drink_surface_point(rotation)
			var filled=1.0 if str(record.drink_owner)=="station" else 0.0
			for staff in game.staff_states:
				if int(staff.get("art_guest_id",-1))==int(record.guest.id) and str(staff.art_action)=="preparing_drink":filled=clampf(float(staff.art_phase),0,1)
			_cup(surface,filled)

func _stove_food_remaining(item_id:int) -> float:
	if not is_instance_valid(game) or game.editing:return 0.0
	for staff in game.staff_states:
		if int(staff.get("art_target_id",-1))!=item_id:continue
		var action=str(staff.get("art_action",""))
		if action not in ["cooking","plating"]:continue
		var record=game.service_guests.get(int(staff.get("art_guest_id",-1)),{})
		if int(record.get("meal_station_id",-1))!=item_id or str(record.get("plate_owner",""))!="kitchen":continue
		# Hold the finished ingredients until the authoritative ready-meal handoff.
		return 1.0
	return 0.0

func _stove_heat_state(item_id:int)->Dictionary:
	if not is_instance_valid(game) or game.editing:return {}
	for staff in game.staff_states:
		if str(staff.get("job_kind",""))!="cook" or int(staff.get("job_step",-1))!=1:continue
		if int(staff.get("station_id",-1))!=item_id or str(staff.get("blocked_reason",""))!="":continue
		var record=game.service_guests.get(int(staff.get("job_guest_id",-1)),{})
		if int(record.get("meal_station_id",-1))!=item_id or str(record.get("plate_owner",""))!="kitchen":continue
		var elapsed=float(staff.get("job_elapsed",0.0))
		var station=game.model.get_item(item_id)
		var remaining=game.Model.cooking_seconds(game.Model.stove_speed_multiplier(station))-elapsed
		return {"elapsed":elapsed,"remaining":remaining,"strength":0.0 if _cooking_reduced_motion() else cooking_motion_strength}
	return {}

func _stove_heat(item_id:int,rotation:int):
	var heat=_stove_heat_state(item_id)
	if not heat.is_empty():furniture_art.draw_stove_heat(self,Vector2.ZERO,rotation,0.0 if _cooking_reduced_motion() else heat.elapsed)

func _cooking_food_owned_by_pose(item_id:int)->bool:
	if not is_instance_valid(game) or game.editing:return false
	for staff in game.staff_states:
		if str(staff.get("art_action",""))!="cooking" or int(staff.get("art_target_id",-1))!=item_id:continue
		var record=game.service_guests.get(int(staff.get("art_guest_id",-1)),{})
		if int(record.get("meal_station_id",-1))==item_id and str(record.get("plate_owner",""))=="kitchen":return true
	return false

func _stove_food(_item_id:int,_rotation:int):
	# Cooking stays covered. Only authoritative finished plates show food.
	pass

func _stove_vessel_motion(item_id:int)->Dictionary:
	var state=_stove_heat_state(item_id)
	if state.is_empty():return {"pot":Vector2.ZERO,"lid":Vector2.ZERO}
	return FurnitureArt.CookingFood.vessel(state.elapsed,state.remaining,state.strength)

func _drink_surface_point(rotation:int) -> Vector2:
	# Cup bottom is a local point on the worktop, shared with the reaching hand.
	return FurnitureArt.KitchenGeometry.surface(Vector2(.17,.25),30,rotation)

func _stove_plate_point(rotation:int) -> Vector2:
	return game.ChefPickup.plate_anchor(rotation)

func _stove_pan_point(rotation:int) -> Vector2:
	# The blade and live food share one exact surface, in every rotation.
	return FurnitureArt.stove_food_surface(rotation)

func _plate(at:Vector2,remaining=1.0,dirty=false):
	# Readable cafe lunch: rice, a grilled cutlet, greens and carrot coins.
	# The ceramic remains after the ingredients are eaten, then is collected.
	ellipse(at+Vector2(.5,1.2),Vector2(14.0,6.4),Color(.48,.42,.28,.14))
	ellipse(at+Vector2(0,.8),Vector2(14.0,6.4),"d4c7a7")
	outlined_ellipse(at,Vector2(14.0,6.4),"faf0d8","e3d7b8",.7)
	ellipse(at+Vector2(0,-.15),Vector2(11.2,4.7),"eee3c7")
	var eaten=1.0 if dirty else (1.0-clampf(remaining,0,1) if remaining>=0 else 0.0)
	if eaten>0.0:
		ellipse(at+Vector2(2,-.6),Vector2(3.5,1.1)*lerpf(.45,1.0,eaten),"cbbb93")
		var crumbs=[Vector2(-4,1),Vector2(5,1),Vector2(-1,-2)]
		for i in range(ceili(eaten*3.0)):ellipse(at+crumbs[i],Vector2(.9,.6),"b4a376")
	if not dirty and remaining>0:
		var rice_scale=clampf(remaining*1.3,.25,1)
		ellipse(at+Vector2(-4,-1.6),Vector2(5.3,3.1)*rice_scale,"fff5da")
		for q in [Vector2(-6,-2),Vector2(-3,-3),Vector2(-2,-1)]:
			if remaining>.48:line(at+q,at+q+Vector2(.8,.2),"ded9b5",.65)
		if remaining>.25:
			ellipse(at+Vector2(3,-1.5),Vector2(5.5,2.8),"aa7548")
			ellipse(at+Vector2(3,-2),Vector2(5.0,2.4),"d5a362")
			for x in [0.5,3,5.5]:line(at+Vector2(x-1,-3.2),at+Vector2(x+1,-.8),"b6834e",.85)
		if remaining>.50:
			for q in [Vector2(-2,-4),Vector2(0,-4.6),Vector2(-.6,-3.6)]:ellipse(at+q,Vector2(2.3,1.3),"88a068")
		if remaining>.75:
			for q in [Vector2(7,1),Vector2(5.2,2)]:outlined_ellipse(at+q,Vector2(1.8,1.1),"e1a561","c88a50",.5)

func _bin(p:Vector2,rotation:int,id:int):
	if not _rigid_part("bin/%d"%posmod(rotation,4),p):_bin_body_legacy(p,rotation)
	if is_instance_valid(game) and not game.editing:
		for record in game.service_guests.values()+game.floor_tasks.messes.values():
			if str(record.get("trash_owner",""))=="bin" and int(record.get("trash_target_id",-1))==id:
				_trash(p+Vector2(0,-25))

func _bin_body_legacy(p:Vector2,_rotation:int):
	# Open rim, no pedal or directional front. All rotations share this body.
	ellipse(p+Vector2(0,2),Vector2(18,7),Color(.36,.43,.27,.13))
	rounded_poly([p+Vector2(-15,-24),p+Vector2(15,-24),p+Vector2(12,0),p+Vector2(-12,0)],3,"8da597")
	ellipse(p,Vector2(12,5),"789384")
	line(p+Vector2(-9,-18),p+Vector2(-8,-3),"b0bd9f",1.2)
	line(p+Vector2(8,-18),p+Vector2(7,-3),"789080",1.2)
	outlined_ellipse(p+Vector2(0,-24),Vector2(16,7),"adc0a4","749180",1.4)
	ellipse(p+Vector2(0,-25),Vector2(11.5,4.6),"597b69")

func _trash(at:Vector2):
	# A small paper bundle with a yellow peel remains identifiable in transit.
	rounded_poly([at+Vector2(-5,0),at+Vector2(-4,-5),at+Vector2(2,-6),at+Vector2(6,-1),at+Vector2(3,3)],1.8,"c0b184")
	line(at+Vector2(-2,-3),at+Vector2(1,1),"e1d7b5",1.4)
	_banana_peel(at+Vector2(2,-4),.65)

func _banana_peel(at:Vector2,scale=1.0):
	ellipse(at+Vector2(0,2)*scale,Vector2(7.5,2.2)*scale,Color(.40,.31,.16,.13))
	poly([at+Vector2(-1.5,-5)*scale,at+Vector2(1,-5)*scale,at+Vector2(2,0)*scale,at+Vector2(7.5,2)*scale,at+Vector2(5.5,4)*scale,at+Vector2(0,1)*scale,at+Vector2(-5.5,4)*scale,at+Vector2(-7.5,2)*scale,at+Vector2(-2,0)*scale],"b99339")
	line(at+Vector2(0,-3.5)*scale,at+Vector2(0,.5)*scale,"f4d878",1.7*scale)
	line(at+Vector2(0,.5)*scale,at+Vector2(5.5,2.6)*scale,"e7c660",1.5*scale)
	line(at+Vector2(-1,.5)*scale,at+Vector2(-5.3,2.6)*scale,"efd174",1.5*scale)

func _dry_crumbs(at:Vector2):
	# Angular, warm crumbs with a light cut face read as dry solid scraps.
	for offset in [Vector2(-4,1),Vector2(2,-1),Vector2(6,2)]:
		var p=at+offset
		poly([p+Vector2(-2,0),p+Vector2(-.7,-1.8),p+Vector2(1.8,-.5),p+Vector2(1.4,1.2),p+Vector2(-.8,1.5)],"a37d48")
		line(p+Vector2(-.7,-1.1),p+Vector2(.9,-.4),"d7b778",.85)

func _wet_spill(at:Vector2,remaining:float):
	if remaining<=.001:return
	# A cool, connected low puddle with a reflection, never a crumb cluster.
	var points=[]
	for point in [Vector2(-12,0),Vector2(-9,-3),Vector2(-4,-3.5),Vector2(0,-5),Vector2(6,-4),Vector2(8,-2),Vector2(13,-1),Vector2(14,1.5),Vector2(8,3.5),Vector2(2,3),Vector2(-4,4.5),Vector2(-10,2.5)]:points.append(at+point*remaining)
	rounded_poly(points,2.0*remaining,Color(.40,.59,.59,.60))
	line(at+Vector2(-7,-1)*remaining,at+Vector2(-2,-2)*remaining,Color(.88,.94,.88,.85),1.1*remaining)
	ellipse(at+Vector2(8,1)*remaining,Vector2(1.8,.65)*remaining,Color(.84,.92,.86,.68))

func _floor_mess_active(record:Dictionary) -> bool:
	var phase=str(record.get("guest",{}).get("phase",""))
	return bool(record.get("floor_dirty",phase in ["checkout_wait","checkout_walk","paying","leaving","dirty","cleaning"])) and not bool(record.get("floor_cleaned",false))

func _draw_floor_mess(record:Dictionary):
	if not _floor_mess_active(record):return
	FloorMessArt.draw(self,record)

func hit_wall_host(screen:Vector2)->Dictionary:
	if objects_hidden():return {}
	update_projection()
	var hosts=game.model.selectable_wall_hosts()
	hosts.sort_custom(func(a,b):return float(a.a.x+a.a.y+a.b.x+a.b.y)>float(b.a.x+b.a.y+b.b.x+b.b.y))
	for host in hosts:
		if OpeningArt.hit_host(self,screen,host):return host
	return {}
func hit_wall_attachment(screen:Vector2)->int:
	if objects_hidden():return -1
	update_projection()
	var openings=game.model.wall_openings()
	openings.sort_custom(func(a,b):return float(a.a.x+a.a.y+a.b.x+a.b.y)>float(b.a.x+b.a.y+b.b.x+b.b.y))
	for opening in openings:
		if OpeningArt.hit_opening(self,screen,opening):return int(opening.id)
	return -1
