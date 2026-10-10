extends SceneTree
const Pick=preload("res://scripts/cafe_character_pick_geometry.gd")
const Native=preload("res://scripts/cafe_native_draw_node.gd")
const Shape=preload("res://scripts/cafe_shape_2d.gd")
class CountingPick extends Pick:
	var state_calls=0
	func _state(art)->int:
		state_calls+=1
		return super._state(art)
var checks=0
var failures=[]
class Ledger extends RefCounted:
	var generation=0
class Owner extends Node2D:
	var ground_mess_generation=0
	var floor_tasks=Ledger.new()
	func ground_mess_identity(_ledger,_id):return {}
class Stream extends RefCounted:
	var active=false
	var frame_id=1
class Art extends Node2D:
	var game
	var canvas_stream=Stream.new()
	var native_object_nodes={}
	var use_native_object_nodes=true
	var origin=Vector2.ZERO
	var tile=Vector2(39,19.5)
	var zoom=1.0
	var ui_scale=1.0
	var pan_offset=Vector2.ZERO
func _initialize():run.call_deferred()
func check(value,label):
	checks+=1
	if not value:failures.append(label);printerr("FAIL ",label)
func present(pick,art,node):
	art.canvas_stream.frame_id+=1;node.generation=art.canvas_stream.frame_id
	pick.request_query();pick.drawing(art);pick.submitting(art);pick.presented(art)
func run():
	# Command/receipt fixture only. Actual current painter pixels are a separate
	# native capture gate; this test never claims a synthetic receipt was painted.
	var pick=CountingPick.new();var art=Art.new();var game=Owner.new()
	root.add_child(game);game.add_child(art);art.game=game
	var node=Native.new();art.add_child(node)
	node.appearance=[["character"]];node.contacts=[{"id":1}];node.generation=1
	art.native_object_nodes[0]=node
	var shape=Shape.new();node.add_child(shape);node.shapes.append(shape)
	var square=PackedVector2Array([Vector2(-5,-5),Vector2(5,-5),Vector2(5,5),Vector2(-5,5)])
	shape.configure(&"draw_colored_polygon",[square,Color.WHITE,PackedVector2Array(),null],Transform2D.IDENTITY)
	check(pick.occludes(art,Vector2.ZERO) and pick.last_uncertain,"unpresented pointer fails closed")
	for frame in 60:
		pick.drawing(art);pick.submitting(art);pick.presented(art)
	check(pick.state_calls==0,"ordinary frame hooks do not traverse character geometry")
	pick.request_query();pick.drawing(art);pick.submitting(art);pick.presented(art)
	check(pick.occludes(art,Vector2.ZERO) and not pick.last_uncertain,"actual command fill occludes")
	check(not pick.occludes(art,Vector2(8,0)),"clear geometry is clickable rather than a whole tile")
	node.position=Vector2(100,100);node.scale=Vector2(-3,3)
	check(pick.occludes(art,Vector2.ZERO) and pick.last_uncertain,"mutated unpresented character transform fails closed")
	present(pick,art,node)
	check(pick.occludes(art,Vector2(100,100)),"current parent position/mirror/zoom used")
	check(not pick.occludes(art,Vector2.ZERO),"previous screen position is not retained")
	shape.draw_arguments[1]=Color(1,1,1,.12)
	present(pick,art,node)
	check(not pick.occludes(art,Vector2(100,100)),"ground shadow alpha does not occlude")
	shape.draw_arguments[1]=Color.WHITE
	node.self_modulate.a=.1
	present(pick,art,node)
	check(not pick.occludes(art,Vector2(100,100)),"invisible modulation does not occlude")
	node.self_modulate=Color.WHITE;node.hide()
	present(pick,art,node)
	check(not pick.occludes(art,Vector2(100,100)),"hidden retained actor is excluded")
	node.show();node.contacts.clear()
	check(pick.occludes(art,Vector2(100,100)) and pick.last_uncertain,"pending native repaint receipt is blocked")
	node.contacts=[{"id":1}];node.generation=0
	check(pick.occludes(art,Vector2(100,100)) and pick.last_uncertain,"visible stale painter generation fails closed")
	node.generation=art.canvas_stream.frame_id;art.zoom=2
	check(pick.occludes(art,Vector2(100,100)) and pick.last_uncertain,"changed projection without completed draw blocked")
	pick.presented(art)
	check(pick.last_uncertain and pick.presented_projection[2]==1.0,"same idle frame cannot certify changed projection")
	present(pick,art,node)
	check(pick.occludes(art,Vector2(100,100)) and not pick.last_uncertain,"fresh frame certifies projection")
	art.canvas_stream.frame_id+=1;node.generation=art.canvas_stream.frame_id
	pick.request_query();pick.drawing(art);pick.submitting(art)
	node.position+=Vector2(1,0);pick.presented(art)
	check(pick.occludes(art,Vector2(100,100)) and pick.last_uncertain,"mutation between pre/post draw cannot certify completed image")
	present(pick,art,node)
	game.ground_mess_generation+=1
	check(pick.occludes(art,Vector2(100,100)) and pick.last_uncertain,"service restore invalidates receipt")
	present(pick,art,node)
	shape.draw_method=&"unsupported_painter_command"
	present(pick,art,node)
	check(pick.occludes(art,Vector2(100,100)) and pick.last_uncertain,"unknown primitive cannot silently permit click")
	game.modulate=Color(1,1,1,2)
	check(pick.occludes(art,Vector2(200,200)) and pick.last_uncertain,"unsupported ancestor modulation fails closed")
	game.modulate=Color.WHITE
	var image=Image.create(8,8,false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT)
	image.set_pixel(4,4,Color.WHITE);var texture=ImageTexture.create_from_image(image)
	var args=[texture,Rect2(0,0,8,8),Rect2(0,0,8,8),Color.WHITE,false,true]
	check(pick.command_hit(&"draw_texture_rect_region",args,Vector2(4.5,4.5),1,Transform2D.IDENTITY,null,{})==Pick.HIT,"painted texture alpha occludes")
	check(pick.command_hit(&"draw_texture_rect_region",args,Vector2(1.5,1.5),1,Transform2D.IDENTITY,null,{})==Pick.CLEAR,"transparent texture rectangle is not a silhouette")
	var points=PackedVector2Array([Vector2(0,0),Vector2(10,0),Vector2(0,10)])
	var colors=PackedColorArray([Color.WHITE,Color.TRANSPARENT,Color.TRANSPARENT])
	check(pick.command_hit(&"draw_polygon",[points,colors,PackedVector2Array(),null],Vector2(1,1),1,Transform2D.IDENTITY,null,{})==Pick.HIT,"vertex alpha interpolates opaque core")
	check(pick.command_hit(&"draw_polygon",[points,colors,PackedVector2Array(),null],Vector2(8,1),1,Transform2D.IDENTITY,null,{})==Pick.CLEAR,"transparent triangle feather excluded")
	check(pick.command_hit(&"draw_line",[Vector2.ZERO,Vector2(10,0),Color.WHITE,2.0,true],Vector2(5,0),1,Transform2D.IDENTITY,null,{})==Pick.HIT,"native line core occludes")
	check(pick.command_hit(&"draw_line",[Vector2.ZERO,Vector2(10,0),Color.WHITE,2.0,true],Vector2(5,4),1,Transform2D.IDENTITY,null,{})==Pick.CLEAR,"line does not claim distant floor")
	# Compare the new far-point rejection against the existing native AA quads,
	# including thin widths and diagonal end/side feathers near the alpha cutoff.
	for width in [.1,1.0,2.0,6.0]:
		var stroke=preload("res://scripts/retained_aa_strokes.gd").new()
		stroke.add_line(Vector2.ZERO,Vector2(10,10),Color.WHITE,width)
		for point in [Vector2(-.5,-.5),Vector2(0,2),Vector2(5,6),Vector2(10.5,10.5),Vector2(20,20)]:
			var reference=pick._triangles_hit(stroke.vertices,stroke.colors,stroke.indices,point,1)
			check(pick.command_hit(&"draw_line",[Vector2.ZERO,Vector2(10,10),Color.WHITE,width,true],point,1,Transform2D.IDENTITY,null,{})==reference,"AA broad rejection preserves exact native quads "+str(width)+" "+str(point))
	pick.request_query()
	var before_calls=pick.state_calls
	for frame in 8:
		art.canvas_stream.frame_id+=1;node.generation=art.canvas_stream.frame_id
		pick.drawing(art);pick.submitting(art);pick.presented(art)
	check(pick.state_calls-before_calls==4,"one query certifies at most two submitted/completed frames")
	pick.query_deadline=Time.get_ticks_msec()-1
	before_calls=pick.state_calls;pick.submitting(art);pick.presented(art)
	check(pick.state_calls==before_calls and pick.occludes(art,Vector2.ZERO) and pick.last_uncertain,"expired query does no traversal and fails closed")
	pick.close_query();pick.submitting(art);pick.presented(art)
	check(pick.state_calls==before_calls and pick.presented_frame==-1,"cancel invalidates receipt and disables deep frame work")
	print("CHARACTER_PICK_GEOMETRY_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"synthetic_commands_only":true,"native_render_verified":false,"player_save_used":false}))
	quit(0 if failures.is_empty() else 1)
