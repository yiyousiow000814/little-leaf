extends RefCounted
## Draw exactly the saved world-space geometry used by the cleanup planner.
const Geometry=preload("res://scripts/cafe_floor_geometry.gd")

static func _screen(art,point:Vector2)->Vector2:return art.iso(point.x,point.y)

static func _project(art,points:Array)->Array:
	var result=[]
	for point in points:result.append(_screen(art,point))
	return result

static func _piece_point(art,piece:Dictionary,point:Vector2)->Vector2:
	return _screen(art,piece.center+(point*float(piece.size)).rotated(float(piece.angle)))

static func _stroke(art,piece:Dictionary,a:Vector2,b:Vector2,color,width:float,unit:float):
	art.line(_piece_point(art,piece,a),_piece_point(art,piece,b),color,width*unit)

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
	for piece in shape.pieces:
		var kind=str(piece.kind)
		var fill={"banana":"c4a046","paper":"eee8cb","bag":"b8a278","crumbs":"a37d48"}.get(kind,"a37d48")
		art.poly(_project(art,Geometry.piece_points(piece)),fill)
		match kind:
			"banana":
				_stroke(art,piece,Vector2(0,-.17),Vector2(0,.02),"f4d878",1.6,unit)
				_stroke(art,piece,Vector2(0,.02),Vector2(.22,.09),"ead071",1.4,unit)
				_stroke(art,piece,Vector2(-.02,.03),Vector2(-.21,.12),"f1d77c",1.4,unit)
			"paper":
				_stroke(art,piece,Vector2(-.19,-.11),Vector2(.06,.02),"c1baa2",.9,unit)
				_stroke(art,piece,Vector2(.06,.02),Vector2(.14,.15),"d0c8b2",.9,unit)
				_stroke(art,piece,Vector2(.09,-.17),Vector2(.06,.02),"faf4dc",1.3,unit)
			"bag":
				_stroke(art,piece,Vector2(-.13,-.14),Vector2(.1,-.16),"807553",1.15,unit)
				_stroke(art,piece,Vector2(-.10,-.15),Vector2(-.075,-.25),"a18c63",1.1,unit)
				_stroke(art,piece,Vector2(-.075,-.25),Vector2(.065,-.25),"a18c63",1.1,unit)
				_stroke(art,piece,Vector2(.065,-.25),Vector2(.09,-.15),"a18c63",1.1,unit)
				_stroke(art,piece,Vector2(-.13,-.08),Vector2(-.10,.13),"d5c298",1.1,unit)
				_stroke(art,piece,Vector2(.14,-.02),Vector2(.13,.15),"96845e",.8,unit)
			_:
				_stroke(art,piece,Vector2(-.025,-.03),Vector2(.025,-.015),"d7b778",.8,unit)
