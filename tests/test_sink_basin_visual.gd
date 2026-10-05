extends SceneTree
const Geometry=preload("res://scripts/kitchen_worktop_geometry.gd")
const Furniture=preload("res://scripts/illustrated_furniture.gd")
const Atlas=preload("res://scripts/furniture_static_atlas.gd")
var checks=0
var failures=[]
class Probe extends Node2D:
 var upright_dishes=0
 var points=[]
 func rounded_poly(shape,_radius,_color):points.append_array(shape)
 func poly(shape,_color):points.append_array(shape)
 func line(a,b,_color,_width=1):points.append(a);points.append(b)
 func _face_line(a,b,_color,_width=1):points.append(a);points.append(b)
 func _face_ellipse(at,radius,_color):points.append(at-radius);points.append(at+radius)
 func ellipse(at,radius,_color):points.append(at-radius);points.append(at+radius)
 func outlined_ellipse(at,radius,_fill,_stroke,_width=1):
  upright_dishes+=1;points.append(at-radius);points.append(at+radius)
func _initialize():run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func run():
 var furniture=Furniture.new();var probe=Probe.new();root.add_child(probe)
 for rotation in range(4):
  var center=Geometry.surface(Geometry.SINK_BASIN_CENTER,Geometry.SINK_RIM_HEIGHT,rotation)
  var rim=PackedVector2Array()
  for step in 128:
   var theta=step*TAU/128.0
   rim.append(Geometry.surface(Geometry.SINK_BASIN_CENTER+Vector2(cos(theta)*Geometry.SINK_BASIN_OUTER.x,sin(theta)*Geometry.SINK_BASIN_OUTER.y),30.0,rotation))
  for step in 128:
   var theta=step*TAU/128.0
   var point=center+Vector2(cos(theta)*14.0,sin(theta)*6.4)
   check(Geometry2D.is_point_in_polygon(point,rim),"unchanged plate footprint fits basin rim r%s sample%s"%[rotation,step])
  check(Geometry.height(Geometry.SINK_BOTTOM_HEIGHT)<Geometry.height(Geometry.SINK_RIM_HEIGHT)-5.0,"basin floor is more than five art pixels recessed r"+str(rotation))
  check(Geometry.sink_plate_anchor(rotation).y>center.y+4.0,"bottom dish rests inside the bowl r"+str(rotation))
  var stack_top=Geometry.sink_plate_anchor(rotation)+Vector2(0,-5*2.2-6.4)
  var outlet=Geometry.surface(Vector2(Geometry.SINK_BASIN_CENTER.x,-.02),Geometry.SINK_TAP_OUTLET_HEIGHT,rotation)
  check(outlet.y<stack_top.y-8.0,"outlet has eight projected pixels above full stack r"+str(rotation))
  check(Geometry.sink_tap_in_front(rotation)==(rotation in [1,2]),"tap layering follows rotated physical mount r"+str(rotation))
  probe.points.clear();probe.upright_dishes=0
  furniture.draw_item(probe,"sink",Vector2.ZERO,rotation,3)
  check(probe.upright_dishes==0,"no ornamental rack plates r"+str(rotation))
  var safe=Atlas.bounds("sink").grow(-1.0)
  for p in probe.points:check(safe.has_point(p),"static basin/tap remains within retained atlas r"+str(rotation))
  var zero_count=probe.points.size()
  probe.points.clear();furniture.draw_item(probe,"sink",Vector2(200,300),rotation,3)
  check(abs(probe.points.size()-zero_count)<12,"translated catalog sink preserves cavity polygons r"+str(rotation))
  for p in probe.points:check(safe.has_point(p-Vector2(200,300)),"translated sink geometry stays correctly anchored r"+str(rotation))
  check(Geometry.SINK_BASIN_CENTER.x-Geometry.SINK_BASIN_OUTER.x>-.47 and Geometry.SINK_BASIN_CENTER.x+Geometry.SINK_BASIN_OUTER.x<.47,"basin fits unchanged cabinet width r"+str(rotation))
  check(Geometry.SINK_BASIN_CENTER.y-Geometry.SINK_BASIN_OUTER.y>-.41 and Geometry.SINK_BASIN_CENTER.y+Geometry.SINK_BASIN_OUTER.y<.41,"basin fits unchanged cabinet depth r"+str(rotation))
 print("SINK_BASIN_VISUAL_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"rotations":4,"plate_radius_unchanged":[14,6.4]}))
 quit(0 if failures.is_empty() else 1)
