extends Node2D
## Color-only ground work tiles. This node retains state, never canvas commands.
## Pure presentation: never moves objects or widens
## service access. Counter front remains waiter-only and back chef-only.
var game
var signature=[]
var markers=[]
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
func _refresh():
 if not is_instance_valid(game):return
 if not game.editing:
  signature=[];markers=[]
  return
 var i=game.interaction
 var next=[game.editing,game.selected_id,game.model.revision]
 if i!=null:next.append_array([i.preview_active,i.drag_item_id,i.drag_kind,i.drag_cell,i.drag_rotation])
 if signature==next:return
 signature=next;markers=describe(game)
func _process(_delta):
 _refresh()
func draw_ground(art):
 # Called only by the illustration, after update_projection and floor drawing,
 # before any wall, prop or actor. No independently retained screen coordinates.
 _refresh()
 if not is_instance_valid(game) or not game.editing:return
 for marker in markers:
  var cell:Vector2i=marker.cell
  var color=Color("527961") if marker.clear else Color("aa5845")
  var corners=PackedVector2Array([art.iso(cell.x+.08,cell.y+.08),art.iso(cell.x+.92,cell.y+.08),art.iso(cell.x+.92,cell.y+.92),art.iso(cell.x+.08,cell.y+.92)])
  var fill=color;fill.a=.20;art.draw_colored_polygon(corners,fill)
  corners.append(corners[0]);art.draw_polyline(corners,color,2.0,true)
