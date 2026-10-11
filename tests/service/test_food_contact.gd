extends SceneTree
const Pose=preload("res://scripts/cooking_tool_pose.gd")
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func at_phase(rear:bool,phase:float,remaining=-1.0):
 var seconds=phase*Pose.FRY_SECONDS
 var shoulder=Vector2(7,-24) if rear else Vector2(-7,-24)
 var pan=Vector2(23.4,-43.7) if rear else Vector2(23.4,-20.3)
 return Pose.pose(shoulder,pan-Pose.body_weight(seconds,remaining),seconds,remaining)
func run():
 for rear in [false,true]:
  var previous=[]
  for sample in range(1201):
   var phase=float(sample)/1200.0
   var p=at_phase(rear,phase)
   var parts=Pose.food_parts(p)
   check(parts.size()==6,"Ingredients are created or lost")
   for id in range(6):
    check(parts[id].id==id,"Ingredient identity changed")
    check(absf(parts[id].at.x)<6.4 and parts[id].at.y>=-6.2 and parts[id].at.y<1.2,"Ingredient leaves pan/lift bounds")
    if not previous.is_empty():check(parts[id].at.distance_to(previous[id].at)<.18,"Ingredient teleports between contact phases")
    if id<3:check(parts[id].at==Pose.FOOD_AT[id],"Untouched food moves without contact")
    elif phase<=.15 or phase>=.82:check(parts[id].at.distance_to(Pose.FOOD_AT[id])<.00001,"Gather/settle food is not in the pan")
    elif phase<=.37:
     var tip=p.contact-p.pan
     var threshold=tip.x+Pose.PUSH_AHEAD[id-3]
     if threshold<=Pose.FOOD_AT[id].x:
      check(parts[id].at==Pose.FOOD_AT[id],"Food moves before the blade reaches it")
     else:check(absf(parts[id].at.x-threshold)<.0001,"Pushed food does not follow blade edge")
    elif phase>.49 and phase<=.63:
     var carried=p.contact-p.pan-p.axis*.4+Pose.CARRY_AT[id-3]
     check(parts[id].at.distance_to(carried)<.0001,"Lifted food is not supported by the blade")
   if phase<=.49:check(Pose.blade_under_food(p),"Contact blade is painted above surface food")
   if phase>.60 and phase<.65:check(not Pose.blade_under_food(p),"Raised blade remains hidden under the food")
   previous=parts
  var start=Pose.food_parts(at_phase(rear,0))
  var end=Pose.food_parts(at_phase(rear,1))
  for id in range(6):check(start[id].at==end[id].at,"Food cycle changes identity/position at wrap")
  # Any recipe ending, including an upgraded stove ending during a lift,
  # settles the same ingredients inside the existing time budget.
  for phase in [.1,.3,.45,.6,.7,.9]:
   var settled=at_phase(rear,phase,0.0)
   var parts=Pose.food_parts(settled)
   check(settled.motion.body==Vector2.ZERO and is_equal_approx(settled.motion.tip_y,.45),"Completion leaves a raised gesture")
   for id in range(6):check(parts[id].at==Pose.FOOD_AT[id],"Completion abandons food in the air")
 print("FOOD_CONTACT_TESTS checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
