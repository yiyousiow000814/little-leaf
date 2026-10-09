extends RefCounted
## Retained native commands for the exact static prefix of IllustratedCafe._draw.
## No image baking, downsampling, geometry welding or reordered commands.
const Visibility=preload("res://scripts/cafe_render_visibility.gd")
const Neighborhood=preload("res://scripts/exterior_environment.gd")
var server=RenderingServer
var canvas=RID()
var signature=[]
var rebuilds=0
var command_count=0
var used=false
var origin_translation_enabled=true
var intro_canvas=RID()
var intro_signature=[]
var intro_anchor=Vector2.ZERO
var intro_coverage=Rect2()
var intro_used=false
var translated_updates=0
class NativeArtist extends RefCounted:
	var source
	var server=RenderingServer
	var canvas:RID
	var origin:Vector2
	var tile:Vector2
	var ui_scale:float
	var zoom:float
	var opacity:float
	var commands=0
	var clip_region=Rect2()
	func _init(artist,rid:RID):
		source=artist;canvas=rid;origin=artist.origin;tile=artist.tile;ui_scale=artist.ui_scale;zoom=artist.zoom;opacity=artist.opacity
	func iso(x,z,h=0.0):return source.iso(x,z,h)
	func get_viewport_rect():return clip_region if clip_region.has_area() else source.get_viewport_rect()
	func render_bounds_visible(bounds):return (not source.use_screen_culling or Visibility.visible(bounds,clip_region,6.0)) if clip_region.has_area() else source.render_bounds_visible(bounds)
	func col(value):
		var color=Color(value) if value is String else value
		color.a*=opacity;return color
	func art_transform(offset:Vector2,rotation:float=0.0,scale:Vector2=Vector2.ONE):
		server.canvas_item_add_set_transform(canvas,Transform2D(rotation,scale,0.0,offset));commands+=1
	func draw_rect(rect:Rect2,color:Color):server.canvas_item_add_rect(canvas,rect,color);commands+=1
	func draw_mesh(mesh:Mesh,_texture):server.canvas_item_add_mesh(canvas,mesh.get_rid());commands+=1
	func poly(points:Array,color):
		var vertices=PackedVector2Array(points);var tint=col(color)
		server.canvas_item_add_polygon(canvas,vertices,PackedColorArray([tint]));commands+=1
		vertices.append(vertices[0]);server.canvas_item_add_polyline(canvas,vertices,PackedColorArray([tint]),.7,true);commands+=1
	func line(a:Vector2,b:Vector2,color,width=1.0):server.canvas_item_add_line(canvas,a,b,col(color),width,true);commands+=1
func release():
	if intro_canvas.is_valid():server.free_rid(intro_canvas);intro_canvas=RID()
	intro_signature=[];intro_used=false
	if canvas.is_valid():server.free_rid(canvas);canvas=RID()
	signature=[];used=false
func _notification(what):
	if what==NOTIFICATION_PREDELETE and intro_canvas.is_valid():server.free_rid(intro_canvas)
	if what==NOTIFICATION_PREDELETE and canvas.is_valid():
		server.free_rid(canvas)
func hide():
	if intro_canvas.is_valid():server.canvas_item_set_visible(intro_canvas,false)
	if canvas.is_valid():server.canvas_item_set_visible(canvas,false)
	used=false
func update(artist)->bool:
	# Nonstandard/inspection paths keep their existing helpers, including stroke
	# compensation under outer canvas transforms. Ordinary world art is identity.
	if artist.material!=null or artist.use_parent_material or artist.self_modulate!=Color.WHITE or artist.clip_children!=CanvasItem.CLIP_CHILDREN_DISABLED or artist.light_mask!=1 or artist.visibility_layer!=1 or artist.y_sort_enabled or not artist.use_batched_ground or not artist.use_grass_mesh or not artist.ground_art.use_stroke_mesh or artist.get_global_transform_with_canvas()!=Transform2D.IDENTITY or artist._art_transform!=Transform2D.IDENTITY:
		hide();return false
	var size=artist.get_viewport_rect().size
	artist.prepare_grass(size)
	artist.ground_art.prepare_pavement_strokes(artist.tile.x/39.0)
	var parking_owned=artist._parking_owned()
	var intro=artist.game.get("cafe_intro")
	if origin_translation_enabled and is_instance_valid(intro) and intro.active:
		return _update_intro(artist,size,parking_owned,intro)
	if intro_used:
		intro_used=false;signature=[]
		server.canvas_item_set_visible(intro_canvas,false)
		server.canvas_item_set_draw_index(canvas,-1)
	var key=[parking_owned,artist.origin,artist.tile,artist.ui_scale,artist.zoom,artist.opacity,size,artist.game.wall_detail,artist.use_screen_culling,artist.grass_mesh,artist.ground_art.pavement_mesh,artist.ground_art.pavement_stroke_mesh]
	if not canvas.is_valid():
		canvas=server.canvas_item_create()
		server.canvas_item_set_parent(canvas,artist.get_canvas_item())
		server.canvas_item_set_draw_behind_parent(canvas,true)
		server.canvas_item_set_draw_index(canvas,-1)
	if key!=signature:
		server.canvas_item_clear(canvas)
		var painter=NativeArtist.new(artist,canvas)
		painter.server=server
		painter.draw_rect(Rect2(Vector2.ZERO,size),Color("c6d5ad"))
		painter.art_transform(artist.origin,0,Vector2.ONE*(artist.tile.x/39.0));painter.draw_mesh(artist.grass_mesh,null);painter.art_transform(Vector2.ZERO)
		Neighborhood.draw_ground(painter,parking_owned)
		artist.ground_art.draw_pavement(painter)
		Neighborhood.draw_crossing(painter,parking_owned)
		command_count=painter.commands;signature=key.duplicate();rebuilds+=1
	server.canvas_item_set_visible(canvas,true);used=true
	return true

func _update_intro(artist,size:Vector2,parking_owned:bool,intro)->bool:
	# The descent moves only translation. Cache enough original world commands
	# for its remaining path; keep the solid screen fill in a separate canvas.
	# Unexpected pan outside that finite coverage simply rebuilds safely.
	var key=[parking_owned,artist.tile,artist.ui_scale,artist.zoom,artist.opacity,size,artist.game.wall_detail,artist.use_screen_culling,artist.grass_mesh,artist.ground_art.pavement_mesh,artist.ground_art.pavement_stroke_mesh]
	var translation=artist.origin-intro_anchor
	var needed=Rect2(-translation,size)
	if not canvas.is_valid():
		canvas=server.canvas_item_create();server.canvas_item_set_parent(canvas,artist.get_canvas_item())
		server.canvas_item_set_draw_behind_parent(canvas,true)
	if not intro_canvas.is_valid():
		intro_canvas=server.canvas_item_create();server.canvas_item_set_parent(intro_canvas,artist.get_canvas_item())
		server.canvas_item_set_draw_behind_parent(intro_canvas,true);server.canvas_item_set_draw_index(intro_canvas,-1)
	if key!=intro_signature or not intro_coverage.encloses(needed):
		intro_anchor=artist.origin;translation=Vector2.ZERO
		intro_coverage=Rect2(Vector2.ZERO,size+Vector2(0,maxf(0.0,float(intro.render_offset(size).y)))).grow(8.0)
		server.canvas_item_clear(canvas)
		server.canvas_item_add_rect(canvas,Rect2(Vector2.ZERO,size),Color("c6d5ad"))
		server.canvas_item_clear(intro_canvas)
		var painter=NativeArtist.new(artist,intro_canvas);painter.server=server;painter.clip_region=intro_coverage
		painter.art_transform(artist.origin,0,Vector2.ONE*(artist.tile.x/39.0));painter.draw_mesh(artist.grass_mesh,null);painter.art_transform(Vector2.ZERO)
		Neighborhood.draw_ground(painter,parking_owned)
		artist.ground_art.draw_pavement(painter)
		Neighborhood.draw_crossing(painter,parking_owned)
		command_count=painter.commands+1;intro_signature=key.duplicate();rebuilds+=1
	server.canvas_item_set_draw_index(canvas,-2)
	server.canvas_item_set_transform(intro_canvas,Transform2D(0,translation))
	server.canvas_item_set_visible(canvas,true);server.canvas_item_set_visible(intro_canvas,true)
	intro_used=true;used=true;translated_updates+=1
	return true
