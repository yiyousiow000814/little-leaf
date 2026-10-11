extends SceneTree
const Pose=preload("res://scripts/dining_pose.gd")
const Layout=preload("res://scripts/dining_placement.gd")
const Checkout=preload("res://scripts/cafe_checkout_art.gd")
class PlateProbe extends "res://scripts/illustrated_cafe.gd":
 var marks=[]
 func ellipse(p:Vector2,r:Vector2,c):marks.append({"at":p,"size":r,"color":str(c)})
 func outlined_ellipse(_p:Vector2,_r:Vector2,_fill,_edge,_width=1.0):pass
 func line(_p:Vector2,_q:Vector2,_c,_width=1.0):pass
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok and not failures.has(label):failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
 var last=1.0
 for sample in range(4001):
  var progress=float(sample)/4000.0
  var remaining=Pose.remaining(progress)
  check(remaining<=last,"Plate refills during a meal")
  check(remaining in [0.0,.25,.5,.75,1.0],"Food decreases between bite beats")
  last=remaining
 var dimensions=[]
 for back in [false,true]:
  for mirror in [1.0,-1.0]:
   var near=Vector2(7,-24) if back else Vector2(-7,-24)
   var far=Vector2(-6,-26.5) if back else Vector2(6,-26.5)
   var forward=(Vector2.UP if mirror>0 else Vector2.LEFT) if back else (Vector2.RIGHT if mirror>0 else Vector2.DOWN)
   var layout=Layout.layout(-forward)
   var ground=Vector2((forward.x-forward.y)*39,(forward.x+forward.y)*19.5)*(1.0-.12-Layout.CHAIR_PULL)
   var plate=(ground+layout.plate)*Vector2(mirror,1)-Vector2(2,-5.5)
   var idle=(near if back else far)+Vector2(1 if back else -1,10).normalized()*10.5
   check(Pose.pose(near,far,plate,0,back,Vector2.INF,mirror).hand.is_equal_approx(idle),"Meal starts away from renderer rest")
   check(Pose.pose(near,far,plate,1,back,Vector2.INF,mirror).hand.is_equal_approx(idle),"Meal end pops before checkout idle")
   var supplied_rest=(near if back else far)+Vector2.DOWN*10.5
   check(Pose.pose(near,far,plate,0,back,supplied_rest,mirror).hand.is_equal_approx(supplied_rest),"Dining overrides renderer-provided rest at start")
   check(Pose.pose(near,far,plate,1,back,supplied_rest,mirror).hand.is_equal_approx(supplied_rest),"Dining overrides renderer-provided rest at end")
   var previous={}
   var min_length=100.0;var max_length=0.0
   for sample in range(4001):
    var progress=float(sample)/4000.0
    var p=Pose.pose(near,far,plate,progress,back,Vector2.INF,mirror)
    check(absf(p.shoulder.distance_to(p.hand)-10.5)<.0001,"Eating stretches an arm")
    check(p.shoulder==(near if back else far),"Eating overrides renderer shoulder sockets")
    if not previous.is_empty():
     check(p.hand.distance_to(previous.hand)<.25,"Hand jumps between eating phases")
     check(p.tip.distance_to(previous.tip)<.4,"Spoon jumps between eating phases")
    if p.phase>=.20 and p.phase<=Pose.PICKUP:check(p.tip.distance_to(p.plate_contact)<.0001,"Scoop misses plate contact")
    if p.phase>=.20 and p.phase<=Pose.PICKUP:check(p.plate_reach_error<.0001,"Pickup hides an unreachable plate")
    if p.stage=="chew":check(p.tip.distance_to(p.mouth)<.0001,"Bite misses mouth")
    if p.loaded:check(p.stage=="lift","Food floats during empty reach or return")
    check(absf(p.head_offset.y)<=.301,"Chew exaggerates head movement")
    var shifted=Pose.pose(near+Vector2(0,1),far+Vector2(0,2),plate,progress,back,Vector2.INF,mirror)
    check(shifted.shoulder==(near+Vector2(0,1) if back else far+Vector2(0,2)),"Dining rejects updated shoulder fit")
    # The independently selected shoulder patch only lowers the far socket.
    var new_far=Vector2(far.x,-24.5)
    var fitted=Pose.pose(near,new_far,plate,progress,back,Vector2.INF,mirror)
    check(absf(fitted.shoulder.distance_to(fitted.hand)-10.5)<.0001,"Selected shoulder fit stretches dining arm")
    check(fitted.shoulder==(near if back else new_far),"Selected shoulder fit uses a competing socket")
    if fitted.phase>=.20 and fitted.phase<=Pose.PICKUP:check(fitted.tip.distance_to(fitted.plate_contact)<.0001,"Selected shoulder fit misses plate")
    if fitted.stage=="chew":check(fitted.tip.distance_to(fitted.mouth)<.0001,"Selected shoulder fit misses mouth")
    check(absf(p.tip.distance_to(p.hand)-Pose.TOOL_LENGTH)<.0001,"Utensil length changes through the cycle")
    check(Pose.pose(near,new_far,plate,progress,back,Vector2.INF,mirror)==fitted,"Paused meal progress changes the pose")
    min_length=minf(min_length,p.hand.distance_to(p.tip));max_length=maxf(max_length,p.hand.distance_to(p.tip))
    previous=p
   for boundary in [.20,Pose.PICKUP,Pose.MOUTH,Pose.RETURN,1.0]:
    var before=Pose.pose(near,far,plate,(boundary-.000001)/4.0,back,Vector2.INF,mirror)
    var after=Pose.pose(near,far,plate,(boundary+.000001)/4.0,back,Vector2.INF,mirror)
    check(before.hand.distance_to(after.hand)<.001 and before.tip.distance_to(after.tip)<.001,"Phase boundary is discontinuous")
   var scoop=Pose.pose(near,far,plate,.25/4.0,back,Vector2.INF,mirror)
   dimensions.append({"back":back,"mirror":mirror,"scoop_shaft":scoop.hand.distance_to(scoop.tip),"min_projected_shaft":min_length,"max_projected_shaft":max_length})
 for boundary in [.25,.50,.75]:
  for delta in [-.001,0,.001]:
   check(is_equal_approx(float(Pose.pose(Vector2(7,-24),Vector2(-6,-26.5),Vector2(30,-45),boundary+delta,true).presence),1.0),"Utensil fades between bites")
 for index in range(Pose.BITES):
  var at=(float(index)+Pose.PICKUP)/Pose.BITES
  check(is_equal_approx(Pose.remaining(at-.00001)-Pose.remaining(at+.00001),.25),"Meal portion does not leave on pickup")
  check(Pose.beat(at+.00001).loaded,"Pickup removes food without loading spoon")
 check(Pose.remaining(0)==1.0 and Pose.remaining(1)==0.0,"Meal endpoints differ")
 check(Pose.pose(Vector2(7,-24),Vector2(-6,-26.5),Vector2(30,-45),0,true).hand.is_equal_approx(Pose.pose(Vector2(7,-24),Vector2(-6,-26.5),Vector2(30,-45),1,true).hand),"End does not return to resting arm")
 var guest={"phase":"eating","seated":true,"mobility":{}}
 for record in [{"plate_owner":"kitchen"},{"plate_owner":"staff"},{"plate_owner":"cleared"},{"plate_owner":"table","dishes_collected":true}]:check(Checkout.guest_action(guest,record)=="waiting_meal","Eating ignores plate ownership")
 check(Checkout.guest_action(guest,{"plate_owner":"table"})=="eating","Served meal cannot animate")
 check(Checkout.guest_action(guest,{})=="eating","Legacy ownership fallback changed")
 guest.phase="drinking";check(Checkout.guest_action(guest,{"drink_done":true,"drink_owner":"table"})=="drinking","Dining changes drinking action")
 var probe=PlateProbe.new()
 for remaining in [1.0,.75,.5,.25,.12,.08,.039,0.0]:
  probe.marks.clear();probe._plate(Vector2.ZERO,remaining,false)
  var used=false;var food=false
  for mark in probe.marks:
   used=used or mark.color=="cbbb93"
   food=food or mark.color=="fff5da"
  check(food or used,"Clean-empty gap at remaining "+str(remaining))
  check(used==(remaining<1.0),"Residue does not build with consumed food")
 probe.marks.clear();probe._plate(Vector2.ZERO,0,false);var finished=probe.marks.duplicate(true)
 probe.marks.clear();probe._plate(Vector2.ZERO,1,true)
 check(probe.marks==finished,"Meal-end plate pops when checkout marks it dirty")
 probe.free()
 print("DINING_POSE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"projection":dimensions}))
 quit(0 if failures.is_empty() else 1)
