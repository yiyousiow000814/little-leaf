extends SceneTree
const Layout=preload("res://scripts/dining_placement.gd")
const Pose=preload("res://scripts/dining_pose.gd")
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok and not failures.has(label):failures.append(label);printerr(label)
func world(point:Vector2)->Vector2:
 var p=Vector2(point.x/34,(point.y+Layout.TABLE_HEIGHT)/17)
 return Vector2((p.x+p.y)*.5,(p.y-p.x)*.5)
func _initialize():
 var measurements=[]
 for forward in [Vector2.RIGHT,Vector2.DOWN,Vector2.UP,Vector2.LEFT]:
  var back=forward.x+forward.y<0;var mirror=-1.0 if forward.x-forward.y<0 else 1.0
  var layout=Layout.layout(-forward)
  check(world(layout.plate).dot(-forward)>.13,"Plate is not on diner-facing half")
  check(world(layout.cup).dot(-forward)<world(layout.plate).dot(-forward),"Cup is closer than the food")
  for angle in range(360):
   var p=layout.plate+Vector2(cos(deg_to_rad(angle))*14.7,sin(deg_to_rad(angle))*7.1)
   check(pow(p.x/Layout.ROUND_TOP.x,2)+pow((p.y+Layout.TABLE_HEIGHT)/Layout.ROUND_TOP.y,2)<1.02,"Plate leaves round tabletop")
   var w=world(p)
   check(absf(w.x)<.45 and absf(w.y)<.45,"Plate leaves cottage square")
   check(absf(w.x)+absf(w.y)<.72,"Plate leaves refined clipped corner")
  for anchor in [layout.cup,layout.vase]:
   for angle in range(360):
    var p=anchor+Vector2(cos(deg_to_rad(angle))*4.2,sin(deg_to_rad(angle))*1.6)
    var w=world(p)
    check(absf(w.x)<.45 and absf(w.y)<.45,"Tableware foot leaves cottage")
    check(absf(w.x)+absf(w.y)<.72,"Tableware foot leaves refined corner")
    check(pow(p.x/Layout.ROUND_TOP.x,2)+pow((p.y+Layout.TABLE_HEIGHT)/Layout.ROUND_TOP.y,2)<1.0,"Tableware foot leaves round tabletop")
  var scale=1.0-.12-Layout.CHAIR_PULL
  var ground=Vector2((forward.x-forward.y)*39,(forward.x+forward.y)*19.5)*scale
  var body=Vector2(2,-5.5)
  var plate=(ground+layout.plate)*Vector2(mirror,1)-body
  var cup=(ground+layout.cup)*Vector2(mirror,1)-body
  var vase=(ground+layout.vase)*Vector2(mirror,1)-body
  var near=Vector2(7,-24) if back else Vector2(-7,-24)
  var far=Vector2(-6,-26.5) if back else Vector2(6,-26.5)
  var max_error=0.0;var cup_hits=[];var vase_hits=[];var max_tool=0.0
  var previous={}
  for step in range(2001):
   var progress=float(step)/2000
   var p=Pose.pose(near,far,plate,progress,back,Vector2.INF,mirror)
   check(absf(p.hand.distance_to(p.shoulder)-10.5)<.0001,"Arm stretches")
   check(absf(p.hand.distance_to(p.tip)-8.0)<.0001,"Spoon grows or shrinks")
   max_tool=maxf(max_tool,p.hand.distance_to(p.tip))
   if p.phase>=.20 and p.phase<Pose.PICKUP:
    var error=p.tip.distance_to(p.plate_contact);max_error=maxf(max_error,error)
    check(error<.001,"Spoon does not touch the actual bite portion")
    check(p.plate_reach_error<.001,"Clamped grip misses a pickup")
   if p.stage=="chew":check(p.tip.distance_to(p.mouth)<.001,"Spoon misses mouth")
   if not previous.is_empty():
    check(p.hand.distance_to(previous.hand)<.40,"Hand discontinuity")
    check(p.tip.distance_to(previous.tip)<.65,"Spoon discontinuity")
   previous=p
   if p.over_table and p.presence>.1:
    # Conservative projected checks flag any candidate overlap for native QA.
    var cup_box=Rect2(cup+Vector2(-4.1,-10.7),Vector2(8.2,11.3))
    var vase_boxes=[Rect2(vase+Vector2(-3.3,-8.3),Vector2(6.6,10.1)),Rect2(vase+Vector2(-.95,-16.5),Vector2(1.9,10)),Rect2(vase+Vector2(-1.3 if mirror>0 else -5.3,-15.0),Vector2(6.6,4.0))]
    var cup_hit=cup_box.grow(2.5).has_point(p.hand) or cup_box.grow(1.8).has_point(p.tip)
    var vase_hit=false
    for box in vase_boxes:vase_hit=vase_hit or box.grow(2.5).has_point(p.hand) or box.grow(1.8).has_point(p.tip)
    for sample in range(17):
     var point=p.hand.lerp(p.tip,float(sample)/16)
     cup_hit=cup_hit or cup_box.grow(.65).has_point(point)
     for box in vase_boxes:vase_hit=vase_hit or box.grow(.65).has_point(point)
    if cup_hit and cup_hits.size()<12:cup_hits.append(progress)
    if vase_hit and vase_hits.size()<12:vase_hits.append(progress)
  check(cup_hits.is_empty(),"Spoon/hand crosses the cup")
  check(vase_hits.is_empty(),"Spoon/hand crosses the vase")
  measurements.append({"forward":str(forward),"max_contact_error":max_error,"max_spoon":max_tool,"cup_overlap_samples":cup_hits,"vase_overlap_samples":vase_hits})
 print("DINING_PLACEMENT_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements}))
 quit(0 if failures.is_empty() else 1)
