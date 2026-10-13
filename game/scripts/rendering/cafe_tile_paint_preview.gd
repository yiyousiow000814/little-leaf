extends RefCounted
## Show the installed floor palette and seams without placement-status overlays.
## Ownership and payment refusal stay with the model and the existing UI text.
const Ground=preload("res://scripts/rendering/illustrated_ground.gd")
static func unique_cells(targets:Array)->Array:
 var seen={};var result=[]
 for target in targets:
  var cell=Vector2i(int(target.x),int(target.z)) if target is Dictionary else Vector2i(target)
  if not seen.has(cell):seen[cell]=true;result.append(cell)
 return result
static func draw(view,targets:Array,material:String,_valid:bool):
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
