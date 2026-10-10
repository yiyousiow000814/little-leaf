extends "res://scripts/cafe_native_draw_node.gd"
## Local doorway visibility; the unchanged character draw list is a child.
## The illustration owns/reuses this existing painter slot and frees both nodes.
const Body=preload("res://scripts/cafe_native_draw_node.gd")
var body:Node2D
var reveal=Rect2()

func _init():
	set_meta("parking_portal",true)
	body=Body.new();add_child(body)

func configure(source:Node2D,callback:Callable,next:Array,placement:Transform2D):
	var masked=next[0] is Array and next[0][-1] is Dictionary and next[0][-1].has("parking_portal_rect")
	var shape=next.duplicate(true) if masked else next
	if masked:shape[0][-1].erase("parking_portal_rect")
	var rect:Rect2=next[0][-1].parking_portal_rect if masked else Rect2()
	var mode=CanvasItem.CLIP_CHILDREN_ONLY if masked else CanvasItem.CLIP_CHILDREN_DISABLED
	if reveal!=rect or clip_children!=mode:
		reveal=rect;clip_children=mode;queue_redraw()
	# This parent paints only the mask. The child retains the existing actor art,
	# including atlas heads, body parts and original grounded walking animation.
	transform=placement;modulate=source.self_modulate
	body.configure(source,callback,shape,Transform2D.IDENTITY)
	body.modulate=Color.WHITE
	contacts=body.contacts
	show()

func _draw():
	if clip_children==CanvasItem.CLIP_CHILDREN_ONLY:draw_rect(reveal,Color.WHITE)

static func draw(artist,position:Vector2,id:int,moving:bool,pose:Dictionary,heading:Vector2,plane:Vector2):
	# The normal retained character path supplies precisely the same callback.
	# Replace only this local painter slot with a clipped parent; later ordinary
	# objects can reuse the slot with clipping disabled by configure().
	var order=artist.canvas_stream.cursor
	if not artist.native_object_nodes.has(order) or not artist.native_object_nodes[order].has_meta("parking_portal"):
		if artist.native_object_nodes.has(order):
			var old=artist.native_object_nodes[order];old.hide();artist.remove_child(old);old.queue_free()
		var node=load("res://scripts/parking_passenger_portal.gd").new()
		artist._insert_native_canvas_child(node,order);artist.native_object_nodes[order]=node
	var local=artist._art_transform.affine_inverse()*(artist.iso(plane.x,plane.y)+artist._presentation_offset)
	var rect=Rect2(local.x,-512,1024,1024) if artist._art_transform.x.x>0 else Rect2(-1024,-512,1024+local.x,1024)
	var options=pose.duplicate();options.parking_portal_rect=rect
	artist.character(position,id,false,moving,false,"walking",0,Vector2(18,-28),heading,"none","none",options)
