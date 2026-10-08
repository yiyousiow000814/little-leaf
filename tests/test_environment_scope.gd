extends SceneTree
const Neighborhood=preload("res://scripts/exterior_environment.gd")
const Camera=preload("res://scripts/cafe_camera_landmarks.gd")
class Recorder extends RefCounted:
 var ui_scale=1.0
 var zoom=1.0
 var polygons=[]
 var lines=[]
 func iso(x:float,z:float,h:float=0.0)->Vector2:return Vector2(x,z-h/39.0)
 func get_viewport_rect()->Rect2:return Rect2(-200,-200,400,400)
 func poly(points:Array,_color):polygons.append(points)
 func line(a:Vector2,b:Vector2,_color,_width=1.0):lines.append([a,b])
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _init():
 var a=Recorder.new();Neighborhood.draw_ground(a)
 for footprint in [Camera.LOT,Camera.MOUTH,Camera.PEDESTRIAN_LINK]:
  var expected=[footprint.position,Vector2(footprint.end.x,footprint.position.y),footprint.end,Vector2(footprint.position.x,footprint.end.y)]
  check(not a.polygons.has(expected),"no parking lot, driveway, or link ground before parking feature")
 for x in [0.0,2.9,5.8,8.7,11.6]:check(not a.lines.has([Vector2(x,-8.45),Vector2(x,-5.75)]),"no early parking bay markings")
 check(not Neighborhood.new().has_method("parking_hooks"),"no enabled parking purchase hooks")
 for tile in [Vector2(13.65,6.825),Vector2(39,19.5),Vector2(156,78)]:
  check(Neighborhood.inspection_bounds(tile)==Camera.inspection_bounds(tile),"environment preserves accepted camera bounds exactly")
 print("ENVIRONMENT_SCOPE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
