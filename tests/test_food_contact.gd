extends SceneTree
## Cooking is now covered: verify actual draw calls, not obsolete food motion.
const Pose=preload("res://scripts/cooking_tool_pose.gd")
const Furniture=preload("res://scripts/illustrated_furniture.gd")
var checks=0
var failures=[]
class Artist extends Node2D:
 var colors=[]
 var seconds=0.0
 func col(c):return Color(c)
 func art_polyline(_points,_color,_width):colors.append(_color)
 func ellipse(_at,_size,color):colors.append(color)
 func rounded_poly(_points,_radius,color):colors.append(color)
 func poly(_points,color):colors.append(color)
 func line(_a,_b,color,_width=1.0):colors.append(color)
 func outlined_ellipse(_at,_size,color,_edge,_width=1.0):colors.append(color)
 func _round_limb(_a,_b,color,_width):colors.append(color)
 func _stove_vessel_motion(_id):return Pose.vessel(seconds)
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
 var artist=Artist.new()
 var furniture=Furniture.new()
 for rear in [false,true]:
  for sample in 101:
   var seconds=float(sample)*.08
   var shoulder=Vector2(7,-24) if rear else Vector2(-7,-24)
   var pan=Vector2(23.4,-43.7) if rear else Vector2(23.4,-20.3)
   var pose=Pose.pose(shoulder,pan-Pose.body_weight(seconds),seconds)
   artist.colors.clear()
   Pose.draw(artist,Vector2.ZERO,pose,"ffffff","dddddd")
   check(artist.colors.size()>0,"Chef hands still render")
   for color in artist.colors:
    check(Color(color) in [Color("ffffff"),Color("dddddd")],"Chef draws visible food or utensil through lid")
   for rotation in range(4):
    artist.seconds=seconds;artist.colors.clear()
    furniture.draw_stove_vessel(artist,Vector2.ZERO,rotation,1)
    check("b5c2a7" in artist.colors and "c9d1b7" in artist.colors,"Covered lid absent in rotation")
    for food_color in Pose.FOOD_COLOR:check(food_color not in artist.colors,"Cooking vessel exposes ingredients")
 artist.free()
 print("FOOD_CONTACT_TESTS checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
