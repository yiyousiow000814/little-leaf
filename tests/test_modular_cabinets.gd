extends SceneTree
const Furniture=preload("res://scripts/illustrated_furniture.gd")
const Atlas=preload("res://scripts/furniture_static_atlas.gd")
const Motion=preload("res://scripts/illustrated_motion.gd")
const Checkout=preload("res://scripts/cafe_checkout_art.gd")
const Wash=preload("res://scripts/cafe_sink_wash_art.gd")
class Probe extends Node2D:
 var points=[]
 var surfaces=[]
 func rounded_poly(shape,_radius,color):
  points.append_array(shape);surfaces.append({"points":shape,"color":color})
 func poly(shape,_color):points.append_array(shape)
 func line(a,b,_color,_width=1):points.append(a);points.append(b)
 func _face_line(a,b,_color,_width=1):points.append(a);points.append(b)
 func _face_ellipse(at,radius,_color):points.append(at-radius);points.append(at+radius)
 func ellipse(at,radius,_color):points.append(at-radius);points.append(at+radius)
 func outlined_ellipse(at,radius,_fill,_stroke,_width=1):points.append(at-radius);points.append(at+radius)
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var f=Furniture.new();var p=Probe.new();root.add_child(p)
 var measures=[]
 for rotation in range(4):
  for kind in ["counter","sink","beverage","register","stove"]:
   p.points.clear();p.surfaces.clear()
   if kind=="stove":f.draw_static_part(p,"stove_base",Vector2.ZERO,rotation)
   else:f.draw_item(p,kind,Vector2.ZERO,rotation,0)
   var top_color={"counter":"e6cca0","sink":"cbd7be","beverage":"e9dfc0","register":"e7d7ad","stove":"d9deca"}[kind]
   var top=[]
   for surface in p.surfaces:
    if surface.color==top_color:top=surface.points
   check(top.size()==4,"one complete modular top "+kind)
   for i in range(4):
    var screen_edge:Vector2=top[(i+1)%4]-top[i]
    var ground_edge=Vector2(screen_edge.x/78+screen_edge.y/39,screen_edge.y/39-screen_edge.x/78)
    check(is_equal_approx(ground_edge.length(),1.),"each true ground edge is one full cell "+kind+str(rotation))
    check(is_zero_approx(ground_edge.x) or is_zero_approx(ground_edge.y),"top edge follows one grid axis "+kind+str(rotation))
   var bounds=Rect2(top[0],Vector2.ZERO)
   for q in top:bounds=bounds.expand(q)
   check(is_equal_approx(bounds.size.x,78) and is_equal_approx(bounds.size.y,39),"one-cell top dimensions "+kind+str(rotation))
   # The right tile translation is (39,19.5); its near-left edge must match.
   var shared=0
   for a in top:
    for b in top:
     if a.distance_to(b+Vector2(39,19.5))<.001:shared+=1
   check(shared==2,"adjacent tops share exact edge "+kind+str(rotation))
   if kind!="register":
    var part={"beverage":"beverage_base","stove":"stove_base"}.get(kind,kind)
    p.points.clear();f.draw_static_part(p,part,Vector2.ZERO,rotation)
    for q in p.points:check(Atlas.bounds(part).grow(-1).has_point(q),"atlas guard "+kind+str(rotation))
   measures.append({"kind":kind,"rotation":rotation,"top_width":bounds.size.x,"top_depth":bounds.size.y})
  # Measure the exact settled shoe polygon in floor coordinates. This does
  # not substitute a root-only clearance check for the actual shoe envelope.
  var heading=-Vector2.DOWN.rotated(rotation*PI/2)
  var axis=Motion._shoe_axis(heading);var across=axis.orthogonal()
  var inward=0.0
  for side in [-1.,1.]:
   var center=Motion._rest_center(side,heading)
   for q in [Vector2(-3.9,-1.25),Vector2(-2.8,-2),Vector2(1.4,-2.2),Vector2(3.5,-1.6),Vector2(4.1,-.3),Vector2(3.5,1.45),Vector2(1.4,2.15),Vector2(-2.8,1.9),Vector2(-3.9,.95)]:
    var pixel=center+axis*q.x+across*q.y
    var world=Vector2(pixel.x/78+pixel.y/39,pixel.y/39-pixel.x/78)
    inward=maxf(inward,world.dot(heading))
  check(1.-Wash.INSET>.5,"wash root outside upper cabinet r"+str(rotation))
  check(1.-Wash.INSET-inward>.33+.02,"shoe clears recessed plinth by .02 cell r"+str(rotation))
  for cashier in [false,true]:
   var payment_heading=heading*(-1. if cashier else 1.)
   var payment_inset=Checkout.payment_inset(payment_heading,rotation,cashier)
   var mirror=-1. if payment_heading.x-payment_heading.y<0 else 1.
   var back=payment_heading.x+payment_heading.y<0
   var ground=Vector2((payment_heading.x-payment_heading.y)*39,(payment_heading.x+payment_heading.y)*19.5)*(1.-payment_inset)
   var reach=(ground+Checkout.contact_surface(rotation,cashier))*Vector2(mirror,1)
   var payment=Checkout.payment_pose(Vector2(7,-24) if back else Vector2(-7,-24),Vector2(-6,-26.5) if back else Vector2(6,-26.5),reach,.52,cashier)
   check(payment.hand.distance_to(reach)<.03,"payment fixed-arm contact r"+str(rotation))
   check(1.-payment_inset>.5,"payment root outside upper cabinet r"+str(rotation))
   measures.append({"rotation":rotation,"cashier":cashier,"payment_inset":payment_inset,"payment_root_distance":1.-payment_inset})
  measures.append({"rotation":rotation,"plinth_shoe_clearance":1.-Wash.INSET-inward-.33,"wash_root_distance":1.-Wash.INSET,"shoe_inward_extent":inward,"wash_shoe_clearance":.5-Wash.INSET-inward,"maximum_clear_inset":.5-inward})
 print("MODULAR_CABINETS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"measurements":measures}))
 quit(0 if failures.is_empty() else 1)
