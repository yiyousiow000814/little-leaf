extends RefCounted
## Preview floor facts, independent of selected product, rotation and wallet.
## Moving logical furniture is lifted only here; the live model stays unchanged.
var signature:Array=[]
var cells:Dictionary={}
var builds=0
func refresh(model,moving_id:int=-1)->Dictionary:
 var claims=model.checkout_claims()
 var next=[model.get_instance_id(),hash(model.items),hash(model.owned_parcels),hash(model.built_walls),hash(model.wall_attachments),hash(model.shell_products),hash(model.shell_segment_products),hash(claims),moving_id]
 if next==signature:return cells
 signature=next;cells.clear();builds+=1
 var moving_members=model.logical_members(moving_id) if moving_id>=0 else []
 var layout:Array[Dictionary]=[]
 for item in model.items:
  if int(item.id) not in moving_members:layout.append(item)
 var blocked={model.ENTRANCE:"Entrance",model.ENTRY_LANDING:"Entrance landing"}
 for item in layout:blocked[Vector2i(item.x,item.z)]="Occupied by "+str(item.kind)
 for at in claims:blocked[at]="Checkout space"
 var reachable=model._furniture_actor_component(model.ENTRY_LANDING,layout)
 for item in layout:
  var kind=str(item.kind);var base=Vector2i(item.x,item.z)
  if kind in ["stove","beverage","sink","counter","register"] and model.LayoutAccess.requires_access(kind):
   var front=model.workface_cell(item);blocked[front]=kind.capitalize()+" working side"
   if kind in ["counter","register"]:blocked[base*2-front]=kind.capitalize()+" rear working side"
  elif kind in ["table","bin"]:
   var sides=model.table_service_cells(item,layout) if kind=="table" else model.bin_service_cells(item,layout)
   var available=[]
   for at in sides:
    if reachable.has(at):available.append(at)
   # When several sides work, no one of them is mandatory. Preserve only
   # the last usable service side; do not predict a selected item's size.
   if available.size()==1:blocked[available[0]]=kind.capitalize()+" service side"
 for z in model.MAX_DEPTH:
  for x in model.MAX_WIDTH:
   var at=Vector2i(x,z)
   if model.is_floor_owned(at):cells[at]={"blocked":blocked.has(at),"reason":blocked.get(at,"")}
 return cells
