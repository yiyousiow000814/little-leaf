extends SceneTree
const Furniture=preload("res://scripts/illustrated_furniture.gd")
const Atlas=preload("res://scripts/furniture_static_atlas.gd")
const Model=preload("res://scripts/cafe_model.gd")
const AA=preload("res://scripts/retained_aa_strokes.gd")
class Artist extends Node2D:
 var tops=[]
 func rounded_poly(points,_radius,color):
  if color=="d9deca":tops.append(PackedVector2Array(points))
 func poly(_points,_color):pass
 func line(_a,_b,_color,_width=1.0):pass
 func ellipse(_at,_size,_color):pass
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func area(points)->float:
 var result=0.0
 for i in points.size():result+=points[i].cross(points[(i+1)%points.size()])
 return absf(result)*.5
func _initialize():run.call_deferred()
func run():
 var artist=Artist.new();var furniture=Furniture.new()
 furniture.a=artist;furniture.origin=Vector2.ZERO;furniture.kitchen_height=true
 for rotation in range(4):
  artist.tops.clear();furniture.turn=rotation;furniture._stove_base()
  check(artist.tops.size()==1,"One real stove worktop")
  var top:PackedVector2Array=artist.tops[0]
  var ground=PackedVector2Array()
  for corner in top:
   var q=corner+Vector2(0,Furniture.KitchenGeometry.height(31))
   var tile=Vector2((q.x/39.0+q.y/19.5)*.5,(q.y/19.5-q.x/39.0)*.5)
   check(absf(absf(tile.x)-.5)<.00001 and absf(absf(tile.y)-.5)<.00001,"Top reaches exactly one grid tile without spill")
   check(Atlas.bounds("stove_base").grow(-2).has_point(corner),"Expanded source art remains inside atlas padding")
   ground.append(tile)
  check(absf(area(ground)-1.0)<.00001,"Full-tile worktop area is one logical cell")
  for direction in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
   var adjacent=PackedVector2Array()
   for q in ground:adjacent.append(q+direction)
   var overlap=0.0
   for polygon in Geometry2D.intersect_polygons(ground,adjacent):overlap+=area(polygon)
   check(overlap<.00001,"Adjacent full-tile tops share only their boundary")
  for sample in range(64):
   var angle=sample*TAU/64.0
   var q=Vector2(cos(angle)*8.5*Furniture.PAN_WIDTH,sin(angle)*4.2*Furniture.PAN_DEPTH)
   var tile=Vector2((q.x/39.0+q.y/19.5)*.5,(q.y/19.5-q.x/39.0)*.5)
   check(absf(tile.x)<.5 and absf(tile.y)<.5,"Enlarged pot rim remains within one tile")
  # Include the actual wood/metal anti-alias envelope, not only endpoints.
  var handle=Furniture.stove_handle_points(rotation)
  var axis=(handle[1]-handle[0]).normalized();var side=axis.orthogonal()
  for along in [-AA.FEATHER_SIZE,handle[0].distance_to(handle[1])+AA.FEATHER_SIZE]:
   for edge in [-1.1-AA.FEATHER_SIZE,1.1+AA.FEATHER_SIZE]:
    var q=handle[0]+axis*along+side*edge+Vector2(0,Furniture.KitchenGeometry.height(Furniture.stove_handle_height(rotation)))
    var tile=Vector2((q.x/39.0+q.y/19.5)*.5,(q.y/19.5-q.x/39.0)*.5)
    check(absf(tile.x)<=.50001 and absf(tile.y)<=.50001,"Handle including AA remains within its occupied tile")
  # At a wall/corner, the visual top never extends past its allocated cell.
  for cell in [Vector2(1,0),Vector2(10,0),Vector2(1,7),Vector2(10,7)]:
   for q in ground:
    var at=cell+Vector2(.5,.5)+q
    check(at.x>=cell.x-.00001 and at.x<=cell.x+1.00001 and at.y>=cell.y-.00001 and at.y<=cell.y+1.00001,"Wall/corner art stays in its tile")
 var model=Model.new();model.coins=100000;model.items.clear();model.customers.clear();model.dining_sets.clear();model._notify()
 check(model.place("stove",4,3,0),"First generated stove places")
 check(model.place("stove",5,3,0),"Adjacent stove preserves available workfronts")
 check(not model.can_place("stove",4,3,0),"Logical footprint still rejects overlap")
 check(model.place("stove",1,0,0),"North-wall corner-facing stove places safely")
 for item in model.items:
  if item.kind=="stove":check(model.workface_accessible(item),"Full artwork does not change route/workface access")
 artist.free()
 print("STOVE_FULL_TILE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
