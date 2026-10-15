extends SceneTree
const Furniture=preload("res://scripts/rendering/illustrated_furniture.gd")
const Atlas=preload("res://scripts/rendering/furniture_static_atlas.gd")
const Motion=preload("res://scripts/rendering/illustrated_motion.gd")
const Wash=preload("res://scripts/rendering/cafe_sink_wash_art.gd")
class Probe extends Node2D:
 var points=[]
 var surfaces=[]
 func rounded_poly(shape,_radius,color):
  points.append_array(shape);surfaces.append({"points":shape,"color":color})
 func poly(shape,_color):points.append_array(shape)
 func line(a,b,_color,_width=1):points.append(a);points.append(b)
 func _face_line(a,b,_color,_width=1):points.append(a);points.append(b)
 func _face_ellipse(at,radius,_color):points.append(at-radius);points.append(at+radius)
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func ground(point:Vector2)->Vector2:
 return Vector2(point.x/78+point.y/39,point.y/39-point.x/78)
func run():
 var furniture=Furniture.new();var probe=Probe.new()
 for rotation in range(4):
  for kind in ["counter","beverage_base","sink"]:
   probe.points.clear();probe.surfaces.clear()
   furniture.draw_static_part(probe,kind,Vector2.ZERO,rotation)
   var color={"counter":"e6cca0","beverage_base":"e9dfc0","sink":"cbd7be"}[kind]
   var top=[]
   for surface in probe.surfaces:
    if surface.color==color:top=surface.points
   check(top.size()==4,"complete cabinet top "+kind+str(rotation))
   if top.size()!=4:continue
   for i in range(4):
    var edge=ground(top[(i+1)%4]-top[i])
    check(is_equal_approx(edge.length(),1.),"true one-cell top edge "+kind+str(rotation))
    check(is_zero_approx(edge.x) or is_zero_approx(edge.y),"top follows grid axis "+kind+str(rotation))
   for side in range(2):
    var face=probe.surfaces[side].points
    for vertex in [face[0],face[1]]:
     var corner=ground(vertex)
     check(is_equal_approx(absf(corner.x),.5) and is_equal_approx(absf(corner.y),.5),"solid body reaches floor corner "+kind+str(rotation))
   var shared=0
   for a in top:
    for b in top:
     if a.distance_to(b+Vector2(39,19.5))<.001:shared+=1
   check(shared==2,"adjacent cabinets share complete edge "+kind+str(rotation))
   var contained=true
   for point in probe.points:
    if not Atlas.bounds(kind).grow(-1).has_point(point):contained=false
   check(contained,"all cabinet geometry fits atlas guard "+kind+str(rotation))
  var heading=-Vector2.DOWN.rotated(rotation*PI/2)
  var axis=Motion._shoe_axis(heading);var across=axis.orthogonal()
  var inward=0.0
  for side in [-1.,1.]:
   var center=Motion._rest_center(side,heading)
   for point in [Vector2(-3.9,-1.25),Vector2(-2.8,-2),Vector2(1.4,-2.2),Vector2(3.5,-1.6),Vector2(4.1,-.3),Vector2(3.5,1.45),Vector2(1.4,2.15),Vector2(-2.8,1.9),Vector2(-3.9,.95)]:
    inward=maxf(inward,ground(center+axis*point.x+across*point.y).dot(heading))
  check(1.-Wash.work_inset(rotation)-inward>.51,"settled washing shoes clear solid body "+str(rotation))
  var front=-heading;var drop_stance=Wash.front_drop_stance(rotation)
  check(1.+drop_stance.dot(front)-inward>.51,"front deposit shoes clear full-cell body "+str(rotation))
  check((drop_stance+front*Wash.work_inset(rotation)).length()>.35,"front deposit retains distinct worker ground contact "+str(rotation))
  var release=Wash.drop_geometry(rotation,.65,Vector2.ZERO,0,true)
  var opening=Wash.Geometry.sink_outline(Wash.Geometry.SINK_BASIN_INNER,Wash.Geometry.SINK_OPENING_HEIGHT,rotation)
  var projected=release.release+Vector2(0,release.release_height-Wash.Geometry.height(Wash.Geometry.SINK_OPENING_HEIGHT))
  check(Geometry2D.is_point_in_polygon(projected,opening),"front release center is inside the physical opening "+str(rotation))

 probe.free()
 print("MODULAR_CABINETS_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
