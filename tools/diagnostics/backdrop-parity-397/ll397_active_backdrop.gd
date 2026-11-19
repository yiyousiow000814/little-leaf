extends "res://scripts/rendering/cafe_background_cache.gd"
## Disposable #397 diagnostic. Stock owns all resources, order and fallback.
## The producer borrows the exact resolved meshes; it never owns game state.
const MAX_SIZE := Vector2i(1360,880)
var _mode := "original"
var _owner: Node2D
var _enabled := false
var _inside := false
var _origin := Vector2.ZERO
var _vp: SubViewport
var _items: Array[RID] = []
var _replacement := RID()
var _baked: Array = []
var _last: Array = []
var _selected := false
var _baking := false
var _generation := 0
var _draw_updates := 0
var _eligible_updates := 0
var _changes := 0
var _hits := 0
var _misses := 0
var _bakes := 0
var _direct_updates := 0
var _resident_color_bytes := 0
var _prefix_primitives := 0

func control_mode(mode: String) -> void:
	_mode = mode if mode in ["original","cache"] else "original"
	_enabled = true
	if is_instance_valid(_owner): refresh_selection(_owner)

func _base_ok(a) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(a.game) or a != a.game.illustration or a.icon_kind != "" or not used or not a.is_visible_in_tree(): return false
	var root: Window = a.get_tree().root
	if a.get_viewport()!=root or not root or a.get_parent()!=a.game or a.game.get_parent()!=root or a.get_canvas_layer_node()!=null: return false
	var extent: Vector2i=root.size
	if extent.x<640 or extent.y<400 or extent.x>MAX_SIZE.x or extent.y>MAX_SIZE.y or a.get_viewport_rect().size!=Vector2(extent): return false
	if root.use_hdr_2d or root.msaa_2d!=Viewport.MSAA_DISABLED or root.snap_2d_transforms_to_pixel or root.snap_2d_vertices_to_pixel or root.canvas_transform!=Transform2D.IDENTITY or root.global_canvas_transform!=Transform2D.IDENTITY or root.get_final_transform()!=Transform2D.IDENTITY: return false
	if a.get_global_transform_with_canvas()!=Transform2D.IDENTITY or a.modulate!=Color.WHITE or a.self_modulate!=Color.WHITE or a.material!=null or a.use_parent_material or a.clip_children!=CanvasItem.CLIP_CHILDREN_DISABLED or a.light_mask!=1 or a.visibility_layer!=1 or a.y_sort_enabled or a.opacity!=1.0: return false
	if a.texture_filter!=CanvasItem.TEXTURE_FILTER_LINEAR or a.texture_repeat!=CanvasItem.TEXTURE_REPEAT_PARENT_NODE or a.game.cafe_intro==null or a.game.cafe_intro.active or a.game.cafe_intro.preparing: return false
	if not (a.use_background_cache and a.use_retained_presentation and a.use_grass_mesh and a.use_batched_ground) or material==null or meshes.size()!=3 or geometry_items.size()!=3 or command_count!=6: return false
	return root.get_visible_rect().size==Vector2(extent) and a.ground_art.pavement_mesh!=null and a.grass_mesh!=null and canvas.is_valid() and screen_canvas.is_valid()

func key_for(a) -> Array:
	if not _base_ok(a): return []
	# During _draw artist.origin has pan removed. _origin is the exact native
	# transform used by super.update(); after _draw normal projection is restored.
	if not _inside and _origin!=a.origin: return []
	return [a.get_tree().root.size,_origin,a.tile,a.pan_offset,a.zoom,a.ui_scale,a._parking_owned(),
		a.opacity,rebuilds,material.get_rid(),material.get_shader_parameter("geometry_scale"),a.grass_mesh.get_rid(),
		a.ground_art.pavement_mesh.get_rid(),meshes[0].get_rid(),meshes[1].get_rid(),meshes[2].get_rid()]

func projection_for(a)->Array:
	if key_for(a).is_empty():return []
	return [a.get_tree().root.size,_origin,a.tile,a.pan_offset,a.zoom,a.ui_scale,a.opacity,a._parking_owned(),
		a.get_global_transform_with_canvas(),a.get_tree().root.get_final_transform()]

func update(a,landed_origin=null,presentation_offset=Vector2.ZERO)->bool:
	var stock:bool=super.update(a,landed_origin,presentation_offset)
	if not _enabled or a.icon_kind!="" or not is_instance_valid(a.game) or a!=a.game.illustration: return stock
	_owner=a
	_inside=true
	_origin=a.origin+presentation_offset
	_draw_updates+=1
	var k:=key_for(a)
	if not k.is_empty(): _eligible_updates+=1
	if k!=_last:
		_changes+=1
		_generation+=1
		_baked=[]
	_last=k
	refresh_selection(a)
	_inside=false
	return stock

func hide():
	super.hide()
	_selected=false
	_baked=[]
	if _replacement.is_valid(): RenderingServer.canvas_item_set_visible(_replacement,false)

func _restore():
	if _replacement.is_valid(): RenderingServer.canvas_item_set_visible(_replacement,false)
	# Stock fallback owns its visibility when optimized stock was rejected.
	if used and canvas.is_valid() and screen_canvas.is_valid():
		RenderingServer.canvas_item_set_visible(screen_canvas,true)
		RenderingServer.canvas_item_set_visible(canvas,true)
	_selected=false

func refresh_selection(a)->bool:
	if not _enabled or not is_instance_valid(a) or a!=_owner: return false
	var k:=key_for(a)
	var valid:=_mode=="cache" and not _baking and _replacement.is_valid() and is_instance_valid(_vp) and _vp.render_target_update_mode==SubViewport.UPDATE_DISABLED and not k.is_empty() and _baked==k
	if not valid:
		if _mode=="cache":_misses+=1
		_direct_updates+=1
		_restore()
		return false
	RenderingServer.canvas_item_set_visible(screen_canvas,false)
	RenderingServer.canvas_item_set_visible(canvas,false)
	RenderingServer.canvas_item_set_visible(_replacement,true)
	_selected=true
	_hits+=1
	return true

func _immediate_resize():
	# Direct size signal; no waiting for a later gameplay tick/redraw.
	_baked=[]
	_generation+=1
	_restore()

func _init_producer(a) -> bool:
	if is_instance_valid(_vp): return true
	_vp=SubViewport.new()
	_vp.world_2d=World2D.new()
	_vp.disable_3d=true
	_vp.transparent_bg=true
	_vp.use_hdr_2d=false
	_vp.msaa_2d=Viewport.MSAA_DISABLED
	_vp.render_target_clear_mode=SubViewport.CLEAR_MODE_ALWAYS
	_vp.render_target_update_mode=SubViewport.UPDATE_DISABLED
	a.get_tree().root.add_child(_vp)
	var layer:=_vp.world_2d.canvas
	# Draw indices reproduce the two stock behind-parent branches inside a
	# private viewport with no other art and a single neutral origin.
	_items.append(_new_item(layer,0))
	_items.append(_new_item(layer,1))
	for i in range(3): _items.append(_new_item(_items[1],i))
	_replacement=_new_item(a.get_canvas_item(),-2)
	RenderingServer.canvas_item_set_draw_behind_parent(_replacement,true)
	RenderingServer.canvas_item_set_visible(_replacement,false)
	RenderingServer.canvas_item_set_default_texture_filter(_replacement,RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
	a.get_tree().root.size_changed.connect(_immediate_resize)
	return true

func bake_once(a)->bool:
	# Synchronous isolated diagnostic only. Never call this during _draw,
	# frame_pre_draw or frame_post_draw.
	var k:=key_for(a)
	if _baking or _inside or k.is_empty() or a!=_owner: return false
	_baked=[]
	_restore()
	_baking=true
	if not _init_producer(a):
		_baking=false
		return false
	var size:Vector2i=a.get_tree().root.size
	_vp.size=size
	_vp.size_2d_override=size
	_vp.size_2d_override_stretch=true
	var gen:=_generation
	var scale_factor:float=a.tile.x/39.0
	for id in _items: RenderingServer.canvas_item_clear(id)
	RenderingServer.canvas_item_add_rect(_items[0],Rect2(Vector2.ZERO,Vector2(size)),Color("c6d5ad"))
	RenderingServer.canvas_item_set_transform(_items[1],Transform2D(0,_origin))
	RenderingServer.canvas_item_add_mesh(_items[1],a.grass_mesh.get_rid(),Transform2D(0,Vector2.ONE*scale_factor,0,Vector2.ZERO),Color.WHITE)
	for i in range(3):
		var s:=_items[i+2]
		RenderingServer.canvas_item_set_material(s,material.get_rid())
		RenderingServer.canvas_item_set_custom_rect(s,true,Rect2(-100000,-100000,200000,200000))
		if i==1:RenderingServer.canvas_item_add_mesh(s,a.ground_art.pavement_mesh.get_rid(),Transform2D.IDENTITY,Color.WHITE)
		if meshes[i].get_surface_count()>0:RenderingServer.canvas_item_add_mesh(s,meshes[i].get_rid())
	_vp.render_target_update_mode=SubViewport.UPDATE_ONCE
	RenderingServer.force_draw(false,0.0)
	_prefix_primitives=_vp.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	_vp.render_target_update_mode=SubViewport.UPDATE_DISABLED
	_baking=false
	if gen!=_generation or key_for(a)!=k: return false
	RenderingServer.canvas_item_clear(_replacement)
	RenderingServer.canvas_item_add_texture_rect(_replacement,Rect2(Vector2.ZERO,Vector2(size)),_vp.get_texture().get_rid(),false,Color.WHITE,false)
	_resident_color_bytes=size.x*size.y*4
	_baked=k.duplicate()
	_bakes+=1
	refresh_selection(a)
	return true

func producer_is_rgba_opaque() -> bool:
	if not is_instance_valid(_vp) or _baked.is_empty():return false
	var im:=_vp.get_texture().get_image()
	if im==null or im.get_size()!=_vp.size:return false
	im.convert(Image.FORMAT_RGBA8)
	var bytes:=im.get_data()
	for i in range(3,bytes.size(),4):
		if bytes[i]!=255:return false
	return bytes.size()==_vp.size.x*_vp.size.y*4

func witness()->Dictionary:
	return {"hits":_hits,"misses":_misses,"changes":_changes,"bakes":_bakes,"selected":_selected,"draw_updates":_draw_updates,"eligible_updates":_eligible_updates,"pixel_bytes":_resident_color_bytes,"direct_selections":_direct_updates,"prefix_primitives":_prefix_primitives,
	"producer_disabled":not is_instance_valid(_vp) or _vp.render_target_update_mode==SubViewport.UPDATE_DISABLED}

func release():
	if is_instance_valid(_vp):
		var root:=_vp.get_tree().root if _vp.is_inside_tree() else null
		if root and root.size_changed.is_connected(_immediate_resize): root.size_changed.disconnect(_immediate_resize)
	if _replacement.is_valid():
		RenderingServer.free_rid(_replacement)
		_replacement=RID()
	for i in range(_items.size()-1,-1,-1):RenderingServer.free_rid(_items[i])
	_items.clear()
	if is_instance_valid(_vp): _vp.queue_free()
	_vp=null
	_baked=[]
	_selected=false
	super.release()
