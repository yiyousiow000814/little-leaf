extends RefCounted
## Current floor facts, independent of selected product, rotation and wallet.
var signature:Array=[]
var cells:Dictionary={}
var builds=0
func refresh(model)->Dictionary:
 var claims=model.checkout_claims()
 var next=[model.get_instance_id(),hash(model.items),hash(model.owned_parcels),hash(model.built_walls),hash(model.wall_attachments),hash(model.shell_products),hash(model.shell_segment_products),hash(claims)]
 if next==signature:return cells
 signature=next;cells.clear();builds+=1
 var blocked={model.ENTRANCE:"Entrance",model.ENTRY_LANDING:"Entrance landing"}
 for item in model.items:blocked[Vector2i(item.x,item.z)]="Occupied by "+str(item.kind)
 for at in claims:blocked[at]="Checkout space"
 var reachable=model._furniture_actor_component(model.ENTRY_LANDING,model.items)
 for item in model.items:
  var kind=str(item.kind);var base=Vector2i(item.x,item.z)
  if kind in ["stove","beverage","sink","counter","register"] and model.LayoutAccess.requires_access(kind):
   var front=model.workface_cell(item);blocked[front]=kind.capitalize()+" working side"
   if kind in ["counter","register"]:blocked[base*2-front]=kind.capitalize()+" rear working side"
  elif kind in ["table","bin"]:
   var sides=model.table_service_cells(item) if kind=="table" else model.bin_service_cells(item)
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
