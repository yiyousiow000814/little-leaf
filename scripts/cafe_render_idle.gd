extends RefCounted
## Retain a settled world while simulation is explicitly frozen. Live play,
## intro, atlas warm-up and active tweens always draw. This does not pause nodes.
## Snapshots compare values, not hashes or aliased mutable model dictionaries.
var previous:Array=[]
var retained=false
var suppressed_frames=0
func invalidate():
	retained=false;previous=[]
func needs_redraw(art)->bool:
	var game=art.game
	if not supports_controller(game):
		invalidate();return true
	if not (game.paused or game.editing) or (game.cafe_intro!=null and game.cafe_intro.active):
		invalidate();return true
	if not art.get_tree().get_processed_tweens().is_empty():
		invalidate();return true
	for atlas in [art.furniture_art.static_atlas,art.head_atlas,art.moving_atlas]:
		if atlas.state in ["cold","warming"]:invalidate();return true
	art.update_projection()
	var next=snapshot(art)
	if retained and next==previous:
		suppressed_frames+=1;return false
	previous=next.duplicate(true);retained=true
	return true

# Historical fixture controllers share the current artist, but not the complete
# snapshot contract (for example, pre-dishwashing games have no dishwashing).
# Fail open for every unknown shape rather than silently retain a partial state.
# Inspect ancestry without preloading main.gd, which itself loads this artist.
static func supports_controller(game)->bool:
	if not is_instance_valid(game):return false
	var script=game.get_script()
	var current=false
	while script!=null:
		if script.resource_path=="res://scripts/main.gd":current=true;break
		script=script.get_base_script()
	if not current:return false
	for name in ["model","floor_tasks","dishwashing","interaction","build_tools","compact_ui"]:
		if not is_instance_valid(game.get(name)):return false
	return true

static func values(object,names:Array)->Array:
	var result=[]
	if object==null:return result
	for name in names:result.append(object.get(name))
	return result
static func snapshot(art)->Array:
	var g=art.game;var m=g.model
	return [
		values(g,["paused","editing","save_recovery_blocked","selected_id","speed","wall_detail","animation_time"]),
		values(m,["revision","items","customers","outside_queue","parking_owned","parking_paid_cost","parking_visits","dining_sets","built_walls","wall_attachments","floor_finishes","shell_material","shell_products","shell_segment_products","owned_parcels","expanded","width","depth","coins","operating_open"]),
		g.staff_states,g.service_guests,g.floor_tasks.messes,g.dishwashing.dishes,
		values(g.interaction,["drag_active","drag_item_id","drag_kind","drag_rotation","drag_cell","drag_valid","preview_active"]),
		values(g.build_tools,["mode","preview","preview_shell","preview_valid","preview_warning","selected_key","replacing","floor_material","floor_preview","opening_source_id","wall_source_key","opening_preview","_render_attachments","_render_preview_active"]),
		values(g.compact_ui,["selected_shell","selected_wall","viewport_too_small"]),
		values(g.compact_ui.shop_ui,["build_page","hide_objects"]),
		art.get_viewport_rect(),art.get_global_transform_with_canvas(),art.origin,art.tile,art.zoom,art.pan_offset,art.ui_scale,
		art.camera_safe_rect(),art.get_viewport().get_mouse_position(),art.get_viewport().gui_get_hovered_control(),
		g.interaction._over_ui(art.get_viewport().get_mouse_position()) if g.interaction!=null else false,
		art.seat_blends,art.stance_offsets,art.carry_hand_offsets,art.character_facings,art.meal_chair_offsets,art.table_dining_directions,art.motion._actors,
		art.street_pedestrians.walkers,art.street_pedestrians.departures,art.street_pedestrians.motion._actors,
		art.bus_stop_pedestrians.actors,art.bus_stop_pedestrians.motion._actors,art.road_traffic.cars,
		art.use_background_cache,art.use_screen_culling,art.use_batched_ground,art.use_grass_mesh,art.use_cached_moving_art,art.use_cached_heads,
		art.furniture_art.cache_enabled,art.furniture_art.expanded_parts_enabled,
		art.furniture_art.static_atlas.state,art.head_atlas.state,art.moving_atlas.state,
		art.ground_art.use_stroke_mesh,art.opacity,
		art.material,art.use_parent_material,art.self_modulate,art.clip_children,art.light_mask,art.visibility_layer,art.y_sort_enabled
	]
