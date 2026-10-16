extends SceneTree
const Native=preload("res://scripts/rendering/cafe_native_draw_node.gd")
class Artist extends Node2D:
	var opacity=1.0
	func paint_native_object(target,callback):callback.call(target)
	func paint_test_shape(target):target.submit_shape(&"draw_rect",[Rect2(0,0,4,4),Color.WHITE,true,-1.0,false],Transform2D.IDENTITY)
class CountingShape extends "res://scripts/rendering/cafe_shape_2d.gd":
	var draws=0
	func _draw():
		draws+=1
		super._draw()
var checks=0
var failures=[]
func check(condition:bool,label:String):
	checks+=1
	if not condition:failures.append(label);printerr("FAIL ",label)
func _init():run.call_deferred()
func settle():
	for frame in 3:await process_frame
func run():
	var shape=CountingShape.new();root.add_child(shape)
	var points=PackedVector2Array([Vector2(10,10),Vector2(40,10),Vector2(40,40),Vector2(10,40)])
	shape.configure(&"draw_colored_polygon",[points,Color.WHITE],Transform2D.IDENTITY)
	points.append(points[0])
	check(shape.draw_arguments[0].size()==4,"outline closure cannot mutate cached fill")
	check(shape.paint_revision==1 and shape.painted_revision==-1,"new commands are not yet painted")
	await settle()
	check(shape.draws==1,"initial native draw recorded once")
	check(shape.painted_revision==shape.paint_revision,"native draw records completed command revision")
	var unchanged=PackedVector2Array([Vector2(10,10),Vector2(40,10),Vector2(40,40),Vector2(10,40)])
	shape.configure(&"draw_colored_polygon",[unchanged,Color.WHITE],Transform2D(0,Vector2(20,30)))
	unchanged.append(unchanged[0])
	await settle()
	check(shape.draws==1,"same fill and moved transform retain native commands")
	check(shape.paint_revision==1 and shape.painted_revision==1,"transform-only movement retains the completed paint receipt")
	var changed=PackedVector2Array([Vector2(10,10),Vector2(45,10),Vector2(40,40),Vector2(10,40)])
	shape.configure(&"draw_colored_polygon",[changed,Color.WHITE],Transform2D.IDENTITY)
	changed[1]=Vector2(90,10)
	check(shape.paint_revision==2 and shape.painted_revision==1,"changed geometry invalidates receipt until native draw")
	await settle()
	check(shape.draws==2,"actual geometry change redraws once")
	check(shape.painted_revision==2,"changed geometry gets a new completed receipt")
	check(shape.draw_arguments[0][1]==Vector2(45,10),"later edits cannot change submitted geometry")
	var colors=PackedColorArray([Color.WHITE]);var uvs=PackedVector2Array([Vector2.ZERO])
	var texture=ImageTexture.new()
	shape.configure(&"draw_polygon",[changed,colors,uvs,texture],Transform2D.IDENTITY)
	colors[0]=Color.RED;uvs[0]=Vector2.ONE
	check(shape.draw_arguments[1][0]==Color.WHITE,"color array has independent ownership")
	check(shape.draw_arguments[2][0]==Vector2.ZERO,"UV array has independent ownership")
	check(shape.draw_arguments[3]==texture,"texture resource is retained without duplication")
	shape.free()
	var artist=Artist.new();root.add_child(artist)
	var object=Native.new();artist.add_child(object)
	object.configure(artist,artist.paint_test_shape,[["test-furniture"]],Transform2D.IDENTITY)
	check(object.paint_revision==1 and object.painted_revision==-1,"native object appearance is pending before painting")
	await settle()
	check(object.paint_revision==object.painted_revision and object.draw_count==1,"native object callback completes its paint receipt")
	object.configure(artist,artist.paint_test_shape,[["test-furniture"]],Transform2D(0,Vector2(15,20)))
	await settle()
	check(object.paint_revision==1 and object.painted_revision==1 and object.draw_count==1,"native object movement neither invalidates art nor repaints it")
	object.configure(artist,artist.paint_test_shape,[["test-furniture","changed"]],Transform2D.IDENTITY)
	check(object.paint_revision==2 and object.painted_revision==1,"native appearance change invalidates completed art")
	await settle()
	check(object.painted_revision==2 and object.draw_count==2,"changed native appearance completes one new draw")
	artist.free()
	print("NATIVE_SHAPE_RETENTION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
