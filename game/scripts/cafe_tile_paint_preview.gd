extends RefCounted
## Real floor palette/seams plus only the outer edge of the previewed region.
## Adjacent selected tiles never receive individual validity boxes or badges.
const Ground=preload("res://scripts/illustrated_ground.gd")
static func unique_cells(targets:Array)->Array:
 var seen={};var result=[]
 for target in targets:
  var cell=Vector2i(int(target.x),int(target.z)) if target is Dictionary else Vector2i(target)
  if not seen.has(cell):seen[cell]=true;result.append(cell)
 return result
static func perimeter(cells:Array)->Array:
 var selected={};var edges=[]
 for cell in cells:selected[cell]=true
 for cell in cells:
  var p=Vector2(cell)
  for side in [[Vector2i.UP,p,p+Vector2.RIGHT],[Vector2i.RIGHT,p+Vector2.RIGHT,p+Vector2.ONE],[Vector2i.DOWN,p+Vector2.ONE,p+Vector2.DOWN],[Vector2i.LEFT,p+Vector2.DOWN,p]]:
   if not selected.has(cell+side[0]):edges.append([side[1],side[2]])
 return edges
static func draw(view,targets:Array,material:String,valid:bool):
 var cells=unique_cells(targets)
 var palette=Ground.floor_palette(material)
 for cell in cells:
  var x=float(cell.x);var z=float(cell.y)
  view.poly([view.iso(x,z),view.iso(x+1,z),view.iso(x+1,z+1),view.iso(x,z+1)],palette[posmod(cell.x+cell.y,2)])
 # Reuse the installed material's natural seams and occasional oak grain.
 for cell in cells:
  var x=float(cell.x);var z=float(cell.y)
  view.line(view.iso(x,z),view.iso(x+1,z),Ground.floor_line(material),.65)
  view.line(view.iso(x,z),view.iso(x,z+1),Ground.floor_line(material),.65)
  if material=="warm_oak" and (cell.x*7+cell.y*13)%11==0:view.line(view.iso(x+.3,z+.4),view.iso(x+.56,z+.4),Color(.69,.56,.35,.13),.6)
 var outline=PackedVector2Array()
 for edge in perimeter(cells):
  outline.append(view.iso(edge[0].x,edge[0].y));outline.append(view.iso(edge[1].x,edge[1].y))
 if not outline.is_empty():view.draw_multiline(outline,Color("6d8e7b") if valid else Color("a54e44"),1.15 if valid else 1.5,true)
