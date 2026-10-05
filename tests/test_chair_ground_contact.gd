extends SceneTree
const Atlas=preload("res://scripts/furniture_static_atlas.gd")
class RecordingArt extends "res://scripts/illustrated_cafe.gd":
 var lines=[]
 var ellipses=[]
 var surfaces=[]
 func line(start:Vector2,finish:Vector2,color,width=1.0):lines.append({"start":start,"finish":finish,"color":color,"width":width})
 func ellipse(at:Vector2,size:Vector2,color):ellipses.append({"at":at,"size":size,"color":color})
 func rounded_poly(points:Array,radius:float,color):surfaces.append({"points":points,"radius":radius,"color":color})
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr(label)
func _initialize():
 var art=RecordingArt.new()
 var corners=[Vector2(-.28,-.28),Vector2(.28,-.28),Vector2(-.28,.28),Vector2(.28,.28)]
 for rotation in range(4):
  for local_offset in [Vector2.ZERO,Vector2(13,-4)]:
   art.lines.clear();art.ellipses.clear();art.surfaces.clear()
   art._chair(local_offset,rotation,false,"basic")
   check(art.lines.size()==4,"Four chair legs must remain")
   check(art.ellipses.size()==5,"One broad shadow and four contact patches")
   check(art.surfaces.size()==2,"Seat top and thickness must remain")
   for index in range(4):
    var q:Vector2=corners[index]
    var floor=art._chair_point(local_offset,q.x*1.1,q.y*1.1,0,rotation)
    check(art.lines[index].start.is_equal_approx(floor),"Leg tip must reach its projected floor point")
    check(art.lines[index].finish.is_equal_approx(art._chair_point(local_offset,q.x,q.y,17,rotation)),"Upper leg and seat height must stay put")
    check(art.ellipses[index+1].at.is_equal_approx(floor),"Contact shadow must share the foot anchor")
    check(art.ellipses[index+1].size==Vector2(2.2,1.1),"Contact remains a small floor-aligned 2:1 patch")
    check(is_equal_approx(art.ellipses[index+1].color.a,.14),"Contact opacity remains restrained")
    var patch=Rect2(floor-local_offset-Vector2(2.55,1.45),Vector2(5.1,2.9))
    check(Atlas.bounds("chair_seat").encloses(patch),"Static atlas must retain each contact and antialias fringe")
    for scale in [.5,1.0,2.2,4.0]:
     for dock in [Vector2.ZERO,Vector2(9.91,-4.96),Vector2(-11.7,5.85)]:
      var transform=Transform2D(0,Vector2.ONE*scale,0,Vector2(750,550)+dock)
      check((transform*art.lines[index].start).is_equal_approx(transform*art.ellipses[index+1].at),"Visual docking must move feet and shadows together")
   var seat=[]
   for q in [Vector2(-.35,-.35),Vector2(.35,-.35),Vector2(.35,.35),Vector2(-.35,.35)]:seat.append(art._chair_point(local_offset,q.x,q.y,18,rotation))
   check(art.surfaces[1].points==seat,"Seat surface must keep the established 18px height")
   art.lines.clear();art.ellipses.clear();art.surfaces.clear()
   art._chair(local_offset,rotation,true,"basic")
   check(art.ellipses.is_empty(),"Rear rail pass must not duplicate floor shadows")
 art.free()
 print("CHAIR_GROUND_CONTACT_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
