extends SceneTree
class CountingShape extends "res://scripts/cafe_shape_2d.gd":
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
	await settle()
	check(shape.draws==1,"initial native draw recorded once")
	var unchanged=PackedVector2Array([Vector2(10,10),Vector2(40,10),Vector2(40,40),Vector2(10,40)])
	shape.configure(&"draw_colored_polygon",[unchanged,Color.WHITE],Transform2D(0,Vector2(20,30)))
	unchanged.append(unchanged[0])
	await settle()
	check(shape.draws==1,"same fill and moved transform retain native commands")
	var changed=PackedVector2Array([Vector2(10,10),Vector2(45,10),Vector2(40,40),Vector2(10,40)])
	shape.configure(&"draw_colored_polygon",[changed,Color.WHITE],Transform2D.IDENTITY)
	changed[1]=Vector2(90,10)
	await settle()
	check(shape.draws==2,"actual geometry change redraws once")
	check(shape.draw_arguments[0][1]==Vector2(45,10),"later edits cannot change submitted geometry")
	var colors=PackedColorArray([Color.WHITE]);var uvs=PackedVector2Array([Vector2.ZERO])
	var texture=ImageTexture.new()
	shape.configure(&"draw_polygon",[changed,colors,uvs,texture],Transform2D.IDENTITY)
	colors[0]=Color.RED;uvs[0]=Vector2.ONE
	check(shape.draw_arguments[1][0]==Color.WHITE,"color array has independent ownership")
	check(shape.draw_arguments[2][0]==Vector2.ZERO,"UV array has independent ownership")
	check(shape.draw_arguments[3]==texture,"texture resource is retained without duplication")
	shape.free()
	print("NATIVE_SHAPE_RETENTION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
