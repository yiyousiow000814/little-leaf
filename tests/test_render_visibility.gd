extends SceneTree
const Visibility=preload("res://scripts/cafe_render_visibility.gd")
const Art=preload("res://scripts/illustrated_cafe.gd")
const Neighborhood=preload("res://scripts/exterior_environment.gd")
const Greenery=preload("res://scripts/environment_greenery.gd")
class Recorder extends RefCounted:
	var origin=Vector2.ZERO
	var ui_scale=1.0
	var zoom=1.0
	var detail=1.0
	var viewport=Rect2(0,0,390,844)
	var culling=true
	var commands=[]
	var callbacks=0
	func iso(x,z,h=0.0):return origin+Vector2((x-z)*39,(x+z)*19.5)*ui_scale*zoom*detail-Vector2(0,h*ui_scale*zoom*detail)
	func get_viewport_rect():return viewport
	func render_bounds_visible(bounds):return not culling or Visibility.visible(bounds,viewport,6)
	func record(kind,bounds,data):commands.append({"bounds":bounds,"key":str([kind,data])})
	func poly(points,color):record("poly",Visibility.points_bounds(points),[points,color])
	func rounded_poly(points,r,color):record("rounded",Visibility.points_bounds(points),[points,r,color])
	func ellipse(p,size,color):record("ellipse",Rect2(p-size,size*2),[p,size,color])
	func line(a,b,color,width=1.0):record("line",Rect2(a,Vector2.ZERO).expand(b).grow(width*.5),[a,b,color,width])
	func draw_rect(rect,color):record("rect",rect,[rect,color])
	func callback():callbacks+=1
class BoundsArt extends "res://scripts/illustrated_cafe.gd":
	var points=[]
	func _face_line(a:Vector2,b:Vector2,c,width=1.0):line(a,b,c,width)
	func _face_ellipse(at:Vector2,radius:Vector2,c):ellipse(at,radius,c)
	func poly(shape:Array,_color):points.append_array(shape)
	func rounded_poly(shape:Array,_radius:float,_color):points.append_array(shape)
	func line(a:Vector2,b:Vector2,_color,width=1.0):points.append(a-Vector2.ONE*width);points.append(a+Vector2.ONE*width);points.append(b-Vector2.ONE*width);points.append(b+Vector2.ONE*width)
	func art_polyline(shape:PackedVector2Array,_color:Color,width:float):
		for point in shape:points.append(point-Vector2.ONE*width);points.append(point+Vector2.ONE*width)
	func ellipse(at:Vector2,radius:Vector2,_color):points.append(at-radius);points.append(at+radius)
	func outlined_ellipse(at:Vector2,radius:Vector2,_color,_edge,width=1.0):points.append(at-radius-Vector2.ONE*width);points.append(at+radius+Vector2.ONE*width)
var checks=0
var failures=[]
func check(ok,label):
	checks+=1
	if not ok and failures.size()<20:failures.append(label);push_error(label)
func visible_keys(commands,viewport):
	var result=[]
	for command in commands:
		if Visibility.visible(command.bounds,viewport,2):result.append(command.key)
	return result
func _initialize():_run_checks.call_deferred()
func _run_checks():
	var view=Rect2(0,0,390,844)
	for margin in [0.0,6.0,20.0]:
		check(Visibility.visible(Rect2(390,100,0,10),view,margin),"edge-touch stays visible")
		check(Visibility.visible(Rect2(Vector2.INF,Vector2.ONE),view,margin),"unknown bounds fail open")
		check(not Visibility.visible(Rect2(2000,2000,100,100),view,margin),"far offscreen omitted")
		check(Visibility.visible(Rect2(-50,-50,500,950),view,margin),"covering viewport retained")
	var art=Art.new();root.add_child(art);art.set_process(false)
	check(art.render_bounds_visible(Rect2(2000,2000,100,100)),"standalone artists fail open")
	art.icon_kind="chair"
	check(art.render_bounds_visible(Rect2(2000,2000,100,100)),"icons fail open")
	art.queue_free();await process_frame

	var art_bounds=BoundsArt.new();art_bounds.use_cached_heads=false;art_bounds.use_cached_moving_art=false;art_bounds.furniture_art.cache_enabled=false
	for kind in ["counter","stove","beverage","sink","bookshelf","bench","divider","rug","table","chair","plant","lamp","register","bin"]:
		for rotation in 4:
			art_bounds.points=[];art_bounds.item(kind,Vector2.ZERO,rotation,0)
			if kind=="chair":art_bounds._chair(Vector2.ZERO,rotation,true)
			for point in art_bounds.points:check(Rect2(-128,-192,256,272).has_point(point),"furniture guard contains %s rotation %s"%[kind,rotation])
	art_bounds.free()
	var recorder=Recorder.new();var greenery=Greenery.new();var removed=0
	for viewport in [Rect2(0,0,390,844),Rect2(0,0,1360,880),Rect2(0,0,844,390)]:
		recorder.viewport=viewport
		for scale in [.25,.5,1.0,2.0,4.0]:
			recorder.zoom=scale
			for detail in [1.0,1.55]:
				recorder.detail=detail
				for origin in [Vector2.ZERO,Vector2(390,250),Vector2(-1100,-700),Vector2(1800,1200),Vector2(0,880),Vector2(1360,0)]:
					recorder.origin=origin
					for subject in ["car_front","car_back","bus","shelter","ground","airy","columnar","sapling","pocket0","pocket1","pocket2"]:
						var baseline=[]
						for culling in [false,true]:
							recorder.culling=culling;recorder.commands=[];recorder.callbacks=0
							match subject:
								"car_front":Neighborhood.draw_car(recorder,Vector2(4.2,-7.15),1,"a2b3b3")
								"car_back":Neighborhood.draw_car(recorder,Vector2(-4.65,6),-1,"ddcdb0")
								"bus":Neighborhood.draw_bus(recorder,Neighborhood.BUS_POSITION)
								"shelter":Neighborhood.draw_shelter(recorder,recorder.callback)
								"ground":Neighborhood.draw_ground(recorder)
								"airy","columnar","sapling":greenery.draw_tree(recorder,recorder.iso(7.7,14),scale*detail,subject)
								_:greenery.draw_pocket(recorder,Vector2(2.5,-3.35),int(subject.right(1)))
							if subject=="shelter":check(recorder.callbacks==1,"shelter callback preserved")
							if not culling:baseline=recorder.commands.duplicate()
							else:
								check(visible_keys(baseline,viewport)==visible_keys(recorder.commands,viewport),"visible command parity %s %s %s %s"%[subject,viewport,scale,origin])
								removed+=baseline.size()-recorder.commands.size()
	check(removed>0,"offscreen geometry is omitted")
	check(Visibility.visible(Rect2(390,100,0,10),Rect2(0,0,390,844)),"edge-touch stays visible")
	check(Visibility.visible(Rect2(Vector2.INF,Vector2.ONE),Rect2(0,0,390,844)),"unknown bounds fail open")
	print("RENDER_VISIBILITY_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"omitted_commands":removed}));quit(0 if failures.is_empty() else 1)
