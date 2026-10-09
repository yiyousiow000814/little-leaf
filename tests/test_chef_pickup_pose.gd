extends SceneTree
const Art=preload("res://scripts/cafe_chef_pickup_art.gd")
const Pickup=preload("res://scripts/cafe_chef_pickup.gd")
const Character=preload("res://scripts/directional_character_art.gd")
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():
 for rotation in range(4):
  var heading=-Vector2.DOWN.rotated(rotation*PI/2)
  var mirror=-1.0 if heading.x-heading.y<0 else 1.0;var back=heading.x+heading.y<0
  var ground=Vector2((heading.x-heading.y)*39,(heading.x+heading.y)*19.5)*(1.0-Art.INSET)
  var near=Vector2(7,-24) if back else Vector2(-7,-24);var far=Vector2(-6,-26.5) if back else Vector2(6,-26.5)
  var grip=(ground+Art.grip(rotation))*Vector2(mirror,1)
  var plate=(ground+Pickup.plate_anchor(rotation))*Vector2(mirror,1)
  var carry=Character.carry_anchor(back)
  for pickup in [false,true]:
   for step in range(101):
    var pose=Art.pose(near,far,carry,grip,plate,step*.01,pickup)
    check(absf(pose.shoulder.distance_to(pose.elbow)-Art.UPPER)<.0001,"fixed upper arm")
    check(absf(pose.elbow.distance_to(pose.hand)-Art.LOWER)<.0001,"fixed lower arm")
    if step==65:
     check(pose.contact_error<.001,"real hand touches stove grip r"+str(rotation))
     check(pose.plate_error<.001,"held and stored plate meet exactly r"+str(rotation))
    if step in [0,100]:check(pose.plate.distance_to(carry+Vector2(4,-2))<.001,"carry continuity at action boundary")
 print("CHEF_PICKUP_POSE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
