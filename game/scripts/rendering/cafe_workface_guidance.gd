extends RefCounted
## Read-only operational workface facts and blocked-station lookup.
## Physical placement uses its own footprint/body guards; this helper never draws.
static func blocked_station(owner)->Dictionary:
 for staff in owner.staff_states:
  var reason=str(staff.get("art_block_reason",staff.get("blocked_reason",""))).to_lower()
  if not reason.contains("blocked"):continue
  var item=owner.model.get_item(int(staff.get("blocked_target_id",-1)))
  if not owner.editing and str(item.get("kind",""))=="stove":continue
  if not item.is_empty() and str(item.kind) in ["stove","beverage","sink","counter","bin","register"]:return item
 return {}
static func describe(owner)->Array:
 if not owner.editing:return []
 var item=owner.model.get_item(owner.selected_id)
 var interaction=owner.interaction
 var preview=interaction!=null and interaction.preview_active
 if preview:
  item={"id":interaction.drag_item_id,"kind":interaction.drag_kind,"x":interaction.drag_cell.x,"z":interaction.drag_cell.y,"rot":interaction.drag_rotation}
 if item.is_empty() or str(item.kind) not in ["stove","beverage","sink","counter","bin","register"]:return []
 var layout:Array[Dictionary]=[]
 for other in owner.model.items:
  if int(other.id)!=int(item.id):layout.append(other)
 layout.append(item)
 var base=Vector2i(item.x,item.z)
 var front=owner.model.workface_cell(item)
 var cells=[{"cell":front,"reverse":false}]
 if item.kind=="register":cells.append({"cell":base*2-front,"reverse":true})
 if item.kind=="counter":cells.append({"cell":base*2-front,"reverse":true})
 if item.kind=="bin":
  cells=[]
  for direction in [Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT]:cells.append({"cell":base+direction,"reverse":false})
 var bin_cells=owner.model.bin_service_cells(item,layout) if item.kind=="bin" else []
 var reachable=owner.model._sale_reachable_in(layout)
 var station_owned=owner.model.is_floor_owned(base)
 for marker in cells:
  var facing=item.duplicate()
  if marker.reverse:facing.rot=posmod(int(item.rot)+2,4)
  marker["clear"]=station_owned and (bin_cells.has(marker.cell) if item.kind=="bin" else owner.model._workface_open_in(facing,layout)) and reachable.has(marker.cell)
  marker["station_cell"]=base
  marker["item_id"]=int(item.id)
 return cells
