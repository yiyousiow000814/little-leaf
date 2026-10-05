extends SceneTree
const Art=preload("res://scripts/illustrated_cafe.gd")
const Character=preload("res://scripts/directional_character_art.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():
 var art=Art.new()
 for species in range(3):
  for role in ["customer","chef","waiter","cleaner","cashier"]:
   var staff=role!="customer"
   for mirror in [-1.0,1.0]:
    for back in [false,true]:
     for moving in [false,true]:
      for seated in [0.0,.5,1.0]:
       for phase in [0.0,.17,.5,.83]:
        var pose={"mirror":mirror,"view_back":back,"seat_mix":seated,"blend":.8,"phase":phase}
        var saved=pose.duplicate(true)
        var body=Character.body_offset(pose,moving,phase)
        var bounds=Character.head_bounds(species,false,staff and role=="chef")
        var old=body+Vector2(bounds.get_center().x,bounds.position.y-18.0)
        old.x*=mirror
        var anchor=art._character_bubble_anchor(species,staff,moving,pose,role)
        check(anchor.is_equal_approx(old+Vector2(5,0)),"Only the approved screen-right shift may change")
        check(is_equal_approx(anchor.x-5,body.x*mirror),"Tail tip must align with head center at either facing")
        check(is_equal_approx(body.y+bounds.position.y-(anchor.y+13),5),"Ear/hat clearance must stay five local pixels")
        check(pose==saved,"Bubble placement must not mutate simulation or pose")
        for scale in [.5,1.0,1.55,2.0]:
         check(((anchor-old)*scale).is_equal_approx(Vector2(5*scale,0)),"Zoom must scale the same rightward shift")
         check(is_equal_approx((anchor.x-5)*scale,body.x*mirror*scale),"Scaled tail must still target the head")
 # This is a presentation-only anchor. Nearby actors and camera translation
 # must not alter its relation to its own head or mutate other actors.
 var pose={"mirror":-1.0,"view_back":true,"seat_mix":1.0,"phase":0.0}
 var anchor=art._character_bubble_anchor(1,false,false,pose)
 for origin in [Vector2(40,170),Vector2(1560,170),Vector2(40,1160),Vector2(1560,1160),Vector2(760,700),Vector2(800,700)]:
  var head=Character.body_offset(pose,false,0)
  head.x*=-1
  check(is_equal_approx((origin+anchor-Vector2(5,0)).x,(origin+head).x),"World placement must preserve tail ownership")
 art.free()
 print("CHARACTER_BUBBLE_RESULT checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
