extends RefCounted
## The same structural workface facts drive preview, commit, and issue navigation.
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
static func _preserves_or_repairs_legacy(previous:Dictionary,issue:Dictionary)->bool:
 if previous.is_empty():return false
 if str(issue.kind)!="stove":return true
 # Keep an old invalid save editable, but do not carry its exception to a
 # different work tile, new blocker, or newly closed working edge.
 for key in ["station_cell","cell"]:
  if previous.get(key)!=issue.get(key):return false
 if int(issue.blocking_item_id)>=0 and int(issue.blocking_item_id)!=int(previous.blocking_item_id):return false
 if bool(issue.blocked_edge) and not bool(previous.blocked_edge):return false
 if bool(previous.reachable) and not bool(issue.reachable):return false
 return true
static func _introduced(before:Array,after:Array)->Dictionary:
 var previous={}
 for issue in before:previous[str(issue.item_id)+":"+str(issue.side)]=issue
 for issue in after:
  if not requires_access(str(issue.kind)):continue
  if not _preserves_or_repairs_legacy(previous.get(str(issue.item_id)+":"+str(issue.side),{}),issue):return issue
 return {}
static func introduced(model,layout:Array)->Dictionary:
 return _introduced(issues(model,model.items),issues(model,layout))
static func _stove_wall_issues(model,walls:Array,openings)->Array:
 var result=[]
 var reachable=model._furniture_actor_component(model.ENTRY_LANDING,model.items,walls,openings)
 for item in model.items:
  if str(item.kind)!="stove":continue
  var center=Vector2i(item.x,item.z);var front=model.workface_cell(item)
  var blocked_edge=model._fixed_edge_blocked(center,front,openings,walls) or model._built_edge_blocked(center,front,walls,openings)
  if reachable.has(front) and not blocked_edge:continue
  var blocker=-1
  for other in model.items:
   if str(other.kind)!="rug" and Vector2i(other.x,other.z)==front:blocker=int(other.id);break
  result.append({"code":"blocked_workface","item_id":int(item.id),"kind":"stove","station_cell":center,"cell":front,"side":"front","blocking_item_id":blocker,"blocked_edge":blocked_edge,"reachable":reachable.has(front),"reason":"Stove front blocked · keep a connected working tile clear"})
 return result
static func introduced_stove_wall(model,walls:Array,openings=null)->Dictionary:
 # Only edit candidates call this. Save validation deliberately continues to
 # accept pre-existing blocked stoves without deleting or rearranging them.
 return _introduced(_stove_wall_issues(model,model.built_walls,model.wall_attachments),_stove_wall_issues(model,walls,model.wall_attachments if openings==null else openings))
