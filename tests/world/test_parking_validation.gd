extends SceneTree
const M=preload("res://scripts/core/cafe_model.gd")
const P=preload("res://scripts/world/cafe_parking.gd")
const C=preload("res://scripts/persistence/cafe_runtime_codec.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():
 var m=M.new();m.parking_owned=true;m.parking_paid_cost=P.PRICE;P.reserve(m,4)
 var source=C.new().encode(P.snapshot(m))
 for field in ["id","bay","phase","car_position","car_heading","car_route","car_index","members"]:
  var raw=source.duplicate(true);raw.visits[0][field]=null
  check(not P.validate(raw,[],[],m._next_customer_id,true).ok,"reject missing car field "+field)
 for field in ["walk_origin","walk_position","walk_heading","walk_route","walk_index","cancelled"]:
  var raw=source.duplicate(true);raw.visits[0].members[0][field]=null
  check(not P.validate(raw,[],[],m._next_customer_id,true).ok,"reject malformed member motion "+field)
 for fault in ["empty","off-route","nonfinite","premature-departure"]:
  var raw=P.snapshot(m).duplicate(true)
  match fault:
   "empty":raw.visits[0].car_route=[]
   "off-route":raw.visits[0].car_position.x+=1
   "nonfinite":raw.visits[0].car_route[0]=Vector2(INF,0)
   "premature-departure":raw.visits[0].phase="car_departing"
  check(not P.validate(C.new().encode(raw),[],[],m._next_customer_id,true).ok,"reject inconsistent car "+fault)
 # A cancelled passenger can be boarded without starting its inward walk.
 # Keep that valid shape as the control for incomplete boarded records.
 var boarded=P.snapshot(m).duplicate(true);var boarded_car=boarded.visits[0]
 boarded_car.phase="car_departing";boarded_car.cancelled=true
 boarded_car.car_position=P.bay_point(int(boarded_car.bay));boarded_car.car_heading=Vector2.UP
 boarded_car.car_route=P.car_route(int(boarded_car.bay),true);boarded_car.car_index=0
 for member in boarded_car.members:member.phase="boarded";member.cancelled=true;member.slot=-1
 var boarded_source=C.new().encode(boarded)
 check(P.validate(boarded_source,[],[],m._next_customer_id,true).ok,"complete cancelled boarded control validates")
 for field in ["cancelled","walk_index"]:
  for fault in ["missing","null","wrong-type"]:
   var bad=boarded_source.duplicate(true)
   if fault=="missing":bad.visits[0].members[0].erase(field)
   else:bad.visits[0].members[0][field]=null if fault=="null" else "invalid"
   var input_before=bad.duplicate(true);var live_before=P.snapshot(m).duplicate(true)
   check(not P.validate(bad,[],[],m._next_customer_id,true).ok,"reject boarded "+fault+" "+field)
   check(bad==input_before and P.snapshot(m)==live_before,"boarded refusal preserves input/live state "+fault+" "+field)
 for i in range(450):P.advance(m,.1)
 check(not m.customers.is_empty(),"actual admitted binding sample")
 var guest=m.customers[0];var original=guest.duplicate(true)
 for field in ["parking_car_id","parking_member_id","appearance_sequence","species_index","appearance_recipe"]:
  guest.erase(field)
  check(not P.validate(C.new().encode(P.snapshot(m)),m.customers,m.outside_queue,m._next_customer_id,true).ok,"missing authoritative guest binding rejected "+field)
  guest.clear();guest.merge(original,true)
 print("PARKING_VALIDATION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
