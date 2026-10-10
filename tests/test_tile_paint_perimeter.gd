extends SceneTree
const Preview=preload("res://scripts/cafe_tile_paint_preview.gd")
class Artist:
 extends RefCounted
 var fills=[]
 var seams=[]
 var outlines=[]
 func iso(x,z):return Vector2(x,z)
 func poly(points,color):fills.append({"points":points,"color":color})
 func line(a,b,color,width):seams.append({"a":a,"b":b,"color":color,"width":width})
 func draw_multiline(points,color,width,_aa):outlines.append({"points":points,"color":color,"width":width})
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label)
func _init():
 for example in [
  {"cells":[Vector2i(0,0)],"edges":4},
  {"cells":[Vector2i(0,0),Vector2i(1,0),Vector2i(2,0),Vector2i(3,0)],"edges":10},
  {"cells":[Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)],"edges":8},
  {"cells":[Vector2i(0,0),Vector2i(1,0),Vector2i(0,1)],"edges":8},
  {"cells":[Vector2i(0,0),Vector2i(3,0)],"edges":8}]:
  var cells=example.cells;var edges=Preview.perimeter(cells)
  check(edges.size()==example.edges,"only region perimeter survives shared edges")
  for material in ["warm_oak","cream_tile","sage_tile"]:
   for valid in [true,false]:
    var artist=Artist.new();Preview.draw(artist,cells,material,valid)
    check(artist.fills.size()==cells.size(),"chosen finish covers whole cells without gaps")
    check(artist.fills[0].color==Preview.Ground.floor_palette(material)[0],"preview uses installed floor palette")
    check(artist.outlines.size()==1 and artist.outlines[0].points.size()==example.edges*2,"one perimeter draw, no per-cell boxes")
    check(artist.outlines[0].width<=1.5,"fine perimeter width")
    check(artist.seams.size()>=cells.size()*2,"natural material seams remain")
 check(Preview.unique_cells([Vector2i.ZERO,Vector2i.ZERO]).size()==1,"revisited cells cannot duplicate edges")
 print("TILE_PAINT_PERIMETER_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
