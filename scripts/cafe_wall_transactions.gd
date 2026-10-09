extends RefCounted
## Wall edits plan against an isolated geometry snapshot. Shell anchors remain
## stable for old saves; removed segments are tombstones, never free receipts.
const Walls=preload("res://scripts/cafe_walls.gd")
const Openings=preload("res://scripts/cafe_wall_openings.gd")
const Segments=preload("res://scripts/cafe_shell_segments.gd")
const Motion=preload("res://scripts/cafe_furniture_motion.gd")

static func editable(model,key:String)->Dictionary:
 var shell=Segments.parse_key(key)
 if shell.is_empty():return model.get_wall(key)
 var host=model.get_wall_host(key)
 if host.is_empty():return {}
 var wall=Walls.make(host.axis,int(host.a.x),int(host.a.y),host.height,host.material)
 wall.id=-1;wall.shell_key=key;wall.paid_cost=int(host.paid_cost);wall.refund_credit=int(host.refund_credit)
 return wall

static func hosted(model,key:String)->Array:
 var shell=Segments.parse_key(key)
 if shell.is_empty():
  var wall=model.get_wall(key)
  return [] if wall.is_empty() else model.attachments_for_wall(int(wall.id))
 var result=[]
 for opening in model.wall_attachments:
  if opening.host_id!=shell.root_id:continue
  if float(opening.offset)+float(opening.width)*.5>float(shell.index)+.00001 and float(opening.offset)-float(opening.width)*.5<float(shell.index)+1.0-.00001:result.append(opening)
 return result

static func removable_error(model,key:String)->String:
 if editable(model,key).is_empty():return "Select a wall first"
 if not hosted(model,key).is_empty():return "Move or sell the attached door/window before selling this wall"
 return ""

static func plan_move(model,key:String,axis:String,x:int,z:int,actors:Array)->Dictionary:
 var wall=editable(model,key)
 if wall.is_empty():return {"ok":false,"error":"Select a wall first"}
 var shadow=Motion.copy_model(model)
 var shell=Segments.parse_key(key)
 var proposed=Walls.make(axis,x,z,wall.height,wall.material)
 var id=int(wall.id) if shell.is_empty() else int(model._next_wall_id)
 proposed.id=id
 for field in ["paid_cost","refund_credit","origin_shell"]:
  if wall.has(field):proposed[field]=wall[field]
 if not shell.is_empty():
  proposed.origin_shell=key
  shadow.shell_segment_products[key]["removed"]=true
  for opening in hosted(model,key):
   if float(opening.offset)-float(opening.width)*.5<float(shell.index)-.00001 or float(opening.offset)+float(opening.width)*.5>float(shell.index)+1.0+.00001:return {"ok":false,"error":"Move the wide opening before moving one of its supporting wall tiles"}
   var moved=shadow.get_wall_attachment(int(opening.id))
   moved.host_id="wall:"+str(id);moved.offset=float(opening.offset)-float(shell.index)
 else:
  var old_shell_key=Segments.edge_key(wall)
  if old_shell_key!="" and hosted(model,old_shell_key).is_empty():shadow.shell_segment_products[old_shell_key]["removed"]=true
  for opening in hosted(model,key):
   if Openings.resolve_host(opening.host_id,model.built_walls).wall_ids.size()>1:return {"ok":false,"error":"Move the wide opening before moving one of its supporting wall tiles"}
 var error=shadow._wall_candidate_error(proposed,model._wall_actor_list(actors),key if shell.is_empty() else "")
 if error!="":return {"ok":false,"error":error}
 var result:Array[Dictionary]=[]
 for existing in shadow.built_walls:
  if shell.is_empty() and int(existing.id)==id:continue
  result.append(existing)
 result.append(proposed)
 return {"ok":true,"walls":result,"segments":shadow.shell_segment_products,"openings":shadow.wall_attachments,"id":id,"shell":not shell.is_empty()}

static func commit_move(model,key:String,plan:Dictionary)->bool:
 if not plan.ok:return model._fail(plan.error)
 model.built_walls.assign(plan.walls);model.shell_segment_products=plan.segments;model.wall_attachments.assign(plan.openings)
 if plan.shell:
  model._next_wall_id+=1
  if model.decoration_build_purchases.has(key):
   model.decoration_build_purchases["wall:"+str(plan.id)]=model.decoration_build_purchases[key]
   model.decoration_build_purchases.erase(key)
 model.last_error="";model.last_event="Moved wall";model._notify();return true
