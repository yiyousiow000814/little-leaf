extends RefCounted
## Draw litter above its saved ground footprint, which drives cleanup contact.
const Geometry=preload("res://scripts/cafe_floor_geometry.gd")

static func _screen(art,point:Vector2)->Vector2:return art.iso(point.x,point.y)

static func _project(art,points:Array)->Array:
	var result=[]
	for point in points:result.append(_screen(art,point))
	return result

static func draw(art,record:Dictionary):
	var shape=art.game.floor_tasks.geometry.ensure(record)
	var unit=art.ui_scale*art.zoom*(1.55 if art.game.wall_detail else 1.0)
	if bool(record.get("floor_spill",false)) and not bool(record.get("spill_cleaned",false)):
		var remaining=clampf(float(record.get("spill_remaining",1.0)),0,1)
		if remaining>.001 and not shape.spill_outline.is_empty():
			# Opacity recedes while the saved perimeter stays fixed, keeping the
			# mop's near-edge contact coherent throughout the wiping gesture.
			art.poly(_project(art,shape.spill_outline),Color(.36,.54,.54,.58*remaining))
			var a:Vector2=shape.spill_outline[2].lerp(shape.center,.56)
			var b:Vector2=shape.spill_outline[5].lerp(shape.center,.56)
			art.line(_screen(art,a),_screen(art,b),Color(.85,.93,.87,.8*remaining),1.15*unit)
			var c:Vector2=shape.spill_outline[10].lerp(shape.center,.38)
			art.ellipse(_screen(art,c),Vector2(2.3,.8)*unit,Color(.83,.92,.86,.55*remaining))
	if str(record.get("trash_owner","none"))!="floor":return
	for piece in shape.pieces:_draw_dry_piece(art,piece,unit)

static func _soften(points:Array,cut:float=.18)->Array:
	# Trim corners within the saved conservative hull; never move a saved piece.
	var result=[]
	for i in range(points.size()):
		var here:Vector2=points[i]
		result.append(here.lerp(points[posmod(i-1,points.size())],cut))
		result.append(here.lerp(points[(i+1)%points.size()],cut))
	return result

static func _face(art,piece:Dictionary,points:Array,color,soft:bool=false):
	var world=[]
	for point in points:world.append(piece.center+(point*float(piece.size)).rotated(float(piece.angle)))
	art.poly(_project(art,_soften(world) if soft else world),color)

# Raised folds affect only illustration height. Their ground projection stays
# inside the same saved footprint used for reach, collision and mop/sweep contact.
static func _raised(art,piece:Dictionary,vertices:Array)->Array:
	var result=[]
	for vertex in vertices:
		var ground=piece.center+(Vector2(vertex.x,vertex.y)*float(piece.size)).rotated(float(piece.angle))
		result.append(art.iso(ground.x,ground.y,vertex.z*float(piece.size)))
	return result

static func _surface(art,piece:Dictionary,vertices:Array,color,unit:float,edge="",smooth:bool=false):
	var points=_raised(art,piece,vertices)
	var footprint=[]
	for vertex in vertices:footprint.append(Vector2(vertex.x,vertex.y))
	if smooth:points=_soften(points,.12);footprint=_soften(footprint,.12)
	# A curl can fold over itself in screen space. Tessellate its ground mesh
	# before lifting, as with a small 3D surface, instead of an invalid 2D loop.
	if not Geometry2D.triangulate_polygon(PackedVector2Array(points)).is_empty():
		art.poly(points,color)
	else:
		var triangles=Geometry2D.triangulate_polygon(PackedVector2Array(footprint))
		for i in range(0,triangles.size(),3):
			var a:Vector2=points[triangles[i]];var b:Vector2=points[triangles[i+1]];var c:Vector2=points[triangles[i+2]]
			if absf((b-a).cross(c-a))>.001*unit*unit and not Geometry2D.triangulate_polygon(PackedVector2Array([a,b,c])).is_empty():art.poly([a,b,c],color)
	if edge!="":
		for i in range(points.size()):art.line(points[i],points[(i+1)%points.size()],edge,.72*unit*float(piece.size))

static func _draw_dry_piece(art,piece:Dictionary,unit:float):
	match str(piece.kind):
		"banana":
			var paint=piece.duplicate();paint.size=float(piece.size)*.92
			# The contact shadow sits under the skin, not under its whole planning hull.
			_face(art,paint,[Vector2(-.22,.057),Vector2(-.13,.022),Vector2(.10,.020),Vector2(.24,.06),Vector2(.15,.110),Vector2(-.14,.126)],Color(.48,.42,.28,.10),true)
			_draw_banana(art,paint,unit)
		"paper":
			# Match the game's warm paper/ceramic whites and low, soft fold values.
			_surface(art,piece,[Vector3(-.187,-.111,0),Vector3(.077,-.164,0),Vector3(.196,-.047,1),Vector3(.140,.145,0),Vector3(-.156,.113,0),Vector3(-.117,.003,0)],"d4c7a7",unit)
			_surface(art,piece,[Vector3(-.177,-.101,.3),Vector3(.073,-.154,.3),Vector3(.180,-.044,1),Vector3(.130,.133,.3),Vector3(-.144,.105,.3),Vector3(-.108,.003,.3)],"faf0d8",unit)
			_surface(art,piece,[Vector3(.012,-.018,1.6),Vector3(.180,-.044,1),Vector3(.130,.133,.3)],"eee3c7",unit)
			_surface(art,piece,[Vector3(.073,-.154,.3),Vector3(.180,-.044,1),Vector3(.063,-.065,2)],"e3d7b8",unit)
		"bag":
			# The existing crumbs slot keeps its saved kind/footprint. Paint remnants
			# of the rice/cutlet lunch already served by IllustratedCafe._plate.
			_draw_meal_remnants(art,piece,unit)
		_:
			_face(art,piece,[Vector2(-.052,-.019),Vector2(-.020,-.052),Vector2(.054,-.013),Vector2(.041,.036),Vector2(-.032,.032)],"aa895d",true)
			_face(art,piece,[Vector2(-.031,-.019),Vector2(-.012,-.039),Vector2(.041,-.011),Vector2(.003,.009)],"d5a362",true)

static func _draw_meal_remnants(art,piece:Dictionary,unit:float):
	# Larger uneven lunch remnants stay within the saved cleanup hull. The
	# cutlet's warm brown values separate them from pale tiles without an outline.
	_surface(art,piece,[Vector3(-0.1457,-0.0057,0),Vector3(-0.107,-0.0592,0),Vector3(-0.0103,-0.0501,0),Vector3(0.0272,0.0102,0),Vector3(-0.0524,0.0477,0)],"946b46",unit,"",true)
	_surface(art,piece,[Vector3(-0.1366,-0.008,0.728),Vector3(-0.1036,-0.0501,1.183),Vector3(-0.0149,-0.0433,1.092),Vector3(0.0147,0.0045,0.546),Vector3(-0.0547,0.0375,0.455)],"aa7548",unit,"",true)
	_surface(art,piece,[Vector3(-0.1036,-0.0501,1.183),Vector3(-0.0149,-0.0433,1.092),Vector3(-0.0365,-0.0068,1.274),Vector3(-0.1013,-0.0012,1.274)],"d5a362",unit,"",true)
	_surface(art,piece,[Vector3(0.0701,0.1127,0),Vector3(0.1017,0.0622,0),Vector3(0.1727,0.0733,0),Vector3(0.1881,0.1169,0),Vector3(0.1368,0.1494,0)],"946b46",unit,"",true)
	_surface(art,piece,[Vector3(0.0795,0.1101,0.378),Vector3(0.1043,0.0716,0.63),Vector3(0.1667,0.0802,0.504),Vector3(0.177,0.1127,0.315),Vector3(0.1342,0.14,0.252)],"aa7548",unit,"",true)
	_surface(art,piece,[Vector3(0.1043,0.0716,0.63),Vector3(0.1667,0.0802,0.504),Vector3(0.1428,0.1015,0.693),Vector3(0.1026,0.0964,0.693)],"d5a362",unit,"",true)
	# Cream grains reuse the rice and subtle warm underside from the plated meal.
	_surface(art,piece,[Vector3(-0.1935,0.0548,0),Vector3(-0.1875,0.0435,0),Vector3(-0.1057,0.0735,0),Vector3(-0.1118,0.0877,0)],"ad9670",unit,"",true)
	_surface(art,piece,[Vector3(-0.1875,0.0518,0.4375),Vector3(-0.1808,0.048,0.5),Vector3(-0.111,0.0742,0.4375),Vector3(-0.1163,0.0825,0.3125)],"fff5da",unit,"",true)
	_surface(art,piece,[Vector3(0.007,-0.1179,0),Vector3(0.0152,-0.1295,0),Vector3(0.0722,-0.1047,0),Vector3(0.0639,-0.089,0)],"ad9670",unit,"",true)
	_surface(art,piece,[Vector3(0.0136,-0.1138,0.4125),Vector3(0.0194,-0.1237,0.55),Vector3(0.0664,-0.1047,0.4125),Vector3(0.0606,-0.0948,0.3438)],"fff5da",unit,"",true)

	_surface(art,piece,[Vector3(0.1146,-0.0414,0),Vector3(0.1308,-0.0683,0),Vector3(0.1794,-0.0319,0),Vector3(0.1632,-0.0116,0)],"ad9670",unit,"",true)
	_surface(art,piece,[Vector3(0.1227,-0.04,0.4375),Vector3(0.1322,-0.0576,0.625),Vector3(0.1713,-0.0292,0.4375),Vector3(0.1618,-0.0198,0.3125)],"fff5da",unit,"",true)

static func _cubic_outline(start:Vector3,curves:Array)->Array:
	var points=[start];var previous=start
	for curve in curves:
		for step in range(1,7):
			var t=step/6.0;var u=1.0-t
			points.append(previous*u*u*u+curve[0]*3.0*u*u*t+curve[1]*3.0*u*t*t+curve[2]*t*t*t)
		previous=curve[2]
	return points

static func _draw_banana(art,piece:Dictionary,unit:float):
	# Original shape study: a joined skin neck opens into broad, drooping
	# ribbons. The small stalk is skin, never a pale piece of exposed fruit.
	var skin=_cubic_outline(Vector3(-0.06448,-0.13,12.48000),[
		[Vector3(-0.04459,-0.145,12.48000),Vector3(0.00104,-0.145,12.48000),Vector3(0.00221,-0.128,12.48000)],
		[Vector3(-0.00822,-0.091,9.36000),Vector3(0.07279,-0.037,8.11200),Vector3(0.0862,0.002,5.46000)],
		[Vector3(0.124,0.061,0.78000),Vector3(0.218,0.096,1.56000),Vector3(0.264,0.065,3.90000)],
		[Vector3(0.29,0.071,4.68000),Vector3(0.278,0.085,3.12000),Vector3(0.254,0.099,2.34000)],
		[Vector3(0.18,0.138,0.00000),Vector3(0.113,0.092,0.00000),Vector3(0.056,0.043,2.34000)],
		[Vector3(0.051,0.078,1.56000),Vector3(0.082,0.123,0.78000),Vector3(0.12,0.129,1.56000)],
		[Vector3(0.113,0.144,0.00000),Vector3(0.069,0.145,0.00000),Vector3(0.031,0.121,0.78000)],
		[Vector3(-0.004,0.096,1.56000),Vector3(-0.028,0.052,3.12000),Vector3(-0.041,0.028,4.68000)],
		[Vector3(-0.105,0.113,0.00000),Vector3(-0.208,0.157,0.46800),Vector3(-0.264,0.103,2.34000)],
		[Vector3(-0.273,0.087,2.80800),Vector3(-0.261,0.081,2.34000),Vector3(-0.246,0.089,1.87200)],
		[Vector3(-0.161,0.116,0.46800),Vector3(-0.079,0.044,2.34000),Vector3(-0.08723,-0.012,6.86400)],
		[Vector3(-0.08778,-0.058,9.36000),Vector3(-0.04755,-0.092,9.98400),Vector3(-0.06448,-0.13,12.48000)]])
	# The low neck leans slightly; unequal curl heights keep the skin relaxed.
	_surface(art,piece,skin,"d8b967",unit,"")
	# Back/right ribbon, a shallow shadow at the throat and a pale turned edge.
	_surface(art,piece,_cubic_outline(Vector3(0.0159,-0.058,8.73600),[
		[Vector3(0.07333,-0.008,5.46000),Vector3(0.116,0.072,0.78000),Vector3(0.208,0.103,1.56000)],
		[Vector3(0.23,0.098,2.34000),Vector3(0.247,0.083,3.12000),Vector3(0.26,0.077,3.90000)],
		[Vector3(0.213,0.137,0.00000),Vector3(0.105,0.078,0.78000),Vector3(0.062,0.028,3.90000)],
		[Vector3(0.05857,-0.006,6.24000),Vector3(0.0276,-0.04,8.73600),Vector3(0.0159,-0.058,8.73600)]]),"c5a762",unit)
	_surface(art,piece,_cubic_outline(Vector3(0.0745,0.018,5.46000),[
		[Vector3(0.124,0.078,1.56000),Vector3(0.213,0.12,1.56000),Vector3(0.265,0.072,3.90000)],
		[Vector3(0.222,0.132,0.00000),Vector3(0.124,0.088,0.78000),Vector3(0.072,0.04,3.90000)],
		[Vector3(0.069,0.033,4.68000),Vector3(0.068,0.025,4.68000),Vector3(0.0745,0.018,5.46000)]]),"e9d28e",unit)
	# The left ribbon retains substantial skin width before its curled tip.
	_surface(art,piece,_cubic_outline(Vector3(-0.07787,-0.001,6.86400),[
		[Vector3(-0.09,0.068,2.34000),Vector3(-0.185,0.141,0.46800),Vector3(-0.254,0.098,2.34000)],
		[Vector3(-0.197,0.156,0.00000),Vector3(-0.1,0.098,0.78000),Vector3(-0.043,0.025,4.68000)],
		[Vector3(-0.05771,0.01,5.46000),Vector3(-0.07013,0.003,6.24000),Vector3(-0.07787,-0.001,6.86400)]]),"ecd58f",unit)
	# Only the low overlap gets warm separation; no perimeter sticker outline.
	_surface(art,piece,_cubic_outline(Vector3(-.254,.098,2.34),[
		[Vector3(-.195,.142,.36),Vector3(-.100,.105,.65),Vector3(-.045,.034,4.1)],
		[Vector3(-.101,.122,.10),Vector3(-.198,.156,0),Vector3(-.254,.098,2.34)]]),"bda36c",unit)
	# A broad front ribbon flows from the neck and overlaps the side ribbons.
	_surface(art,piece,_cubic_outline(Vector3(-0.03468,-0.087,9.98400),[
		[Vector3(-0.05987,-0.044,7.48800),Vector3(-0.007,0.033,3.12000),Vector3(0.028,0.084,1.56000)],
		[Vector3(0.054,0.119,0.78000),Vector3(0.085,0.14,0.00000),Vector3(0.111,0.134,0.78000)],
		[Vector3(0.069,0.158,0.00000),Vector3(0.025,0.111,0.78000),Vector3(-0.005,0.068,2.34000)],
		[Vector3(-0.07481,-0.003,6.24000),Vector3(-0.06366,-0.059,8.73600),Vector3(-0.03468,-0.087,9.98400)]]),"e7cd82",unit)
	# Restrained light catches the skin ridge; the center stays yellow.
	_surface(art,piece,_cubic_outline(Vector3(-0.03847,-0.107,11.23200),[
		[Vector3(-0.05547,-0.051,8.73600),Vector3(-0.04322,-0.009,6.24000),Vector3(0.007,0.051,3.12000)],
		[Vector3(-0.05726,-0.004,6.24000),Vector3(-0.07419,-0.057,8.73600),Vector3(-0.03847,-0.107,11.23200)]]),"f1dba0",unit)
	_surface(art,piece,[Vector3(-0.06448,-0.13,12.48000),Vector3(0.00221,-0.128,12.48000),Vector3(-0.00454,-0.108,11.23200),Vector3(-0.05251,-0.11,11.23200)],"a3a06e",unit)
	_surface(art,piece,[Vector3(-0.06448,-0.13,12.48000),Vector3(-0.04693,-0.139,12.48000),Vector3(0.00104,-0.136,12.48000),Vector3(0.00221,-0.128,12.48000)],"95815a",unit)
	_surface(art,piece,[Vector3(-0.264,0.103,2.34000),Vector3(-0.273,0.087,2.80800),Vector3(-0.261,0.081,2.34000),Vector3(-0.246,0.089,1.87200)],"ab8e56",unit)
	_surface(art,piece,[Vector3(0.264,0.065,3.90000),Vector3(0.284,0.07,4.68000),Vector3(0.278,0.085,3.12000),Vector3(0.26,0.082,3.12000)],"ab8e56",unit)
