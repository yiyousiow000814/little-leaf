extends SceneTree
const Character=preload("res://scripts/directional_character_art.gd")
const Furniture=preload("res://scripts/illustrated_furniture.gd")
class Artist extends Node2D:
 var head_at=Vector2.ZERO
 func col(c):return Color(c)
 func art_polyline(_p,_c,_w):pass
 func _face_ellipse(_p,_r,_c):pass
 func _face_line(_p,_q,_c,_w):pass
 func _round_limb(_p,_q,_c,_w):pass
 func rounded_poly(_p,_r,_c):pass
 func poly(_p,_c):pass
 func ellipse(_p,_r,_c):pass
 func line(_p,_q,_c,_w):pass
 func _draw_head(p,_s,_b,_blink,_hat,_blocked,_view):head_at=p
 func _action_prop(_p,_carry,_a,_t,_payload,_tool,_hand,_tip,_floor):pass
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var artist=Artist.new();var character=Character.new()
 for species in range(3):
  for back in [false,true]:
   for seat in [0.0,1.0]:
    for action in ["idle","carrying_plate"]:
     var settings={"action":action,"seat_mix":seat,"payload":"plate" if action=="carrying_plate" else "none"}
     var base=character.draw(artist,Vector2.ZERO,species,back,false,0,true,false,settings)
     var base_head=artist.head_at
     for variant in ["baseline","A","B"]:
      settings["proportion_study"]=variant
      var p=character.draw(artist,Vector2.ZERO,species,back,false,0,true,false,settings)
      var expected=(3.0 if variant=="A" else (5.0 if variant=="B" else 0.0)) if seat==0 else (2.0 if variant=="A" else (3.0 if variant=="B" else 0.0))
      check(p.near_foot.is_equal_approx(base.near_foot) and p.far_foot.is_equal_approx(base.far_foot),"Ground/seat foot anchors stay fixed")
      check(artist.head_at.is_equal_approx(base_head-Vector2(0,expected)),"Intact head translates by declared amount only")
      check(absf(base.near_shoulder.y-p.near_shoulder.y-expected)<.0001,"Declared shoulder lift is applied")
      if action=="carrying_plate":check(absf(p.near_hand.distance_to(p.carry)-base.near_hand.distance_to(base.carry))<.0001,"Carried prop remains attached")
 for rotation in range(4):
  var toward=-Vector2(0,1).rotated(rotation*PI/2.0)
  var mirror=-1.0 if toward.x-toward.y<0 else 1.0
  var back=toward.x+toward.y<0
  var ground=Vector2((toward.x-toward.y)*39,(toward.x+toward.y)*19.5)*(1.0-Character.CookingPose.WORK_INSET)
  for variant in ["baseline","A","B"]:
   for sample in 50:
    var seconds=sample*.1
    var reach=(ground+Furniture.stove_handle_points(rotation)[1]+Character.CookingPose.vessel(seconds).pot)*Vector2(mirror,1)
    var p=character.draw(artist,Vector2.ZERO,0,back,false,0,true,false,{"action":"cooking","cooking_grip":true,"reach":reach,"cooking_elapsed":seconds,"proportion_study":variant})
    var grip=p.cooking_pose
    check(grip.grip_error<.5,"Variant retains actual moving pot contact")
    check(absf(grip.shoulder.distance_to(grip.elbow)-Character.CookingPose.UPPER_ARM)<.0001,"Upper arm stays fixed length")
    check(absf(grip.elbow.distance_to(grip.hand)-Character.CookingPose.FOREARM)<.0001,"Forearm stays fixed length")
 artist.free()
 print("PROPORTION_STUDY_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"production_default_changed":false}))
 quit(0 if failures.is_empty() else 1)
