extends SceneTree
const Character=preload("res://scripts/directional_character_art.gd")
const Layout=preload("res://scripts/dining_placement.gd")
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok and not failures.has(label):failures.append(label);printerr(label)
func _initialize():
 for back in [false,true]:
  var sign=-1.0 if back else 1.0
  var ground_dock=Vector2(4.68,sign*2.34)
  var along=Vector2(25,sign*12.5);var across=Vector2(-sign*25,12.5)
  for mirror in [-1.0,1.0]:
   var pose=Character.leg_pose({"seat_mix":1.0,"mirror":mirror},false,0.0,back)
   check(pose.body==Vector2(2,-5.5),"Seated body lifted off its seat")
   for near in [false,true]:
    var prefix="near" if near else "far"
    var hip:Vector2=pose[prefix+"_hip"];var ankle:Vector2=pose[prefix+"_foot"]
    var lane=.15 if near else -.15
    check((hip+pose.body+ground_dock).is_equal_approx(along*.20+across*lane+Vector2(0,-18)),"Thigh socket leaves seat plane")
    check(absf((ankle-hip).cross(along.normalized()))<.0001,"Short seated leg leaves the annotated seat direction")
    check(absf(hip.distance_to(ankle)-Character.SEATED_LEG_REACH)<.0001,"Seated figure grows a long leg")
    check((ankle+pose.body+ground_dock).x>(along*.35+across*lane).x,"Suspended foot does not project beyond seat edge")
    check((pose[prefix+"_axis"] as Vector2).dot(along.normalized())>.999,"Shoe perspective differs from its short leg")
   var previous={}
   for step in range(101):
    var mix=float(step)/100.0
    var p=Character.leg_pose({"seat_mix":mix,"mirror":mirror},false,0.0,back)
    if not previous.is_empty():
     for point in ["near_hip","far_hip","near_foot","far_foot"]:check((p[point] as Vector2).distance_to(previous[point])<.25,"Seat/dismount leg endpoint jumps")
    previous=p
 check(Layout.table_height(0)==0.0 and Layout.table_height(1)==1.0,"Table floor contacts move")
 check(is_equal_approx(Layout.table_height(33),Layout.TABLE_HEIGHT),"Table artwork and dish plane disagree")
 check(Layout.TABLE_HEIGHT<29.5 and Layout.TABLE_HEIGHT>18,"Table is at shoulder height or below seat")
 print("SEATED_PROPORTIONS_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
