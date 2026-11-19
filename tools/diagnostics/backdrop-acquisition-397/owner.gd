extends "res://ll397_active_backdrop.gd"
## Disposable diagnostics only. No forced draw, manual refresh frame, or CPU pixel readback here.
const EXPECTED_PREFIX := 139288
var _armed_key: Array = []
var _armed_generation := -1
var _submitted := [false, false, false]  # screen stock, geometry stock, cache quad; last visible commands

func _submit_pair(orig:bool, quad:bool)->void:
	if not used or not screen_canvas.is_valid() or not canvas.is_valid():
		if _replacement.is_valid():RenderingServer.canvas_item_set_visible(_replacement,false)
		_submitted=[false,false,false]
		return
	RenderingServer.canvas_item_set_visible(screen_canvas,orig)
	RenderingServer.canvas_item_set_visible(canvas,orig)
	if _replacement.is_valid():RenderingServer.canvas_item_set_visible(_replacement,quad)
	_submitted=[orig,orig,quad and _replacement.is_valid()]

func _restore():
	_submit_pair(true,false)
	_selected=false

func refresh_selection(a)->bool:
	if not _enabled or not is_instance_valid(a) or a!=_owner:return false
	var k:=key_for(a)
	var valid:=_mode=="cache" and not pending() and not _baking and _replacement.is_valid() and is_instance_valid(_vp) and _vp.render_target_update_mode==SubViewport.UPDATE_DISABLED and not k.is_empty() and _baked==k
	_submit_pair(not valid,valid)
	_selected=valid
	return valid

func pending()->bool:
	return not _armed_key.is_empty()

func discard()->void:
	_armed_key=[]
	_armed_generation=-1
	_baked=[]
	_baking=false
	if is_instance_valid(_vp):_vp.render_target_update_mode=SubViewport.UPDATE_DISABLED
	_restore()

func hide():
	super.hide()
	discard()

func _immediate_resize():
	_generation+=1
	discard()

func update(a,landed_origin=null,presentation_offset=Vector2.ZERO)->bool:
	var result:bool=super.update(a,landed_origin,presentation_offset)
	if pending() and _armed_generation!=_generation:discard()
	return result

func drawing_state()->Dictionary:
	return {"generation":_generation,"selected":_submitted==[false,false,true] and _selected,
		"root_original":used and _submitted==[true,true,false],"pending":pending(),
		"update_mode":RenderingServer.viewport_get_update_mode(_vp.get_viewport_rid()) if is_instance_valid(_vp) else -1}

func arm(a)->bool:
	var k:=key_for(a)
	if pending() or _baking or _inside or a!=_owner or k.is_empty():return false
	discard()
	if not _init_producer(a):return false
	var extent:Vector2i=a.get_tree().root.size
	_vp.size=extent
	_vp.size_2d_override=extent
	_vp.size_2d_override_stretch=true
	# Identical five borrowed resources, two orders, target and first-use population as the pixel-verified bake.
	var s:float=a.tile.x/39.0
	for id in _items:RenderingServer.canvas_item_clear(id)
	RenderingServer.canvas_item_add_rect(_items[0],Rect2(Vector2.ZERO,Vector2(extent)),Color("c6d5ad"))
	RenderingServer.canvas_item_set_transform(_items[1],Transform2D(0,_origin))
	RenderingServer.canvas_item_add_mesh(_items[1],a.grass_mesh.get_rid(),Transform2D(0,Vector2.ONE*s,0,Vector2.ZERO),Color.WHITE)
	for i in range(3):
		var id:=_items[i+2]
		RenderingServer.canvas_item_set_material(id,material.get_rid())
		RenderingServer.canvas_item_set_custom_rect(id,true,Rect2(-100000,-100000,200000,200000))
		if i==1:RenderingServer.canvas_item_add_mesh(id,a.ground_art.pavement_mesh.get_rid(),Transform2D.IDENTITY,Color.WHITE)
		if meshes[i].get_surface_count()>0:RenderingServer.canvas_item_add_mesh(id,meshes[i].get_rid())
	_armed_key=k.duplicate();_armed_generation=_generation;_baking=true
	_vp.render_target_update_mode=SubViewport.UPDATE_ONCE
	return true

func finish(a)->bool:
	if not pending() or not is_instance_valid(_vp) or RenderingServer.viewport_get_update_mode(_vp.get_viewport_rid())!=RenderingServer.VIEWPORT_UPDATE_DISABLED or _armed_generation!=_generation or key_for(a)!=_armed_key or not drawing_state().root_original:
		discard();return false
	var n:=_vp.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	if n!=EXPECTED_PREFIX:
		discard();return false
	# The native transition ONCE -> DISABLED happens after this exact viewport draws.
	_vp.render_target_update_mode=SubViewport.UPDATE_DISABLED  # synchronize the scene-side requested mode after observing the native one-shot
	var size:=_vp.size
	RenderingServer.canvas_item_clear(_replacement)
	RenderingServer.canvas_item_add_texture_rect(_replacement,Rect2(Vector2.ZERO,Vector2(size)),_vp.get_texture().get_rid(),false,Color.WHITE,false)
	_prefix_primitives=n;_baked=_armed_key.duplicate();_armed_key=[];_armed_generation=-1;_baking=false
	_resident_color_bytes=size.x*size.y*4;_bakes+=1
	refresh_selection(a)
	return true

func refresh_before_root(a)->bool:
	# Recheck generation & every structural dependency before each actual observed root, not just artist updates.
	if pending() and (_armed_generation!=_generation or key_for(a)!=_armed_key):
		discard()
	if not _baked.is_empty() and key_for(a)!=_baked:discard()
	return refresh_selection(a)
