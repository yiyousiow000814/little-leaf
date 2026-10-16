extends SceneTree
const Pick=preload("res://scripts/rendering/cafe_character_pick_geometry.gd")
const Native=preload("res://scripts/rendering/cafe_native_draw_node.gd")
const Shape=preload("res://scripts/rendering/cafe_shape_2d.gd")
class CountingPick extends Pick:
	var state_calls=0
	var node_visits=0
	func _node_state(node:Node2D,state:int)->int:
		node_visits+=1
		return super._node_state(node,state)
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
	var native_world_shapes={}
	var ground_occlusion_start=0
	var ground_occlusion_end=1
	var use_native_object_nodes=true
	var origin=Vector2.ZERO
	var tile=Vector2(39,19.5)
	var zoom=1.0
	var ui_scale=1.0
	var pan_offset=Vector2.ZERO
	var alpha_revision=0
	func ground_hit_alpha_state()->Array:return [alpha_revision]
func _initialize():run.call_deferred()
func check(value,label):
	checks+=1
	if not value:failures.append(label);printerr("FAIL ",label)
func fixture_painted(node):
	# Synthetic command test ONLY, not a claim that Godot presented these pixels.
	node.painted_revision=node.paint_revision
	if node.get_script()==Native:
		for child in node.shapes:fixture_painted(child)
func present(pick,art,_node):
	art.canvas_stream.frame_id+=1
	for node in art.native_object_nodes.values():
		node.generation=art.canvas_stream.frame_id;fixture_painted(node)
	for node in art.native_world_shapes.values():
		node.set_meta("generation",art.canvas_stream.frame_id);fixture_painted(node)
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
	check(pick.state_calls==0,"ordinary frame hooks do not traverse world geometry")
	fixture_painted(node)
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
		var stroke=preload("res://scripts/rendering/retained_aa_strokes.gd").new()
		stroke.add_line(Vector2.ZERO,Vector2(10,10),Color.WHITE,width)
		for point in [Vector2(-.5,-.5),Vector2(0,2),Vector2(5,6),Vector2(10.5,10.5),Vector2(20,20)]:
			var reference=pick._triangles_hit(stroke.vertices,stroke.colors,stroke.indices,point,1)
			check(pick.command_hit(&"draw_line",[Vector2.ZERO,Vector2(10,10),Color.WHITE,width,true],point,1,Transform2D.IDENTITY,null,{})==reference,"AA broad rejection preserves exact native quads "+str(width)+" "+str(point))
	hidden_subtree_cases(pick,art,node,shape)
	world_span_cases(pick,art,node,texture)
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

func world_span_cases(pick,art,actor,texture):
	actor.hide()
	# Fixed points, not a search for any point the production picker accepts.
	# A small table top and separate leg leave (8, 0) clear inside the old box.
	var furniture=Native.new();art.add_child(furniture)
	furniture.appearance=[["furniture","item",{"kind":"table"}]]
	art.native_object_nodes[1]=furniture;art.ground_occlusion_end=5
	var top=Shape.new();furniture.add_child(top);furniture.shapes.append(top)
	top.configure(&"draw_rect",[Rect2(-10,-12,20,4),Color.WHITE,true,-1.0,false],Transform2D.IDENTITY)
	var leg=Shape.new();furniture.add_child(leg);furniture.shapes.append(leg)
	leg.configure(&"draw_rect",[Rect2(-2,-8,4,12),Color.WHITE,true,-1.0,false],Transform2D.IDENTITY)
	present(pick,art,actor)
	check(not pick.occludes(art,Vector2(8,0)),"fixed exposed floor beside table leg is not blocked by furniture rectangle")
	check(pick.occludes(art,Vector2(0,0)) and not pick.last_uncertain,"painted table leg blocks the neighboring fixed point")
	check(pick.occludes(art,Vector2(8,-10)),"painted table top still blocks floor litter")
	furniture.position=Vector2(100,50);furniture.scale=Vector2(-2,2)
	present(pick,art,actor)
	check(not pick.occludes(art,Vector2(84,50)) and pick.occludes(art,Vector2(100,50)),"translated mirrored scaled furniture uses current painted geometry")
	furniture.paint_revision+=1
	pick.drawing(art);pick.submitting(art);pick.presented(art)
	check(pick.occludes(art,Vector2(84,50)) and pick.last_uncertain,"requested furniture art cannot certify old retained paint")
	present(pick,art,actor)
	furniture.hide()
	# Two actual wall panels, no fabricated full-host face over their opening.
	for order in [2,3]:
		var wall=Shape.new();art.add_child(wall);art.native_world_shapes[order]=wall
		wall.configure(&"draw_rect",[Rect2(-10 if order==2 else 5,-10,5,20),Color.WHITE,true,-1.0,false],Transform2D.IDENTITY)
	present(pick,art,actor)
	check(not pick.occludes(art,Vector2.ZERO),"fixed doorway aperture stays clear between painted wall panels")
	check(pick.occludes(art,Vector2(-8,0)),"painted wall panel blocks adjacent floor")
	var wall=art.native_world_shapes[2];wall.paint_revision+=1
	pick.drawing(art);pick.submitting(art);pick.presented(art)
	check(pick.occludes(art,Vector2.ZERO) and pick.last_uncertain,"unpainted world shape fails closed")
	present(pick,art,actor)
	wall.hide();art.native_world_shapes[3].hide()
	# Ground rugs/effects before the span and editing overlays after it cannot
	# steal cleanup. An identical shape in the world span must block.
	for order in [-1,4,5]:
		var layer=Shape.new();art.add_child(layer);art.native_world_shapes[order]=layer
		layer.configure(&"draw_rect",[Rect2(-4,-4,8,8),Color.WHITE,true,-1.0,false],Transform2D.IDENTITY)
	art.native_world_shapes[4].hide();present(pick,art,actor)
	check(not pick.occludes(art,Vector2.ZERO),"ground and editor passes are excluded by half-open painter span")
	art.native_world_shapes[4].show();present(pick,art,actor)
	check(pick.occludes(art,Vector2.ZERO),"same painted shape in world span blocks")
	art.native_world_shapes[4].self_modulate.a=.12;present(pick,art,actor)
	check(not pick.occludes(art,Vector2.ZERO),"world shadow alpha does not cover litter")
	# Atlas/pattern alpha, including textured mesh limbs, uses UVs only inside
	# actual triangles. An unrelated textured object cannot veto all clicks.
	var quad=PackedVector2Array([Vector2.ZERO,Vector2(8,0),Vector2(8,8),Vector2(0,8)])
	var uv=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN])
	var args=[quad,PackedColorArray([Color.WHITE]),uv,texture]
	check(pick.command_hit(&"draw_polygon",args,Vector2(20,20),1,Transform2D.IDENTITY,null,{})==Pick.CLEAR,"distant textured wall does not globally reject a click")
	check(pick.command_hit(&"draw_polygon",args,Vector2(1.5,1.5),1,Transform2D.IDENTITY,null,{})==Pick.CLEAR,"transparent textured polygon is clear")
	check(pick.command_hit(&"draw_polygon",args,Vector2(4.5,4.5),1,Transform2D.IDENTITY,null,{})==Pick.HIT,"opaque textured polygon is covered")
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=quad;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3])
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	args=[mesh,texture,Transform2D.IDENTITY,Color.WHITE]
	check(pick.command_hit(&"draw_mesh",args,Vector2(20,20),1,Transform2D.IDENTITY,null,{})==Pick.CLEAR,"distant textured mesh does not globally reject a click")
	check(pick.command_hit(&"draw_mesh",args,Vector2(1.5,1.5),1,Transform2D.IDENTITY,null,{})==Pick.CLEAR,"textured mesh transparent padding stays clear")
	check(pick.command_hit(&"draw_mesh",args,Vector2(4.5,4.5),1,Transform2D.IDENTITY,null,{})==Pick.HIT,"textured mesh opaque triangle blocks")
	for node in art.native_world_shapes.values():node.queue_free()
	art.native_world_shapes.clear();art.native_object_nodes.erase(1);furniture.queue_free()
	art.ground_occlusion_end=1
	# A completed fallback frame has no retained world span. Even with matching
	# projection/state receipts and no visible native nodes it cannot mean clear.
	art.ground_occlusion_start=-1;art.ground_occlusion_end=-1
	present(pick,art,actor)
	check(pick.occludes(art,Vector2.ZERO) and pick.last_uncertain,"completed immediate-painter fallback without native span fails closed")
	art.ground_occlusion_start=0;art.ground_occlusion_end=1

func hidden_subtree_cases(pick,art,node,shape):
	var hidden=Native.new();node.add_child(hidden);node.shapes.append(hidden)
	var inactive=Shape.new();hidden.add_child(inactive);hidden.shapes.append(inactive)
	inactive.configure(&"draw_rect",[Rect2(0,0,20,20),Color.WHITE,true,-1.0,false],Transform2D.IDENTITY)
	hidden.hide();node.show()
	shape.configure(&"draw_rect",[Rect2(200,200,5,5),Color.WHITE,true,-1.0,false],Transform2D.IDENTITY)
	present(pick,art,node)
	pick.node_visits=0;var state=pick._state(art)
	check(pick.node_visits==3,"hidden subtree hashes only its visibility marker, not descendants")
	inactive.draw_arguments[0]=Rect2(-100,-100,200,200)
	hidden.position=Vector2(70,70)
	check(pick._state(art)==state,"inactive geometry and transforms cannot dirty a hidden subtree receipt")
	hidden.show()
	check(pick.occludes(art,Vector2.ZERO) and pick.last_uncertain,"revealing hidden subtree invalidates an already completed receipt")
	present(pick,art,node)
	inactive.draw_arguments[1]=Color(1,1,1,.5)
	check(pick.occludes(art,Vector2.ZERO) and pick.last_uncertain,"visible payload mutation still invalidates without a revision-counter shortcut")
	hidden.hide();present(pick,art,node)
	art.canvas_stream.frame_id+=1;node.generation=art.canvas_stream.frame_id
	pick.request_query();pick.drawing(art);pick.submitting(art);hidden.show();pick.presented(art)
	check(pick.occludes(art,Vector2.ZERO) and pick.last_uncertain,"hidden-to-visible mutation between submit and present fails closed")
	hidden.hide();present(pick,art,node)
	art.alpha_revision+=1
	check(pick.occludes(art,Vector2.ZERO) and pick.last_uncertain,"atlas alpha invalidation rejects a previous presentation receipt")
	node.shapes.erase(hidden);hidden.queue_free()
