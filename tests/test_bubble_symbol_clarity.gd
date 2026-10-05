extends SceneTree
const Art=preload("res://scripts/illustrated_cafe.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():
 var dots=Art.bubble_symbol_geometry("…")
 var warning=Art.bubble_symbol_geometry("!")
 var angry=Art.bubble_symbol_geometry("angry")
 check(dots.dots.size()==3 and not dots.has("stem"),"Ordering must remain three separate dots")
 check(warning.dots.size()==1 and warning.has("stem"),"Blocked must remain a stem and separate dot")
 check(Art.bubble_symbol_geometry("").is_empty(),"Empty status must draw no mark")
 check(dots.dots[1].is_equal_approx(Vector2.ZERO),"Middle dot must be at oval center")
 check(dots.dots[0].is_equal_approx(-dots.dots[2]),"Dots must be horizontally and vertically balanced")
 check(warning.dots[0].x==0 and warning.stem[0].x==0 and warning.stem[1].x==0,"Exclamation must be on the oval centerline")
 var dot_area=PI*warning.radius*warning.radius
 var stem_area=warning.width*warning.stem[0].distance_to(warning.stem[1])
 var optical_y=(warning.dots[0].y*dot_area+(warning.stem[0].y+warning.stem[1].y)*.5*stem_area)/(dot_area+stem_area)
 check(absf(optical_y)<.25,"Exclamation visual mass must be vertically balanced")
 check(dots=={"dots":[Vector2(-3.5,0),Vector2(0,0),Vector2(3.5,0)],"radius":.85},"Ordering geometry remains exactly unchanged")
 check(warning=={"dots":[Vector2(0,4.0)],"radius":.8,"stem":[Vector2(0,-4.0),Vector2(0,1.5)],"width":1.5},"Staff warning geometry remains exactly unchanged")
 check(angry.has("face_radius") and angry.dots.size()==2 and angry.strokes.size()==3 and not angry.has("stem"),"Impatience is a vector face with two brows and a mouth, never an exclamation or font emoji")
 check(angry.face_radius<10.0,"Round face fits centered inside the unchanged oval")
 check(is_equal_approx(angry.dots[0].x,-angry.dots[1].x) and angry.dots[0].y==angry.dots[1].y,"Eyes are centered symmetrically")
 var left=angry.strokes[0];var right=angry.strokes[1];var mouth=angry.strokes[2]
 check(left[0].y<left[1].y and right[0].y>right[1].y,"Eyebrows angle inward and downward for anger")
 check(mouth[mouth.size()/2].y<mouth[0].y and is_equal_approx(mouth[0].y,mouth[-1].y),"Mouth corners turn downward in a centered frown")
 var ink_mass=2.0*PI*angry.radius*angry.radius
 var ink_moment=ink_mass*angry.dots[0].y
 for stroke in angry.strokes:
  for index in range(stroke.size()-1):
   var mass=stroke[index].distance_to(stroke[index+1])*angry.width
   ink_mass+=mass;ink_moment+=mass*(stroke[index].y+stroke[index+1].y)*.5
  for point in stroke:check(point.length()+angry.width*.5<angry.face_radius,"Every facial stroke stays inside its face")
 check(absf(ink_moment/ink_mass)<.3,"Facial ink is optically centered vertically")
 for symbol in ["…","!","angry"]:
  var mark=Art.bubble_symbol_geometry(symbol)
  for point in mark.dots:
   check(absf(point.x)+mark.radius<13 and absf(point.y)+mark.radius<10,"Mark must remain inside unchanged oval")
  for scale in [.2,.35,.5,.8,1.0,1.55,2.0,4.0,8.0,14.0]:
   for mirror in [-1.0,1.0]:
    for outer_scale in [.8,1.0,2.0]:
     var outer=Transform2D(.0,Vector2.ONE*outer_scale,0,Vector2(13,27))
     # Actor facing affects its head anchor, never status-symbol orientation.
     var anchor=Vector2(2*mirror+32,-67)
     var local=Transform2D(0,Vector2.ONE*scale,0,Vector2(700,800))
     var raster=outer*local
     var inverse=outer.affine_inverse()
     check(is_equal_approx(Art.art_stroke_scale(raster),scale*outer_scale),"Display scale must include canvas scale")
     for point in mark.dots:
      check((outer*(inverse*(raster*(anchor+point)))).is_equal_approx(raster*(anchor+point)),"Raster AA must preserve every dot position")
      check(is_equal_approx(mark.radius*Art.art_stroke_scale(raster),mark.radius*scale*outer_scale),"Dot radius must preserve original authored size")
     if mark.has("stem"):
      check((raster*(anchor+mark.stem[1])-raster*(anchor+mark.stem[0])).y>0,"Exclamation stays upright at every facing")
      check(mark.stem[1].y+mark.width*.5<mark.dots[0].y-mark.radius,"Stem and dot stay visibly separate")
     for stroke in mark.get("strokes",[]):
      for point in stroke:
       check((outer*(inverse*(raster*(anchor+point)))).is_equal_approx(raster*(anchor+point)),"Raster AA preserves the centered face at every zoom and facing")
 print("BUBBLE_SYMBOL_CLARITY_RESULT checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
