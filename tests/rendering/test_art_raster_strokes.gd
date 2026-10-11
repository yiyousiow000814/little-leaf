extends SceneTree
const Art=preload("res://scripts/illustrated_cafe.gd")
var checks=0
var failures=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize():run.call_deferred()
func run():
 for scale in [.25,.5,1.0,2.0,4.0,8.0]:
  for angle in [0.0,.4,PI]:
   for mirror in [-1.0,1.0]:
    var transform=Transform2D(angle,Vector2(scale*mirror,scale),0,Vector2(71,129))
    check(is_equal_approx(Art.art_stroke_scale(transform),scale),"Uniform or mirrored scale changed")
    var outer=Transform2D(.2,Vector2.ONE*1.5,0,Vector2(32,17))
    var point=Vector2(-9.5,-60.2)
    check((outer*(outer.affine_inverse()*(outer*transform*point))).is_equal_approx(outer*transform*point),"Raster stroke position changed")
    check(is_equal_approx(Art.art_stroke_scale(outer*transform),scale*1.5),"Parent scale omitted")
 check(Art.art_stroke_scale(Transform2D(0,Vector2(2,3),0,Vector2.ZERO))==0,"Nonuniform stroke must use original path")
 check(Art.art_stroke_scale(Transform2D(0,Vector2(2,2),.3,Vector2.ZERO))==0,"Sheared stroke must use original path")
 check(Art.art_stroke_scale(Transform2D(0,Vector2.ZERO,0,Vector2.ZERO))==0,"Zero scale must use original path")
 var artist=Art.new()
 root.add_child(artist)
 artist._stroke_to_raster=Transform2D.IDENTITY
 artist._stroke_raster_scale=8.0
 check(not artist.art_cache_covers(Rect2(1,1,20,20),4.0),"Visible magnified art must use source geometry")
 check(not artist.art_cache_covers(Rect2(-1000,-1000,20,20),4.0),"Magnified offscreen art must retain source geometry before panning into view")
 artist._stroke_raster_scale=4.0
 check(artist.art_cache_covers(Rect2(1,1,20,20),4.0),"Native-resolution cache should remain active")
 artist._stroke_raster_scale=.8
 check(artist.art_cache_covers(Rect2(1,1,20,20),4.0),"Normal zoom should remain cached")
 check(artist.art_cache_covers(Rect2(-1000,-1000,20,20),4.0),"Offscreen art within atlas resolution remains cached")
 artist.free()
 print("ART_RASTER_STROKE_TESTS checks=",checks," failures=",failures)
 quit(0 if failures==0 else 1)
