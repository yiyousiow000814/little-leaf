extends RefCounted
const EditPlan=preload("res://scripts/cafe_edit_plan.gd")
const FloorAvailability=preload("res://scripts/cafe_floor_availability.gd")
var edit_plan=EditPlan.new()
var floor_availability=FloorAvailability.new()
var placement_receipt:Dictionary={}
const Money=preload("res://scripts/cafe_money.gd")
## Transactional world input. Furniture positions and coins change only on a
## successful drag release (or new-item placement); previews never mutate
## the model. Call handle_input BEFORE GUI dispatch to retain an active gesture,
## and handle_unhandled_input AFTER GUI dispatch to begin a world gesture.

const DRAG_THRESHOLD = 7.0
const NO_CELL = Vector2i(-100, -100)

var game
var drag_active = false
var drag_item_id = -1
var drag_kind = ""
var drag_rotation = 0
var drag_cell = NO_CELL
var drag_position = Vector2.ZERO
var drag_valid = false
var drag_reason = ""
var drag_warning = ""
var preview_active = false
var pan_offset = Vector2.ZERO
var last_pointer = Vector2.ZERO
var _pointer_device = 0
var _left_down = false
var _middle_down = false
var _gesture = ""
var _press_pointer = Vector2.ZERO
var _previous_pointer = Vector2.ZERO
var _press_item_id = -1
var _press_parcel_id = ""
var _press_selected_id = -1
var _press_kind = ""
var _press_editing = false
var _grab_offset = Vector2.ZERO
var _last_valid_cell = NO_CELL

func _init(owner_game = null):
	game = owner_game
	if game != null and is_instance_valid(game.illustration):
		pan_offset = game.illustration.pan_offset

func handle_input(event: InputEvent) -> bool:
	if game == null: return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel()
			if is_instance_valid(game.settings): game.settings.hide()
			return true
		if event.keycode == KEY_R and game.editing:
			rotate_selection()
			return true
	if event is InputEventMouse and _left_down and event.device != _pointer_device:
		# A physical mouse and emulated touch cannot finish each other's drag.
		return true
	if event is InputEventMouseButton:
		last_pointer = event.position
		if event.canceled:
			on_focus_lost()
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel()
			return true
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed: _clear_gesture()
			_middle_down = event.pressed
			_previous_pointer = event.position
			return true
		if event.button_index == MOUSE_BUTTON_LEFT and _left_down:
			# Retain capture even if a duplicate press arrives over a GUI button.
			if not event.pressed: _release_left(event.position)
			return true
		if _left_down or _middle_down:
			if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				_zoom_step_at(event.position, 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
				return true
	if event is InputEventMouseMotion:
		last_pointer = event.position
		# A release outside the OS window may not arrive. Its first motion after
		# re-entry has no button bit; cancel rather than committing a stale drag.
		if _left_down and not (event.button_mask & MOUSE_BUTTON_MASK_LEFT): _clear_gesture()
		if _middle_down and not (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE): _middle_down = false
		if _middle_down:
			_pan_by(event.position - _previous_pointer)
			_previous_pointer = event.position
			refresh(event.position)
			return true
		if _left_down:
			_move_left(event.position)
			return true
		refresh(event.position)
	return false

func handle_unhandled_input(event: InputEvent) -> bool:
	if game == null: return false
	if event is InputEventMouseButton:
		last_pointer = event.position
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# ScrollContainer may propagate wheel input at its limits. UI owns it.
			if _over_ui(event.position):return true
			_zoom_step_at(event.position, 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
			return true
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if _left_down or _middle_down: return true
			if event.canceled or not _point_in_view(event.position) or _over_ui(event.position): return true
			_begin_left(event.position, event.device)
			return true
	return false

func refresh(screen: Vector2):
	last_pointer = screen
	_sync_projection()
	if _left_down and (game.editing != _press_editing or str(game.selected_kind) != _press_kind or int(game.selected_id) != _press_selected_id):
		_clear_gesture()
	if not game.editing:
		preview_active = false
		drag_valid = false
		return
	if drag_active:
		drag_rotation = posmod(int(game.rotation_step), 4)
		drag_cell = game._floor_cell(screen + _grab_offset)
		_update_validity(screen)
	elif str(game.selected_kind) != "":
		preview_active = true
		drag_item_id = -1
		drag_kind = str(game.selected_kind)
		drag_rotation = posmod(int(game.rotation_step), 4)
		drag_cell = game._floor_cell(screen)
		_update_validity(screen)
	else:
		preview_active = false
		drag_valid = false
	game.hover_cell = drag_cell if preview_active else game._floor_cell(screen)
	if preview_active and is_instance_valid(game.tool_text):game.tool_text.text=drag_reason

func cancel(clear_selection = true):
	edit_plan.invalidate()
	_clear_gesture()
	_middle_down = false
	preview_active = false
	drag_item_id = -1
	drag_kind = ""
	drag_cell = NO_CELL
	drag_valid = false
	drag_reason = ""
	drag_warning = ""
	if clear_selection: game._cancel_selection()

func on_focus_lost():
	# Keep the tool selected, but restore any lifted furniture without a write.
	_clear_gesture()
	_middle_down = false
	preview_active = false
	drag_valid = false

func rotate_selection():
	if not game.editing: return
	var next = posmod(int(game.rotation_step) + 1, 4)
	if drag_active or str(game.selected_kind) != "":
		game.rotation_step = next
		drag_rotation = next
		refresh(last_pointer)
		return
	if int(game.selected_id) >= 0:
		var selected: Dictionary = game.model.get_item(int(game.selected_id))
		if selected.is_empty(): cancel(); return
		# R on a clicked selection retains the previous immediate rotation
		# behavior, but R while dragging is purely a preview until release.
		var actors=_staff_positions()
		var receipt=edit_plan.prepare(game.model,game.model.logical_kind(int(selected.id)),int(selected.id),next,Vector2i(selected.x,selected.z),actors)
		if edit_plan.commit(game.model,receipt,actors,game._apply_edit_staff_positions):
			game.rotation_step = next
			game._rebuild_furniture()
			game._update_ui()
			game._save()
		else:
			game.rotation_step = game.model.logical_rotation(int(selected.id))
	else:
		game.rotation_step = next

func _begin_left(screen: Vector2, device: int = 0):
	if _left_down: return
	_pointer_device = device
	_sync_projection()
	_left_down = true
	_press_pointer = screen
	_previous_pointer = screen
	_press_editing = bool(game.editing)
	_press_kind = str(game.selected_kind)
	_press_selected_id = int(game.selected_id)
	_press_item_id = -1
	_press_parcel_id = ""
	_grab_offset = Vector2.ZERO
	_gesture = "pending"
	if game.editing and _press_kind == "":
		_press_item_id = game.illustration.hit_item(screen)
		if _press_item_id < 0:
			var cell: Vector2i = game._floor_cell(screen)
			var item: Dictionary = game.model.item_at(cell.x, cell.y)
			if not item.is_empty(): _press_item_id = int(item.id)
	if _press_item_id>=0:_press_item_id=game.model.logical_item_id(_press_item_id)
	if game.editing and _press_kind == "" and _press_selected_id < 0 and _press_item_id < 0:
		_press_parcel_id = _hit_parcel(screen)
	refresh(screen)

func _hit_parcel(screen: Vector2) -> String:
	if not game.editing:return ""
	if game.illustration.has_method("hit_parcel"):
		var hit: String = str(game.illustration.hit_parcel(screen))
		if hit != "": return hit
	var parcel: Dictionary = game.model.parcel_at(game._floor_cell(screen))
	return str(parcel.id) if not parcel.is_empty() and not bool(parcel.owned) and bool(parcel.get("visible",true)) else ""

func _move_left(screen: Vector2):
	# Projection and stale-gesture cancellation must precede threshold/anchor
	# handling. Placement validity is consumed only after those state updates;
	# leave the single full refresh below, plus normal frame/commit validation.
	last_pointer = screen
	_sync_projection()
	if _left_down and (game.editing != _press_editing or str(game.selected_kind) != _press_kind or int(game.selected_id) != _press_selected_id):
		_clear_gesture()
	if not _left_down:
		refresh(screen)
		return
	if _gesture == "pending" and screen.distance_to(_press_pointer) >= DRAG_THRESHOLD:
		if game.editing and (_press_kind != "" or _press_item_id >= 0):
			_start_drag()
		else:
			_gesture = "pan"
			# Include movement accumulated inside the tap threshold.
			_pan_by(screen - _press_pointer)
			_previous_pointer = screen
	if _gesture == "pan":
		_pan_by(screen - _previous_pointer)
		_previous_pointer = screen
	refresh(screen)

func _start_drag():
	_gesture = "drag"
	drag_active = true
	preview_active = true
	drag_item_id = _press_item_id if _press_kind == "" else -1
	drag_kind = _press_kind
	drag_rotation = posmod(int(game.rotation_step), 4)
	_last_valid_cell = NO_CELL
	if drag_item_id >= 0:
		var item: Dictionary = game.model.get_item(drag_item_id)
		if item.is_empty(): _clear_gesture(); return
		drag_kind = game.model.logical_kind(int(item.id))
		# Pick up at the visible hit point, rather than snapping a tall item
		# several cells backward when its upper surface was clicked.
		_grab_offset = game.illustration.iso(float(item.x) + 0.5, float(item.z) + 0.5) - _press_pointer
		_select_item(item)
		drag_rotation = game.model.logical_rotation(int(item.id))
		_press_selected_id = drag_item_id

func _release_left(screen: Vector2):
	refresh(screen)
	if not _left_down: return
	if _gesture == "drag":
		if drag_valid: _commit_preview()
	elif _gesture == "pending" and game.editing and _press_editing and _press_parcel_id != "" and _point_in_view(screen) and not _over_ui(screen):
		if _hit_parcel(screen) == _press_parcel_id and game.has_method("_buy_parcel"):
			game._buy_parcel(_press_parcel_id)
	elif _gesture == "pending" and game.editing and _point_in_view(screen) and not _over_ui(screen):
		if _press_kind != "":
			if drag_valid: _commit_preview()
		elif _press_item_id >= 0:
			_select_item(game.model.get_item(_press_item_id))
	_clear_gesture()
	refresh(screen)

func _select_item(item: Dictionary):
	if item.is_empty(): return
	item=game.model.get_item(game.model.logical_item_id(int(item.id)))
	game.selected_id = int(item.id)
	game.selected_kind = ""
	game.rotation_step = game.model.logical_rotation(int(item.id))
	var kind = str(game.model.logical_kind(int(item.id)))
	var display_name = kind.replace("_", " ").capitalize()
	if game.compact_ui != null: display_name = str(game.compact_ui.SHORT_NAMES.get(kind, display_name))
	if is_instance_valid(game.tool_text):
		game.tool_text.text = "Selected %s · hold and drag to move · R rotates" % display_name
	game._update_ui()

func _update_validity(screen: Vector2):
	drag_position = Vector2(drag_cell.x + 0.5, drag_cell.y + 0.5)
	drag_valid = false
	drag_warning = ""
	drag_reason = "Move onto an open cafe tile"
	if not _point_in_view(screen) or _over_ui(screen):
		drag_reason = "Drop on the cafe floor; furniture stays put outside it"
		return
	if drag_kind == "": return
	if drag_item_id >= 0:
		if game.model.get_item(drag_item_id).is_empty():
			drag_reason = "This furnishing is no longer available"; return
	placement_receipt=edit_plan.prepare(game.model,drag_kind,drag_item_id,drag_rotation,drag_cell,_staff_positions())
	if not placement_receipt.ok:
		drag_reason=placement_receipt.error;game.model.last_placement_issue=placement_receipt.issue;return
	drag_valid = true
	drag_reason = "Release to move" if drag_item_id >= 0 else ("Release to place" if drag_active else "Click or drag to place")
	if game.model.has_method("placement_warning"):
		drag_warning = str(game.model.placement_warning(drag_kind, drag_cell.x, drag_cell.y, drag_item_id, drag_rotation))
		if drag_warning != "": drag_reason += " · " + drag_warning
	_last_valid_cell = drag_cell

func _commit_preview():
	# Repeat the same validation at commit time. Previewing never purchases,
	# moves, increments revision, rebuilds service routes, or saves.
	_update_validity(last_pointer)
	if not drag_valid:return
	var was_move = drag_item_id >= 0
	if was_move:
		var current: Dictionary = game.model.get_item(drag_item_id)
		if int(current.x) == drag_cell.x and int(current.z) == drag_cell.y and game.model.logical_rotation(drag_item_id) == drag_rotation:
			return
	var success: bool = edit_plan.commit(game.model,placement_receipt,_staff_positions(),game._apply_edit_staff_positions)
	if not success:return
	if was_move: game._cancel_selection()
	game._rebuild_furniture()
	game._update_ui()
	if game._save():game.settings_controls.play_sfx("place")

func _clear_gesture():
	if drag_active and drag_item_id >= 0 and game != null:
		var original: Dictionary = game.model.get_item(drag_item_id)
		if not original.is_empty(): game.rotation_step = game.model.logical_rotation(int(original.id))
	_left_down = false
	_gesture = ""
	_press_item_id = -1
	_press_parcel_id = ""
	_grab_offset = Vector2.ZERO
	drag_active = false
	preview_active = false
	drag_valid = false

func _pan_by(delta: Vector2):
	if not delta.is_finite():return
	game.illustration.pan_offset += delta
	_sync_projection()

func _zoom_step_at(screen:Vector2,direction:float):
	# Multiplicative, reversible steps stay useful throughout the close range.
	_zoom_factor_at(screen,pow(1.15,direction))

func _zoom_factor_at(screen:Vector2,factor:float,pan_delta:Vector2=Vector2.ZERO):
	if not is_finite(factor) or factor<=0.0:return
	_sync_projection()
	_zoom_at(screen,game.illustration.zoom*(factor-1.0),pan_delta)

func _zoom_at(screen:Vector2,amount:float,pan_delta:Vector2=Vector2.ZERO):
	if not screen.is_finite() or not is_finite(amount) or not pan_delta.is_finite():return
	_sync_projection()
	var old_zoom:float=game.illustration.zoom
	var limits:Vector2=game.illustration.camera_zoom_limits()
	var next_zoom=clampf(old_zoom+amount,limits.x,limits.y)
	if is_equal_approx(old_zoom,next_zoom) and pan_delta.is_zero_approx():return
	var world:Vector2=game.illustration.screen_to_world(screen)
	game.illustration.zoom=next_zoom
	# Apply zoom and midpoint translation together, then clamp once. Clamping
	# each half of a pinch separately loses its world anchor at a map edge.
	game.illustration.update_projection(false)
	_pan_by(screen+pan_delta-game.illustration.iso(world.x,world.y))
	if drag_active:_grab_offset*=next_zoom/old_zoom
	refresh(screen+pan_delta)

func _sync_projection():
	if is_instance_valid(game.illustration) and game.illustration.has_method("update_projection"):
		game.illustration.update_projection()
		pan_offset=game.illustration.pan_offset

func _point_in_view(screen: Vector2) -> bool:
	return game.get_viewport().get_visible_rect().has_point(screen)

func _over_ui(screen: Vector2) -> bool:
	# The optional hook makes synthetic tests deterministic. During capture
	# we consume _input before the GUI can refresh its hover state, so inspect
	# actual visible control geometry instead of relying on stale GUI hover.
	if game.has_method("_interaction_over_ui"): return bool(game._interaction_over_ui(screen))
	var ui_root = game.get("ui")
	if is_instance_valid(ui_root): return _ui_tree_blocks(ui_root, screen)
	var control = game.get_viewport().gui_get_hovered_control()
	return is_instance_valid(control) and control.is_visible_in_tree() and control.mouse_filter != Control.MOUSE_FILTER_IGNORE and control.get_global_rect().has_point(screen)

func _ui_tree_blocks(node: Node, screen: Vector2) -> bool:
	if node is Control:
		if not node.is_visible_in_tree(): return false
		if node.clip_contents and not node.get_global_rect().has_point(screen): return false
		if node.mouse_filter != Control.MOUSE_FILTER_IGNORE and node.get_global_rect().has_point(screen): return true
	for child in node.get_children():
		if _ui_tree_blocks(child, screen): return true
	return false

func _staff_positions() -> Array[Vector2]:
	# Read authoritative positions afresh for hover, release, and immediate R
	# rotation, including changes since a previous preview. Never cache them.
	var result:Array[Vector2]=[]
	for staff in game.staff_states:
		result.append(staff.pos)
	return result

func _service_locked(id: int) -> bool:
	return game.has_method("_item_service_locked") and bool(game._item_service_locked(id))

func draw_floor_feedback(artist):
	if not game.editing:return
	for cell in floor_availability.refresh(game.model):
		var blocked=bool(floor_availability.cells[cell].blocked)
		var fill=Color(.66,.38,.29,.22) if blocked else Color(.32,.52,.30,.22)
		var outline=Color(.62,.37,.29,.32) if blocked else Color(.34,.50,.28,.42)
		var corners=[artist.iso(cell.x+.04,cell.y+.04),artist.iso(cell.x+.96,cell.y+.04),artist.iso(cell.x+.96,cell.y+.96),artist.iso(cell.x+.04,cell.y+.96)]
		artist.poly(corners,fill)
		for edge in 4:artist.line(corners[edge],corners[(edge+1)%4],outline,.8)
