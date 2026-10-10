extends SceneTree
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
   check(art.ellipses.is_empty(),"No chair ground shadow or contact patches")
   check(art.surfaces.size()==2,"Seat top and thickness must remain")
   for index in range(4):
    var q:Vector2=corners[index]
    var floor=art._chair_point(local_offset,q.x*1.1,q.y*1.1,0,rotation)
    check(art.lines[index].start.is_equal_approx(floor),"Leg tip must reach its projected floor point")
    check(art.lines[index].finish.is_equal_approx(art._chair_point(local_offset,q.x,q.y,17,rotation)),"Upper leg and seat height must stay put")
   var seat=[]
   for q in [Vector2(-.35,-.35),Vector2(.35,-.35),Vector2(.35,.35),Vector2(-.35,.35)]:seat.append(art._chair_point(local_offset,q.x,q.y,18,rotation))
   check(art.surfaces[1].points==seat,"Seat surface must keep the established 18px height")
   for index in range(4):check(art.surfaces[0].points[index]==seat[index]+Vector2(0,1.25),"Thin seat rim retains material-plane shading")
   art.lines.clear();art.ellipses.clear();art.surfaces.clear()
   art._chair(local_offset,rotation,true,"basic")
   check(art.ellipses.is_empty(),"Rear rail pass must not duplicate floor shadows")
 for style in ["cottage","retro","refined"]:
  for rotation in range(4):
   art.lines.clear();art.ellipses.clear();art.surfaces.clear()
   art._chair(Vector2.ZERO,rotation,false,style)
   check(art.ellipses.is_empty(),"Styled seat must not project a floor oval")
   var lower=art.surfaces[0].points;var top=art.surfaces[1].points
   for index in range(4):check(lower[index]==top[index]+Vector2(0,1.25),"Styled seat keeps a thin material rim")
 art.free()
 print("CHAIR_GROUND_CONTACT_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
