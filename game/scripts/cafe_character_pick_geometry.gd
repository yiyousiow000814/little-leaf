extends RefCounted
## Query the current retained painter's commands. Never repaint or solve a pose.
## Alpha below this threshold includes the character's non-occluding shadow.
const ALPHA=.2
const CLEAR=0
const HIT=1
const UNKNOWN=2
const Native=preload("res://scripts/cafe_native_draw_node.gd")
const Shape=preload("res://scripts/cafe_shape_2d.gd")
const Strokes=preload("res://scripts/retained_aa_strokes.gd")
var presented_frame=-1
var presented_projection:Array=[]
var draw_projection:Array=[]
var draw_frame=-1
var presented_state=0
var submitted_state=0
var submitted_frame=-1
var last_uncertain=false

func _projection(art)->Array:
	return [art.origin,art.tile,art.zoom,art.ui_scale,art.pan_offset,art.get_viewport_rect(),art.get_global_transform_with_canvas(),art.game.get_instance_id(),art.game.ground_mess_generation,art.game.floor_tasks.get_instance_id(),art.game.floor_tasks.generation]

func drawing(art):
	if not is_instance_valid(art.game) or not art.game.has_method("ground_mess_identity"):return
	draw_projection=_projection(art)
	draw_frame=art.canvas_stream.frame_id

func _supported_ancestors(art)->bool:
	var parent=art.get_parent()
	while parent!=null:
		if parent is CanvasItem and (parent.modulate!=Color.WHITE or parent.material!=null or parent.clip_children!=CanvasItem.CLIP_CHILDREN_DISABLED):return false
		parent=parent.get_parent()
	return art.material==null and art.clip_children==CanvasItem.CLIP_CHILDREN_DISABLED

func _node_state(node:Node2D,state:int)->int:
	state=hash([state,node.get_instance_id(),node.get_parent().get_instance_id(),node.get_global_transform_with_canvas(),node.visible,node.modulate,node.self_modulate,node.material])
	if node.get_script()==Shape:
		state=hash([state,node.draw_method,node.draw_arguments])
		if node.material is ShaderMaterial:state=hash([state,node.material.get_shader_parameter("stroke_width"),node.material.get_shader_parameter("geometry_scale")])
	elif node.get_script()==Native:
		state=hash([state,node.generation,node.appearance,node.draw_count,node.resources])
		for child in node.shapes:
			if is_instance_valid(child):state=_node_state(child,state)
	return state

func _state(art)->int:
	# A bounded scalar receipt, not copied geometry or retained renderer resources.
	var state=hash([art.modulate,art.self_modulate])
	for node in art.native_object_nodes.values():
		if is_instance_valid(node) and not node.appearance.is_empty() and node.appearance[0][0]=="character":state=_node_state(node,state)
	return state

func submitting(art):
	submitted_frame=-1
	if not is_instance_valid(art.game) or not art.game.has_method("ground_mess_identity") or art.canvas_stream.active:return
	if draw_frame!=art.canvas_stream.frame_id or draw_projection!=_projection(art):return
	submitted_state=_state(art)
	submitted_frame=art.canvas_stream.frame_id

func presented(art):
	# Only a completed new painter frame may certify its projection. An idle
	# retained frame must not certify a projection changed after that draw.
	if not is_instance_valid(art.game) or not art.game.has_method("ground_mess_identity") or art.canvas_stream.active:return
	if presented_frame==art.canvas_stream.frame_id:return
	if draw_frame!=art.canvas_stream.frame_id or draw_projection!=_projection(art):return
	if submitted_frame!=art.canvas_stream.frame_id or submitted_state!=_state(art):return
	presented_frame=art.canvas_stream.frame_id
	presented_projection=_projection(art)
	presented_state=submitted_state

func occludes(art,screen:Vector2)->bool:
	last_uncertain=false
	if not screen.is_finite() or not is_instance_valid(art.game) or not art.game.has_method("ground_mess_identity") or not art.use_native_object_nodes or art.canvas_stream.active or presented_frame!=art.canvas_stream.frame_id or presented_projection!=_projection(art) or not _supported_ancestors(art) or presented_state!=_state(art):
		last_uncertain=true;return true
	# Images/mesh arrays live only for this pointer query; no retained readback
	# cache, additional nodes, renderer resources or per-frame geometry copies.
	var images={}
	for node in art.native_object_nodes.values():
		if not is_instance_valid(node) or not node.is_visible_in_tree():continue
		var appearance:Array=node.appearance
		if appearance.is_empty() or appearance[0].is_empty() or appearance[0][0]!="character":continue
		if node.generation!=presented_frame:last_uncertain=true;return true
		# configure clears these existing receipts when appearance changes; the
		# native character callback repopulates them only after actual painting.
		if node.contacts.is_empty():last_uncertain=true;return true
		var result=_node_hit(node,screen,art.modulate.a,images)
		if result!=CLEAR:last_uncertain=result==UNKNOWN;return true
	return false

func _node_hit(node:Node2D,screen:Vector2,opacity:float,images:Dictionary)->int:
	if not node.is_visible_in_tree():return CLEAR
	opacity*=node.modulate.a*node.self_modulate.a
	if opacity<=ALPHA:return CLEAR
	var transform=node.get_global_transform_with_canvas()
	if not transform.is_finite() or is_zero_approx(transform.determinant()):return UNKNOWN
	var point=transform.affine_inverse()*screen
	if node.get_script()==Shape:return command_hit(node.draw_method,node.draw_arguments,point,opacity,transform,node.material,images)
	if node.get_script()!=Native:return UNKNOWN
	if node._rigid_key_supported() and not node.resources.is_empty():
		for mesh in node.resources:
			if not mesh is Mesh:return UNKNOWN
			var result=_mesh_hit(mesh,point,opacity)
			if result!=CLEAR:return result
		return CLEAR
	for child in node.shapes:
		if not is_instance_valid(child):continue
		var result=_node_hit(child,screen,opacity,images)
		if result!=CLEAR:return result
	return CLEAR

func command_hit(method:StringName,args:Array,point:Vector2,opacity:float,transform:Transform2D,material:Material,images:Dictionary)->int:
	match method:
		&"draw_colored_polygon":
			if args[3]!=null:return UNKNOWN
			return HIT if args[1].a*opacity>ALPHA and Geometry2D.is_point_in_polygon(point,args[0]) else CLEAR
		&"draw_polygon":
			if args[3]!=null:return UNKNOWN
			return _triangles_hit(args[0],args[1],Geometry2D.triangulate_polygon(args[0]),point,opacity)
		&"draw_mesh":
			if args[1]!=null:return UNKNOWN
			return _mesh_hit(args[0],args[2].affine_inverse()*point,opacity*args[3].a)
		&"retained_aa_mesh",&"scaled_contours":
			var scale=maxf(transform.x.length(),1.0)
			var width=float(material.get_shader_parameter("stroke_width")) if method==&"retained_aa_mesh" and material is ShaderMaterial else .7
			var geometry_scale=float(material.get_shader_parameter("geometry_scale")) if method==&"scaled_contours" and material is ShaderMaterial else 1.0
			return _mesh_hit(args[0],point,opacity,minf(width*scale,1.0)/scale if method==&"retained_aa_mesh" else 1.0,geometry_scale)
		&"ordered_triangles":return _triangles_hit(args[1],args[2],args[0],point,opacity)
		&"draw_texture_rect_region":return _texture_hit(args,point,opacity,images)
		&"draw_line",&"scalable_line":return _line_hit(args[0],args[1],args[2],args[3],point,opacity,transform)
		&"draw_polyline",&"scalable_polyline",&"draw_multiline":
			var points:PackedVector2Array=args[0]
			for i in range(0,points.size()-1,2 if method==&"draw_multiline" else 1):
				if _line_hit(points[i],points[i+1],args[1],args[2],point,opacity,transform)==HIT:return HIT
			return CLEAR
		&"draw_rect":
			if args[2]:return HIT if args[1].a*opacity>ALPHA and args[0].abs().has_point(point) else CLEAR
			var r:Rect2=args[0];var points=PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y),r.position])
			for i in 4:
				if _line_hit(points[i],points[i+1],args[1],args[3],point,opacity,transform)==HIT:return HIT
			return CLEAR
		&"draw_circle":
			if args[2].a*opacity<=ALPHA:return CLEAR
			var distance=point.distance_to(args[0])
			return HIT if (distance<=args[1] if args[3] else absf(distance-args[1])<=args[4]*.5) else CLEAR
	return UNKNOWN

func _line_hit(a:Vector2,b:Vector2,color:Color,width:float,point:Vector2,opacity:float,transform:Transform2D)->int:
	if color.a*opacity<=ALPHA:return CLEAR
	if width<0:
		var scale=maxf(transform.x.length(),.00001)
		return HIT if point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b))<=.5/scale else CLEAR
	var stroke=Strokes.new();stroke.add_line(a,b,color,width)
	return _triangles_hit(stroke.vertices,stroke.colors,stroke.indices,point,opacity)

func _mesh_hit(mesh:Mesh,point:Vector2,opacity:float,fringe=0.0,geometry_scale=1.0)->int:
	var bounds=mesh.get_aabb()
	var rect=Rect2(Vector2(bounds.position.x,bounds.position.y)*geometry_scale,Vector2(bounds.size.x,bounds.size.y)*geometry_scale)
	if not rect.grow(5.0 if fringe!=0 else 0.0).has_point(point):return CLEAR
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES:return UNKNOWN
		var arrays=mesh.surface_get_arrays(surface);var vertices=PackedVector2Array()
		var uv=arrays[Mesh.ARRAY_TEX_UV]
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			var vertex=arrays[Mesh.ARRAY_VERTEX][i]
			vertices.append(Vector2(vertex.x,vertex.y)*geometry_scale+(uv[i]*fringe if uv!=null and fringe!=0 else Vector2.ZERO))
		var result=_triangles_hit(vertices,arrays[Mesh.ARRAY_COLOR],arrays[Mesh.ARRAY_INDEX],point,opacity)
		if result!=CLEAR:return result
	return CLEAR

func _triangles_hit(vertices,colors,indices,point:Vector2,opacity:float)->int:
	var count=indices.size() if indices!=null and not indices.is_empty() else vertices.size()
	for i in range(0,count-2,3):
		var ids=[indices[i],indices[i+1],indices[i+2]] if indices!=null and not indices.is_empty() else [i,i+1,i+2]
		var a:Vector2=vertices[ids[0]];var b:Vector2=vertices[ids[1]];var c:Vector2=vertices[ids[2]]
		var area=(b-a).cross(c-a)
		if is_zero_approx(area):continue
		var v=(point-a).cross(c-a)/area;var w=(b-a).cross(point-a)/area;var u=1.0-v-w
		if minf(u,minf(v,w))<-.00001:continue
		var alpha=1.0
		if colors!=null and not colors.is_empty():
			alpha=colors[0].a if colors.size()==1 else u*colors[ids[0]].a+v*colors[ids[1]].a+w*colors[ids[2]].a
		if alpha*opacity>ALPHA:return HIT
	return CLEAR

func _texture_hit(args:Array,point:Vector2,opacity:float,images:Dictionary)->int:
	var rect:Rect2=args[1];var source:Rect2=args[2]
	if not rect.abs().has_point(point) or args[3].a*opacity<=ALPHA:return CLEAR
	if is_zero_approx(rect.size.x) or is_zero_approx(rect.size.y):return CLEAR
	var texture:Texture2D=args[0]
	if not images.has(texture):images[texture]=texture.get_image()
	var image:Image=images[texture]
	if image==null or image.is_empty():return UNKNOWN
	var uv=(point-rect.position)/rect.size
	if args[4]:uv=Vector2(uv.y,uv.x)
	var sample=source.position+uv*source.size-Vector2(.5,.5)
	var x=floori(sample.x);var y=floori(sample.y);var mix=sample-Vector2(x,y)
	var a=image.get_pixel(clampi(x,0,image.get_width()-1),clampi(y,0,image.get_height()-1)).a
	var b=image.get_pixel(clampi(x+1,0,image.get_width()-1),clampi(y,0,image.get_height()-1)).a
	var c=image.get_pixel(clampi(x,0,image.get_width()-1),clampi(y+1,0,image.get_height()-1)).a
	var d=image.get_pixel(clampi(x+1,0,image.get_width()-1),clampi(y+1,0,image.get_height()-1)).a
	return HIT if lerpf(lerpf(a,b,mix.x),lerpf(c,d,mix.x),mix.y)*args[3].a*opacity>ALPHA else CLEAR
