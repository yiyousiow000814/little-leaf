extends SceneTree
const Feedback=preload("res://scripts/cafe_placement_feedback.gd")
class Artist:
 extends RefCounted
 var fills=[]
 var lines=[]
 var circles=[]
 func poly(points,color):fills.append({"points":points,"color":color})
 func line(a,b,color,width):lines.append({"a":a,"b":b,"color":color,"width":width})
 func draw_circle(at,radius,color):circles.append({"at":at,"radius":radius,"color":color})
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label)
func _init():
 var corners=[Vector2(30,0),Vector2(60,15),Vector2(30,30),Vector2(0,15)]
 for valid in [true,false]:
  var expected=Feedback.fill_color(valid)
  check(expected.a==1.0,"state fill is opaque")
  for base in [Color("fff7dd"),Color("10293c"),Color("cc7766"),Color("7b886e")]:
   check(base.blend(expected)==expected,"floor color cannot alter validity color")
  var ground=Artist.new();Feedback.draw_cell(ground,corners,valid)
  check(ground.fills.size()==1 and ground.fills[0].color==expected,"ground uses fixed semantic fill")
  check(ground.lines.size()==8,"contrasting border has opaque light and semantic edges")
  var tiles=Artist.new();Feedback.draw_cell(tiles,corners,valid,true,false)
  check(tiles.fills.is_empty(),"outline-only drawing does not add a fill")
  check(tiles.circles.size()==1 and tiles.lines.size()==10,"active furniture outline adds explicit check or cross")
  var active=Artist.new();Feedback.draw_cell(active,corners,valid,true)
  check(active.fills[0].color==expected and active.circles.size()==1,"active preview preserves semantic color and symbol")
 print("PLACEMENT_FEEDBACK_COLORS_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
