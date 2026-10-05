extends SceneTree
const Character=preload("res://scripts/directional_character_art.gd")
const Occlusion=preload("res://scripts/character_arm_occlusion.gd")
const Checkout=preload("res://scripts/cafe_checkout_art.gd")
class Artist extends Node2D:
 var commands=[]
 func col(c):return Color(c)
 func art_polyline(_points,_color,_width):pass
 func _face_ellipse(_p,_r,_c):pass
 func _face_line(_p,_q,_c,_w):pass
 func _round_limb(p,q,c,w):commands.append({"kind":"limb","start":p,"finish":q,"color":c,"width":w})
 func rounded_poly(p,r,c):commands.append({"kind":"shape","points":p,"radius":r,"color":c})
 func poly(p,c):commands.append({"kind":"clipped","points":p,"color":c})
 func ellipse(_p,_r,_c):pass
 func line(_p,_q,_c,_w):pass
 func _draw_head(_p,_s,_b,_blink,_hat,_blocked,_view):commands.append({"kind":"head"})
 func _action_prop(_p,_carry,_action,_t,_payload,_tool,_work_hand,_tip,_floor):pass
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok and not failures.has(label):failures.append(label);printerr(label)
func area(p:PackedVector2Array)->float:
 var result=0.0
 for i in p.size():result+=p[i].cross(p[(i+1)%p.size()])
 return absf(result)*.5
func _initialize():
 var artist=Artist.new();var character=Character.new()
 for back in [false,true]:
  var near=Vector2(7,-24) if back else Vector2(-7,-24)
  var far=Vector2(-6,-26.5) if back else Vector2(6,-26.5)
  for species in range(3):
   for action in ["idle","standby","blocked"]:
    for phase in [0.0,.25,.5,.75,1.0]:
     var g=character.draw(artist,Vector2.ZERO,species,back,false,phase,true,false,{"action":action,"progress":phase,"role":"cashier"})
     check(g.near_shoulder==near and g.far_shoulder==far,"No shoulder is lowered or moved")
     check(g.near_hand==near+Vector2.DOWN*10.5,"Standing near hand hangs vertically")
     check(g.far_hand==far+Vector2.DOWN*10.5,"Standing far hand hangs vertically")
   var seated=character.draw(artist,Vector2.ZERO,species,back,false,0.0,false,false,{"action":"standby","seat_mix":1.0})
   check(not is_equal_approx(seated.near_hand.x,seated.near_shoulder.x),"Standing rest does not replace seated pose")
   var carrying=character.draw(artist,Vector2.ZERO,species,back,false,0.0,true,false,{"action":"carrying_plate","payload":"plate","role":"cashier"})
   var expected=near+(Character.carry_anchor(back)-near).normalized()*10.5
   check(carrying.near_hand.is_equal_approx(expected),"Carried plate hand remains exact")
   for angle in range(0,360,5):
    var hand=far+Vector2.from_angle(deg_to_rad(angle))*10.5
    var parts=Occlusion.visible_far_arm(far,hand,4.4,back,false,species)
    var masks:Array[PackedVector2Array]=[Occlusion.rounded(Occlusion.torso_points(back),3.5)]
    masks.append_array(Occlusion.head_masks(back,false,species,Vector2.ZERO))
    for part in parts:
     check(not Geometry2D.is_point_in_polygon(far,part),"Far overlay exposes its shoulder root")
     for mask in masks:
      var overlap=0.0
      for polygon in Geometry2D.intersect_polygons(part,mask):overlap+=area(polygon)
      check(overlap<.0005,"Far overlay paints through body/head")
    check(far.distance_to(hand)>10.4999 and far.distance_to(hand)<10.5001,"Occlusion does not alter arm length")
  var outside_hand=far+Vector2(-10.5 if back else 10.5,0)
  var outside_parts=Occlusion.visible_far_arm(far,outside_hand,4.4,back)
  check(outside_parts.any(func(p):return Geometry2D.is_point_in_polygon(outside_hand,p)),"Exposed working forearm remains visible")
 # Front payment previously repainted the far shoulder over its shirt.
 artist.commands.clear()
 var settings={"action":"taking_payment","progress":.5,"reach":Vector2(16,-22),"role":"cashier","shirt":"b68b92"}
 var full=character.draw(artist,Vector2.ZERO,2,false,false,0.0,true,false,settings)
 check(not full.payment_pose.use_near,"Fixture selects the reported far arm")
 var far_indices=[];var torso_index=-1
 for i in artist.commands.size():
  var c=artist.commands[i]
  if c.kind=="limb" and c.start==full.far_shoulder and is_equal_approx(c.width,4.4):far_indices.append(i)
  if c.kind=="shape" and c.color is String and c.color=="b68b92" and torso_index<0:torso_index=i
 check(far_indices.size()==1 and far_indices[0]<torso_index,"Far arm is drawn once behind torso")
 artist.commands.clear();settings.reach_overlay=true
 var over=character.draw(artist,Vector2.ZERO,2,false,false,0.0,true,false,settings)
 check(over.far_shoulder==full.far_shoulder and over.far_hand==full.far_hand,"Overlay preserves exact pose/contact")
 check(artist.commands.filter(func(c):return c.kind=="limb").is_empty(),"Overlay does not repaint a full arm or resting near arm")
 check(not artist.commands.filter(func(c):return c.kind=="clipped").is_empty(),"Overlay redraws visible distal forearm")
 for cashier in [false,true]:
  for rotation in range(4):
   var direction=Vector2(0,1 if cashier else -1).rotated(rotation*PI/2)
   var mirror=-1.0 if direction.x-direction.y<0 else 1.0;var back=direction.x+direction.y<0
   var axis=Vector2((direction.x-direction.y)*39*mirror,(direction.x+direction.y)*19.5)
   var surface=Checkout.contact_surface(rotation,cashier);surface.x*=mirror
   var reach=surface+axis*(1.0-Checkout.payment_inset(direction,rotation,cashier))
   for phase in [.32,.4,.46,.52,.58,.64,.78]:
    var g=character.draw(artist,Vector2.ZERO,0,back,false,0.0,cashier,false,{"action":"taking_payment" if cashier else "paying","progress":phase,"reach":reach,"role":"cashier"})
    check(g.payment_pose.hand.distance_to(reach)<.37,"Payment contact/intentional tap retained")
 artist.free()
 print("ARM_OCCLUSION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
