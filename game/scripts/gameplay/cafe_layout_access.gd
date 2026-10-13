extends RefCounted
## Operational workface diagnostics; physical placement has separate geometry guards.
static func requires_access(kind:String)->bool:return kind in ["stove","beverage","sink","counter","register","table","bin"]

static func issues(model,layout:Array)->Array:
 var typed_layout:Array[Dictionary]=[];typed_layout.assign(layout)
 var result=[]
 var reachable=model._furniture_actor_component(model.ENTRY_LANDING,layout)
 for item in layout:
  var kind=str(item.kind);var center=Vector2i(int(item.x),int(item.z))
  var faces=[]
  if kind in ["stove","beverage","sink","counter","register"]:
   var front=model.workface_cell(item);faces.append({"side":"front","cell":front})
   if kind in ["counter","register"]:faces.append({"side":"back","cell":center*2-front})
  elif kind in ["table","bin"]:
   var sides=model.table_service_cells(item,typed_layout) if kind=="table" else model.bin_service_cells(item,typed_layout)
   var usable=false
   for side in sides:
    if reachable.has(side):usable=true;break
   if usable:continue
   var preferred=center+(model._table_service_direction_in(item,typed_layout) if kind=="table" else Vector2i.DOWN)
   faces.append({"side":"service","cell":preferred})
  for face in faces:
   var at:Vector2i=face.cell
   if reachable.has(at) and not model.edge_blocked(center,at):continue
   var blocker=-1
   for other in layout:
    if str(other.kind)!="rug" and Vector2i(int(other.x),int(other.z))==at:blocker=int(other.id);break
   var label="Table service side" if kind=="table" else ("Bin service side" if kind=="bin" else kind.capitalize()+" "+str(face.side))
   result.append({"code":"blocked_workface","item_id":int(item.id),"kind":kind,"station_cell":center,"cell":at,"side":str(face.side),"blocking_item_id":blocker,"blocked_edge":model.edge_blocked(center,at),"reachable":reachable.has(at),"reason":label+" blocked · keep a connected working tile clear"})
 return result
