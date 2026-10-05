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
 for symbol in ["…","!"]:
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
 print("BUBBLE_SYMBOL_CLARITY_RESULT checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
