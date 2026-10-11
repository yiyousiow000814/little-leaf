extends SceneTree
const Furniture=preload("res://scripts/illustrated_furniture.gd")
const Kitchen=preload("res://scripts/kitchen_worktop_geometry.gd")
class ArtistSpy:
 extends Node2D
 var tubes=[]
 func poly(points:Array,color):
  if color=="5e7d69":tubes.append(PackedVector2Array(points))
 func rounded_poly(_points,_radius,_color):pass
 func line(_start,_end,_color,_width=1.0):pass
 func ellipse(_at,_size,_color):pass
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
 var artist=ArtistSpy.new();var renderer=Furniture.new()
 renderer.a=artist;renderer.origin=Vector2(40,80);renderer.kitchen_height=true
 for rotation in range(4):
  var path=Furniture.beverage_spout_path(rotation)
  check(path[0].is_equal_approx(Kitchen.surface(Vector2(.17,.06),43,rotation)),"Tube lost its reservoir mount")
  check(path[-1].is_equal_approx(Kitchen.surface(Vector2(.17,.24),39.5,rotation)),"Outlet lost its cup/tray alignment")
  for index in range(1,path.size()-1):
   var incoming=(path[index]-path[index-1]).normalized()
   var outgoing=(path[index+1]-path[index]).normalized()
   check(absf(incoming.angle_to(outgoing))<.30,"Tube retains a square segmented elbow")
  var silhouettes=[Furniture.beverage_spout_silhouette(rotation)]
  for scale in [1.0,4.0,10.0]:
   check(not Geometry2D.triangulate_polygon(Transform2D(0,Vector2.ONE*scale,0,Vector2.ZERO)*silhouettes[0]).is_empty(),"Actual tube cannot be filled at native or magnified scale")
  check(silhouettes.size()==1,"Tube splits into disconnected pieces")
  if silhouettes.size()==1:
   for index in range(path.size()-1):
    for fraction in [0.0,.25,.5,.75]:
     check(Geometry2D.is_point_in_polygon(path[index].lerp(path[index+1],fraction),silhouettes[0]),"Tube silhouette has an internal gap")
   for point in silhouettes[0]:check(Furniture.StaticAtlas.bounds("beverage_machine").grow(-1).has_point(point),"Tube leaves protected atlas bounds")
  artist.tubes.clear();renderer.turn=rotation;renderer.espresso()
  check(artist.tubes.size()==(1 if rotation in [0,3] else 0),"Spout ignores dispenser body occlusion")
  if artist.tubes.size()==1:
   for point in path:check(Geometry2D.is_point_in_polygon(renderer.origin+point,artist.tubes[0]),"Actual painter breaks the connected silhouette")
 artist.free()
 print("CONTINUOUS_SPOUT_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
