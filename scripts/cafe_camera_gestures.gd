extends RefCounted
## Mouse emulation remains enabled for ordinary one-finger GUI/world gestures.
## Godot dispatches that emulated mouse event before the corresponding touch.
## Any second finger cancels a held world edit; two world fingers take camera
## ownership before any release can commit it. Ownership lasts until every
## finger has lifted.
var game
var touches:Dictionary={}
var world_touches:Dictionary={}
var pinching=false
var touch_edit_canceled=false
var pinch_ids:Array=[]
var previous_center=Vector2.ZERO
var previous_distance=0.0
var emulated_press_pending=false
var emulated_press_blocked=false

func _init(owner_game):game=owner_game

func handle_input(event:InputEvent)->bool:
	if event is InputEventMouse:
		if pinching or touch_edit_canceled:return true
		if event is InputEventMouseButton and event.device==InputEvent.DEVICE_ID_EMULATION and event.pressed:
			emulated_press_pending=true
			emulated_press_blocked=_popup_open() or game.interaction._over_ui(event.position)
		if event is InputEventMouseButton and event.canceled:
			on_focus_lost();return true
	if event is InputEventScreenTouch:
		return _touch(event)
	if event is InputEventScreenDrag:
		if touches.has(event.index):touches[event.index]=event.position
		if pinching:
			_update_pinch();return true
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		var focus=game.get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:return false
		if event.keycode==KEY_F1:
			_cancel_pending();game.compact_ui.show_help();return true
		if _popup_open() or focus is OptionButton or focus is Range or focus is ScrollContainer:return false
		if event.keycode in [KEY_PLUS,KEY_EQUAL,KEY_KP_ADD,KEY_MINUS,KEY_KP_SUBTRACT,KEY_0,KEY_KP_0,KEY_HOME]:
			_cancel_pending()
			if event.keycode in [KEY_0,KEY_KP_0,KEY_HOME]:
				game.illustration.fit_overview();game.interaction.pan_offset=game.illustration.pan_offset
			else:
				game.interaction._zoom_step_at(game.get_viewport().get_visible_rect().get_center(),1.0 if event.keycode in [KEY_PLUS,KEY_EQUAL,KEY_KP_ADD] else -1.0)
			return true
	if event is InputEventMagnifyGesture:
		if _popup_open() or game.interaction._over_ui(event.position):return false
		_cancel_pending()
		game.interaction._zoom_factor_at(event.position,event.factor)
		return true
	return false

func _touch(event:InputEventScreenTouch)->bool:
	var owned=pinching or touch_edit_canceled
	if event.pressed and not event.canceled:
		touches[event.index]=event.position
		var blocked_before_dispatch=emulated_press_pending and emulated_press_blocked
		emulated_press_pending=false
		if not blocked_before_dispatch and not _popup_open() and game.interaction._point_in_view(event.position) and not game.interaction._over_ui(event.position):
			world_touches[event.index]=true
		if touches.size()>=2 and game.interaction!=null and game.interaction._left_down:
			# Even a second finger on UI invalidates a held world edit. It must
			# never leave the first release able to commit the furniture.
			touch_edit_canceled=true
			_cancel_pending()
		if not pinching and world_touches.size()>=2:
			pinching=true;pinch_ids=world_touches.keys().slice(0,2)
			_cancel_pending();_rebase_pinch()
		return pinching or touch_edit_canceled
	if event.canceled:_cancel_pending()
	touches.erase(event.index);world_touches.erase(event.index)
	# Do not promote the remaining finger to a fresh edit gesture after pinch.
	# Nor may a third finger cause a discontinuity by replacing a released pair.
	if touches.is_empty():
		pinching=false;touch_edit_canceled=false;pinch_ids.clear();previous_distance=0.0
	return owned

func _rebase_pinch():
	if pinch_ids.size()!=2:return
	var a:Vector2=touches[pinch_ids[0]];var b:Vector2=touches[pinch_ids[1]]
	previous_center=(a+b)*.5;previous_distance=a.distance_to(b)

func _update_pinch():
	if pinch_ids.size()!=2 or not touches.has(pinch_ids[0]) or not touches.has(pinch_ids[1]):return
	var a:Vector2=touches[pinch_ids[0]];var b:Vector2=touches[pinch_ids[1]]
	var center=(a+b)*.5;var distance=a.distance_to(b)
	var factor=distance/previous_distance if previous_distance>=8.0 and distance>=8.0 else 1.0
	game.interaction._zoom_factor_at(previous_center,factor,center-previous_center)
	previous_center=center;previous_distance=distance

func _popup_open()->bool:
	if is_instance_valid(game.settings) and game.settings.visible:return true
	if game.compact_ui==null:return false
	if game.compact_ui.has_method("has_open_popup"):return game.compact_ui.has_open_popup()
	for panel in game.compact_ui._popup_panels():
		if is_instance_valid(panel) and panel.visible:return true
	return false

func _cancel_pending():
	if game.interaction!=null:game.interaction.on_focus_lost()
	if game.build_tools!=null:game.build_tools.on_focus_lost()

func on_focus_lost():
	_cancel_pending();touches.clear();world_touches.clear();pinch_ids.clear();pinching=false;touch_edit_canceled=false;previous_distance=0.0;emulated_press_pending=false
