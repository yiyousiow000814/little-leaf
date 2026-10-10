extends SceneTree
const F=preload("res://scripts/illustrated_furniture.gd")
const L=preload("res://scripts/cafe_stove_layout.gd")
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func footprint(center:Vector2,radii:Vector2,rotation:int)->PackedVector2Array:
 var result=PackedVector2Array()
 for index in range(256):
  var angle=index*TAU/256.0;var q=Vector2(cos(angle)*radii.x,sin(angle)*radii.y)
  result.append(center+Vector2(q.x/68+q.y/34,q.y/34-q.x/68).rotated(-rotation*PI/2))
 return result
func _initialize():
 var measures=[];var half=F.STOVE_TILE_SPAN*.5
 for rotation in range(4):
  # Exact ceramic/rim envelopes, including half their outline strokes;
  # painter shadows are not physical surfaces. No perspective-size shortcut.
  var plate=footprint(L.OUTPUT_CENTER,Vector2(14+.35,6.4+.35),rotation)
  var pot=footprint(L.POT_CENTER,Vector2(8.5*F.PAN_WIDTH+.6,4.2*F.PAN_DEPTH+.6),rotation)
  var burner=PackedVector2Array()
  for i in range(256):burner.append(L.POT_CENTER+Vector2.from_angle(i*TAU/256.0)*(.155*F.PAN_WIDTH))
  var support=INF
  for polygon in [plate,pot]:
   for q in polygon:
    support=minf(support,half-maxf(absf(q.x),absf(q.y)))
    check(absf(q.x)<=half and absf(q.y)<=half,"complete plate/pot envelope supported r"+str(rotation))
  check(Geometry2D.intersect_polygons(plate,pot).is_empty(),"full-size plate does not intersect pot r"+str(rotation))
  check(Geometry2D.intersect_polygons(plate,burner).is_empty(),"full-size plate does not intersect burner r"+str(rotation))
  var min_distance=INF
  for p in plate:
   for i in pot.size():min_distance=minf(min_distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,pot[i],pot[(i+1)%pot.size()])))
  check(min_distance>.005,"positive ceramic/pot clearance including strokes r"+str(rotation))
  measures.append({"rotation":rotation,"minimum_support_margin":support,"minimum_pot_clearance":min_distance,"plate_radii_unchanged":[14,6.4]})
 print("STOVE_OUTPUT_GEOMETRY_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"measurements":measures}))
 quit(0 if failures.is_empty() else 1)
