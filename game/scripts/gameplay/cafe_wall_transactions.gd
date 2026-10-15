extends RefCounted
## One installed product transaction for preset, imported and bought walls.
const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
const Motion=preload("res://scripts/gameplay/cafe_furniture_motion.gd")
static func editable(model,key:String)->Dictionary:return model.get_wall(key)
static func hosted(model,key:String)->Array:
 var wall=model.get_wall(key)
 return [] if wall.is_empty() else model.attachments_for_wall(Walls.identity(wall))
static func removable_error(model,key:String)->String:
 if editable(model,key).is_empty():return "Select a wall first"
 if not hosted(model,key).is_empty():return "Move or sell the attached door/window before selling this wall"
 return ""
static func plan_move(model,key:String,axis:String,x:int,z:int,actors:Array)->Dictionary:
 var wall=editable(model,key)
 if wall.is_empty():return {"ok":false,"error":"Select a wall first"}
 for opening in hosted(model,key):
  if opening.wall_ids.size()>1:return {"ok":false,"error":"Move the wide opening before moving one of its supporting wall tiles"}
 var proposed=Walls.installed(Walls.identity(wall),Walls.make(axis,x,z,wall.height,wall.material),int(wall.paid_cost),int(wall.refund_credit),wall.get("placement",{}))
 var shadow=Motion.copy_model(model)
 var error=shadow._wall_candidate_error(proposed,model._wall_actor_list(actors),Walls.key_of(wall))
 if error!="":return {"ok":false,"error":error}
 var result:Array[Dictionary]=[]
 for existing in shadow.built_walls:result.append(proposed if Walls.identity(existing)==Walls.identity(wall) else existing)
 return {"ok":true,"walls":result,"openings":shadow.wall_attachments}
static func commit_move(model,_key:String,plan:Dictionary)->bool:
 if not plan.ok:return model._fail(plan.error)
 model.built_walls.assign(plan.walls);model.wall_attachments.assign(plan.openings)
 model.last_error="";model.last_event="Moved wall";model._notify();return true
