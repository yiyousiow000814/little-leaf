extends RefCounted
## Paused edit transactions may move a worker out of a new furnishing's way.
## Every destination is reachable before the edit and safe after it.
static func plan(model,kind:String,id:int,x:int,z:int,rotation:int,actors:Array)->Dictionary:
 var parts=model.placement_parts(kind,x,z,rotation,id)
 var omitted=model.logical_members(id) if id>=0 else []
 var layout:Array[Dictionary]=[]
 for item in model.items:
  if int(item.id) not in omitted:layout.append(item)
 layout.append_array(parts)
 if model._furniture_actor_error(parts,layout,actors)=="":return {"ok":true,"positions":actors.duplicate(),"moves":[]}
 var reachable=model._furniture_actor_component(model.ENTRY_LANDING,layout)
 var positions=actors.duplicate();var moves=[]
 var reserved={}
 for item in layout:
  if str(item.kind) in ["stove","beverage","sink","counter","register"]:
   var front=model.workface_cell(item);reserved[front]=true
   if str(item.kind) in ["counter","register"]:reserved[Vector2i(item.x,item.z)*2-front]=true
 for cell in model.checkout_claims():reserved[cell]=true
 for index in actors.size():
  var start:Vector2=actors[index];var cell=Vector2i(start.floor())
  if point_clear(model,start,layout) and reachable.has(cell):continue
  # Search the old floor: workers step aside before furniture is installed.
  # A wall or old solid cannot be crossed to reach a convenient new pocket.
  var old_reachable=model._furniture_actor_component(cell,model.items)
  if old_reachable.is_empty() or model.segment_blocked(start,model.cell_center(cell)):
   return {"ok":false,"error":"No safe place for staff to step aside"}
  var queue=[cell];var visited={cell:true};var cursor=0;var found=false
  while cursor<queue.size():
   var at:Vector2i=queue[cursor];cursor+=1
   var target=model.cell_center(at)
   if reachable.has(at) and not reserved.has(at) and point_clear(model,target,layout) and _body_clear(model,target,positions,index):
    positions[index]=target;moves.append({"index":index,"from":start,"to":target});found=true;break
   for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
    var next=at+direction
    if visited.has(next) or not old_reachable.has(next) or model.edge_blocked(at,next):continue
    visited[next]=true;queue.append(next)
  if not found:return {"ok":false,"error":"No safe place for staff to step aside"}
 return {"ok":true,"positions":positions,"moves":moves}

static func point_clear(model,point:Vector2,layout:Array)->bool:
 var cell=Vector2i(point.floor())
 if cell.x<1 or not model.is_floor_owned(cell):return false
 for item in layout:
  if str(item.kind)=="rug":continue
  var minimum=Vector2(item.x,item.z)
  if point.distance_squared_to(point.clamp(minimum,minimum+Vector2.ONE))<model.STAFF_PLACEMENT_RADIUS*model.STAFF_PLACEMENT_RADIUS:return false
 return true

static func _body_clear(model,point:Vector2,actors:Array,index:int)->bool:
 for other in actors.size():
  if other!=index and point.distance_to(actors[other])<.9:return false
 for guest in model.customers:
  if str(guest.phase) not in ["dirty","cleaning"] and point.distance_to(Vector2(guest.x,guest.z))<.9:return false
 return true
