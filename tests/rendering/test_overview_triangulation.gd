extends SceneTree
const Triangles=preload("res://scripts/cafe_polygon_triangulation.gd")
const Neighborhood=preload("res://scripts/exterior_environment.gd")
var checks=0
var failures=[]
func area(points:PackedVector2Array)->float:
 var value=0.0
 for i in range(1,points.size()-1):value+=(points[i]-points[0]).cross(points[i+1]-points[0])
 return absf(value)*.5
func check(ok:bool,label:String):
 checks+=1
 if not ok and label not in failures:failures.append(label)
func _init():
 var contours=[PackedVector2Array([Vector2(0,0),Vector2(4,0),Vector2(4,1),Vector2(1,1),Vector2(1,4),Vector2(0,4)])]
 contours.append(PackedVector2Array([Vector2.ZERO,Vector2(4,0),Vector2(4,0),Vector2(4,4),Vector2(0,4),Vector2.ZERO]))
 for layer in preload("res://scripts/exterior_tree_art.gd").new().layers:contours.append(layer[1])
 for row in Neighborhood.stop_paving:contours.append(PackedVector2Array(row.points))
 for variant in Neighborhood.greenery.trees:
  for layer in Neighborhood.greenery.trees[variant]:contours.append(layer[1])
 for pocket in Neighborhood.greenery.pockets:
  for layer in pocket:contours.append(layer[1])
 for contour in contours:
  for scale in [.01,.04,.1,.3,1.0]:
   for reverse in [false,true]:
    var points=PackedVector2Array()
    for point in contour:points.append(point*scale+Vector2(100,425))
    if reverse:points.reverse()
    var expected=area(points);var indices=Triangles.indices(points)
    if expected<.0000001:continue
    check(not indices.is_empty(),"nondegenerate authored contour triangulates at overview scale")
    var actual=0.0
    for i in range(0,indices.size(),3):actual+=absf((points[indices[i+1]]-points[indices[i]]).cross(points[indices[i+2]]-points[indices[i]]))*.5
    check(absf(actual-expected)<=maxf(.00001,expected*.001),"triangle areas preserve concave contour and winding")
 for layer in preload("res://scripts/exterior_tree_art.gd").new().layers:
  var source:PackedVector2Array=layer[1];var indices=Triangles.indices(source)
  check(not indices.is_empty(),"every oak layer has cached source-space triangles")
  for scale in [.04,.08,.2]:
   for mirror in [-1.0,1.0]:
    for offset in [Vector2(-400,1000),Vector2(100,425),Vector2(1400,-200)]:
     var transform=Transform2D(Vector2(scale*mirror,0),Vector2(0,scale),offset)
     var projected=transform*source;var expected=area(projected);var actual=0.0
     for i in range(0,indices.size(),3):actual+=absf((projected[indices[i+1]]-projected[indices[i]]).cross(projected[indices[i+2]]-projected[indices[i]]))*.5
     check(absf(actual-expected)<maxf(.01,expected*.001),"cached oak triangles retain mirrored/translated overview silhouette")
 check(Triangles.indices(PackedVector2Array()).is_empty(),"empty contour rejected")
 check(Triangles.indices(PackedVector2Array([Vector2.ONE,Vector2.ONE,Vector2.ONE])).is_empty(),"collapsed contour rejected")
 print("OVERVIEW_TRIANGULATION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
