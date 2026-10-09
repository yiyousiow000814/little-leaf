extends SceneTree
const Wash=preload("res://scripts/cafe_sink_wash_art.gd")
const Checkout=preload("res://scripts/cafe_checkout_art.gd")
const Motion=preload("res://scripts/illustrated_motion.gd")
func inward(heading:Vector2)->float:
 var axis=Motion._shoe_axis(heading);var across=axis.orthogonal();var extent=0.0
 for side in [-1.,1.]:
  var center=Motion._rest_center(side,heading)
  for q in [Vector2(-3.9,-1.25),Vector2(-2.8,-2),Vector2(1.4,-2.2),Vector2(3.5,-1.6),Vector2(4.1,-.3),Vector2(3.5,1.45),Vector2(1.4,2.15),Vector2(-2.8,1.9),Vector2(-3.9,.95)]:
   var pixel=center+axis*q.x+across*q.y
   extent=maxf(extent,Vector2(pixel.x/78+pixel.y/39,pixel.y/39-pixel.x/78).dot(heading))
 return extent
func _initialize():
 var rows=[]
 for scale in [1.,1.25,1.40]:
  for rotation in range(4):
   var heading=-Vector2.DOWN.rotated(rotation*PI/2)
   var inset=.5-inward(heading)*scale-.01
   var mirror=-1. if heading.x-heading.y<0 else 1.;var back=heading.x+heading.y<0
   var ground=Vector2((heading.x-heading.y)*39,(heading.x+heading.y)*19.5)*(1.-inset)
   var near=Vector2(7,-24) if back else Vector2(-7,-24)
   var far=Vector2(-6,-26.5) if back else Vector2(6,-26.5)
   var reference={};var max_error=0.0
   for sample in range(16,387):
    var seconds=sample*.05;var g=Wash.geometry(rotation,seconds,1)
    var center=(ground+g.center)*Vector2(mirror,1)/scale
    var axes:Transform2D=g.basis
    var basis=Transform2D(axes.x*Vector2(mirror,1)/scale,axes.y*Vector2(mirror,1)/scale,Vector2.ZERO)
    if reference.is_empty():reference={"center":center,"basis":basis}
    var pose=Wash.pose(near,far,center,basis,seconds,reference)
    max_error=maxf(max_error,maxf(pose.near.error,pose.far.error)*scale)
   rows.append({"scale":scale,"rotation":rotation,"action":"washing","clear_inset":inset,"body_clearance":.01,"max_hand_error_pixels":max_error})
   for cashier in [false,true]:
    var d=heading*(-1. if cashier else 1.)
    mirror=-1. if d.x-d.y<0 else 1.;back=d.x+d.y<0
    near=(Vector2(7,-24) if back else Vector2(-7,-24))*scale
    far=(Vector2(-6,-26.5) if back else Vector2(6,-26.5))*scale
    var min_t=.5+inward(d)*scale+.01
    var axis=Vector2((d.x-d.y)*39*mirror,(d.x+d.y)*19.5)
    var surface=Checkout.contact_surface(rotation,cashier)*Vector2(mirror,1)
    var error=INF;var best_t=min_t
    for shoulder in [near,far]:
     var t=maxf(min_t,-axis.dot(surface-shoulder)/axis.length_squared())
     var distance=(axis*t+surface-shoulder).length()
     if maxf(0,distance-10.5*scale)<error:error=maxf(0,distance-10.5*scale);best_t=t
    rows.append({"scale":scale,"rotation":rotation,"action":"cashier" if cashier else "customer_payment","clear_inset":1-best_t,"body_clearance":.01,"minimum_reach_error_pixels":error})
 print("PLAIN_BODY_CONTACT_STUDY ",JSON.stringify(rows));quit()
