extends RefCounted
## Small deterministic collection of authored 2D contours, sampled once.
## Ground anchors and palette are shared; silhouettes are not scaled copies.
const Visibility=preload("res://scripts/cafe_render_visibility.gd")
var tree_bounds={}
var static_contours={}

var use_retained_fills=true
var use_ordered_pockets=true
var ordered_pocket_cache={}
const OrderedPocket=preload("res://scripts/ordered_pocket_triangles.gd")
var fill_meshes={}
var pocket_bounds=[]
var trees={}
var pockets=[]
func _init():
	var airy=[]
	airy.append(shape("958660",Vector2(-5,1),[[-2,-18,-4,-39,-2,-65],[0,-74,5,-87,8,-94],[8,-80,6,-68,5,-57],[11,-69,21,-74,29,-73],[20,-69,12,-57,6,-46],[5,-31,6,-15,8,1],[4,3,-1,3,-5,1]]))
	airy.append(shape("b6a377",Vector2(-1,0),[[0,-22,-1,-40,1,-57],[2,-54,3,-51,3,-46],[3,-30,4,-14,5,1],[2,2,0,2,-1,0]]))
	for leaf in [[-28,-67,25,19],[-8,-93,26,23],[21,-81,24,18],[-19,-111,23,18],[7,-126,20,22],[30,-102,19,17]]:
		airy.append(crown("8bA36d",Vector2(leaf[0],leaf[1]),Vector2(leaf[2],leaf[3])))
		airy.append(crown("a9bd84",Vector2(leaf[0]-3,leaf[1]-5),Vector2(leaf[2]*.68,leaf[3]*.57)))
	trees["airy"]=airy
	var columnar=[]
	columnar.append(shape("938361",Vector2(-4,1),[[-3,-31,-3,-61,0,-108],[4,-86,4,-60,3,-42],[7,-26,5,-12,8,1],[3,3,-1,3,-4,1]]))
	columnar.append(shape("bdad83",Vector2(-2,-1),[[-1,-25,-1,-51,1,-83],[3,-67,2,-45,2,-22],[3,-9,3,-4,4,0],[1,1,0,0,-2,-1]]))
	columnar.append(shape("839c69",Vector2(-19,-48),[[-34,-57,-36,-74,-26,-83],[-33,-98,-24,-117,-17,-119],[-18,-135,-7,-155,3,-158],[15,-153,23,-139,21,-126],[32,-117,30,-99,25,-90],[34,-77,28,-59,16,-51],[2,-43,-8,-42,-19,-48]]))
	columnar.append(shape("9fb780",Vector2(-17,-71),[[-25,-83,-23,-97,-18,-104],[-21,-118,-9,-143,3,-148],[14,-142,17,-128,14,-119],[22,-108,20,-94,15,-87],[23,-73,12,-62,3,-62],[-7,-59,-14,-65,-17,-71]]))
	columnar.append(shape("b1c58d",Vector2(-10,-107),[[-12,-125,-4,-139,3,-144],[13,-136,13,-126,9,-117],[13,-110,9,-97,1,-96],[-6,-96,-11,-100,-10,-107]]))
	trees["columnar"]=columnar
	var sapling=[]
	sapling.append(shape("9a8b64",Vector2(-4,1),[[-1,-20,3,-42,0,-68],[6,-63,7,-52,7,-42],[15,-49,23,-53,28,-55],[21,-48,13,-40,8,-31],[7,-17,7,-6,9,1],[4,3,0,3,-4,1]]))
	for leaf in [[-2,-58,-31,-74], [1,-69,-14,-97], [5,-64,22,-87], [7,-43,37,-57], [3,-46,-24,-57]]:
		sapling.append(leaf_shape("91a975",Vector2(leaf[0],leaf[1]),Vector2(leaf[2],leaf[3]),8))
		sapling.append(leaf_shape("adc28b",Vector2(leaf[0],leaf[1])-Vector2(0,2),Vector2(leaf[2],leaf[3])+Vector2(2,2),3))
	trees["sapling"]=sapling
	# Fan grass: blades change direction, length and curvature around one root.
	var fan=[]
	for leaf in [[0,1,-17,-8,2.4],[1,1,-9,-20,2.5],[1,2,1,-25,2.3],[2,2,13,-16,2.8],[3,2,19,-7,2.1]]:
		fan.append(leaf_shape("91a779" if leaf[2]<0 else "a8b989",Vector2(leaf[0],leaf[1]),Vector2(leaf[2],leaf[3]),leaf[4]))
	pockets.append(fan)
	# Low shrub: uneven joined canopy rather than disconnected identical circles.
	var shrub=[]
	shrub.append(shape("8fa477",Vector2(-24,2),[[-28,-4,-24,-11,-17,-12],[-19,-20,-8,-23,-3,-17],[3,-24,14,-22,18,-14],[27,-12,30,-4,24,1],[10,7,-10,7,-24,2]]))
	shrub.append(shape("a7b987",Vector2(-19,-5),[[-18,-12,-10,-15,-4,-10],[0,-17,10,-17,14,-10],[20,-11,22,-5,18,-2],[8,2,-8,2,-19,-5]]))
	for leaf in [[-13,-6,-17,-13],[-2,-8,1,-17],[10,-5,17,-10]]:shrub.append(leaf_shape("bfcca1",Vector2(leaf[0],leaf[1]),Vector2(leaf[2],leaf[3]),2.5))
	pockets.append(shrub)
	# Fern: flat spreading compound fronds with visible gaps and angled leaflets.
	var fern=[]
	for side in [-1,1]:
		fern.append(leaf_shape("8fa579",Vector2(0,2),Vector2(side*24,-10),1.7))
		for i in range(1,5):
			var base=Vector2(side*i*4.3,1-i*1.8)
			fern.append(leaf_shape("a3b585",base,base+Vector2(side*3,-6-i*.7),2.0))
	fern.append(leaf_shape("98ad7d",Vector2(0,2),Vector2(-2,-17),2.2))
	pockets.append(fern)
	for variant in trees:tree_bounds[variant]=bounds_for(trees[variant])
	for pocket in pockets:pocket_bounds.append(bounds_for(pocket))
func shape(color:String,start:Vector2,curves:Array)->Array:
	var vertices=PackedVector2Array([start]);var previous=start
	for c in curves:
		var finish=Vector2(c[4],c[5])
		for step in range(1,9):vertices.append(previous.bezier_interpolate(Vector2(c[0],c[1]),Vector2(c[2],c[3]),finish,float(step)/8))
		previous=finish
	if vertices[-1].is_equal_approx(start):vertices.remove_at(vertices.size()-1)
	return [color,vertices]
func crown(color:String,center:Vector2,radius:Vector2)->Array:
	return shape(color,center+Vector2(-radius.x,0),[
		[center.x-radius.x*1.1,center.y-radius.y*.6,center.x-radius.x*.4,center.y-radius.y*1.1,center.x,center.y-radius.y],
		[center.x+radius.x*.4,center.y-radius.y*1.2,center.x+radius.x,center.y-radius.y*.5,center.x+radius.x,center.y],
		[center.x+radius.x*1.1,center.y+radius.y*.65,center.x+radius.x*.4,center.y+radius.y,center.x,center.y+radius.y*.8],
		[center.x-radius.x*.4,center.y+radius.y,center.x-radius.x*1.1,center.y+radius.y*.4,center.x-radius.x,center.y]])
func leaf_shape(color:String,base:Vector2,tip:Vector2,width:float)->Array:
	var axis=tip-base;var side=axis.normalized().orthogonal()*width
	return shape(color,base,[[base.x+axis.x*.3+side.x,base.y+axis.y*.3+side.y,tip.x+side.x,tip.y+side.y,tip.x,tip.y],[tip.x-side.x,tip.y-side.y,base.x+axis.x*.3-side.x,base.y+axis.y*.3-side.y,base.x,base.y]])
func bounds_for(items:Array)->Rect2:
	var bounds=Rect2();var first=true
	for item in items:
		var part=Visibility.points_bounds(item[1])
		bounds=part if first else bounds.merge(part);first=false
	return bounds
func _fill_mesh(points:PackedVector2Array)->ArrayMesh:
	if fill_meshes.has(points):return fill_meshes[points]
	var triangles=Geometry2D.triangulate_polygon(points)
	if triangles.is_empty():return null
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=points
	arrays[Mesh.ARRAY_INDEX]=triangles
	var mesh=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	fill_meshes[points]=mesh
	return mesh
func draw_layers(a,items:Array,ground:Vector2,scale:float,local_bounds:Rect2,variant_key:String=""):
	var bounds=Visibility.local_bounds(ground,scale,local_bounds)
	if a.has_method("render_bounds_visible"):
		if not a.render_bounds_visible(bounds):return
	elif a.has_method("get_viewport_rect") and not Visibility.visible(bounds,a.get_viewport_rect(),6.0):return
	if variant_key!="" and a.has_method("draw_scaled_contours") and a.canvas_stream.active and a.use_native_object_nodes and a.get_global_transform_with_canvas()==Transform2D.IDENTITY and a._art_transform==Transform2D(0,a._presentation_offset):
		var key=[variant_key,a.opacity]
		if not static_contours.has(key):
			var mesh=_make_static_contours(items,a)
			if mesh!=null:
				if static_contours.size()>=64:static_contours.erase(static_contours.keys()[0])
				static_contours[key]=mesh
		if static_contours.has(key):
			a.draw_scaled_contours(static_contours[key],ground,scale)
			return
	var transform=Transform2D(Vector2(scale,0),Vector2(0,scale),ground)
	# Keep every authored contour, native outline, and painter position. Only
	# immutable fill geometry gains a retained resource; inspection/painters
	# with outer transforms continue through the original poly implementation.
	var retained=use_retained_fills and a is CanvasItem and "_art_transform" in a and a._art_transform==Transform2D(0,a._presentation_offset) and a.has_method("art_polyline")
	if use_ordered_pockets and retained and a.get_global_transform_with_canvas()==Transform2D.IDENTITY and items in pockets:
		var key=[items.hash(),ground,scale,a.opacity]
		if not ordered_pocket_cache.has(key):
			var ordered=OrderedPocket.new();var valid=true
			for item in items:
				if not ordered.append_contour(transform*item[1],a.col(item[0]),.7):valid=false;break
			if valid:
				if ordered_pocket_cache.size()>=64:ordered_pocket_cache.clear()
				ordered_pocket_cache[key]=ordered
		if ordered_pocket_cache.has(key):
			var ordered=ordered_pocket_cache[key]
			if a.has_method("draw_ordered_triangles"):a.draw_ordered_triangles(ordered)
			else:RenderingServer.canvas_item_add_triangle_array(a.get_canvas_item(),ordered.indices,ordered.vertices,ordered.colors)
			return
	for item in items:
		var mesh=_fill_mesh(item[1]) if retained else null
		if mesh==null:a.poly(Array(transform*item[1]),item[0]);continue
		preload("res://scripts/cafe_canvas_draw.gd").draw_mesh(a,mesh,null,transform,a.col(item[0]))
		var outline:PackedVector2Array=transform*item[1]
		outline.append(outline[0])
		a.art_polyline(outline,a.col(item[0]),.7)
func draw_tree(a,ground:Vector2,scale:float,variant:String):
	a.ellipse(ground+Vector2(2,0),Vector2(31,9)*scale,Color(.45,.57,.32,.12))
	draw_layers(a,trees[variant],ground,scale,tree_bounds[variant],"tree:"+variant)
func draw_pocket(a,p:Vector2,variant:int):
	var index=posmod(variant,pockets.size())
	draw_layers(a,pockets[index],a.iso(p.x,p.y),a.ui_scale*a.zoom*.75,pocket_bounds[index],"pocket:"+str(index))

func _make_static_contours(items:Array,artist)->ArrayMesh:
	var full=OrderedPocket.new();var center=OrderedPocket.new()
	for item in items:
		if not full.append_contour(item[1],artist.col(item[0]),.7):return null
		if not center.append_contour(item[1],artist.col(item[0]),0.0):return null
	if full.vertices.size()!=center.vertices.size() or full.vertices.is_empty():return null
	var offsets=PackedVector2Array()
	for index in range(full.vertices.size()):offsets.append(full.vertices[index]-center.vertices[index])
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=center.vertices
	arrays[Mesh.ARRAY_TEX_UV]=offsets
	arrays[Mesh.ARRAY_COLOR]=full.colors
	arrays[Mesh.ARRAY_INDEX]=full.indices
	var mesh=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return mesh
