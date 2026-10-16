extends RefCounted
## Derived service identities, not a second reservation ledger or saved state.
## A task owns its payload; a contact may additionally need an exclusive workspace.
static func task(staff:Dictionary)->Array:
 var kind=str(staff.get("job_kind",""))
 if kind=="":return []
 var token=int(staff.get("job_token",-1))
 if kind=="floor":return ["mess",int(staff.get("job_mess_id",-1)),token,"floor"]
 if kind=="wash":return ["dish",int(staff.get("job_dish_id",-1)),token,"wash"]
 var domain="service"
 if kind=="take_payment":domain="payment"
 elif kind=="cleanup":domain="table" if int(staff.get("job_step",0))<3 else "floor"
 return ["guest",int(staff.get("job_guest_id",-1)),token,domain]

static func task_conflicts(left:Array,right:Array)->bool:
 if left.is_empty() or right.is_empty() or left[0]!=right[0] or int(left[1])!=int(right[1]):return false
 if left[0]!="guest":return true
 # The original meal/order chain remains serial. Finished-visit domains own
 # separate table payload, floor litter and payment, never the whole actor tile.
 return left[3]=="service" or right[3]=="service" or left[3]==right[3]

static func sink_lane(staff:Dictionary)->int:
 if staff.get("role")=="cleaner" and staff.get("job_kind")=="wash":return 1
 if staff.get("role")=="waiter" and staff.get("job_kind")=="cleanup" and int(staff.get("job_step",0))==1:return 2
 return 0

static func contact(staff:Dictionary,target:Dictionary,cell:Vector2i,index:int)->Dictionary:
 var identity=task(staff)
 if identity.is_empty() or target.is_empty():return {}
 var kind=str(target.get("kind",""));var job=str(staff.get("job_kind",""));var step=int(staff.get("job_step",0))
 var floor_work=(job=="floor" or (job=="cleanup" and step>=3)) and kind in ["floor","table","floor_disposal"]
 var resource=["floor",identity[0],identity[1]] if floor_work else ["item",kind,int(target.get("id",-1))]
 var shared=floor_work or kind=="table"
 var lane=sink_lane(staff) if kind=="sink" else 0
 return {"cell":cell,"task":identity,"resource":resource,"exclusive":not shared,"worker":index,"productive":true,"lane":lane,"sink_id":int(target.id) if kind=="sink" else -1}

static func complementary(left:Dictionary,right:Dictionary)->bool:
 return int(left.get("sink_id",-1))>=0 and left.get("sink_id")==right.get("sink_id") and int(left.get("lane",0))+int(right.get("lane",0))==3

static func conflicts(left:Dictionary,right:Dictionary)->bool:
 if left.is_empty() or right.is_empty() or not left.get("productive",false) or not right.get("productive",false):return false
 if task_conflicts(left.get("task",[]),right.get("task",[])):return true
 if complementary(left,right):return false
 if left.get("resource",[])==right.get("resource",[]):return true
 return bool(left.get("exclusive",true)) or bool(right.get("exclusive",true))
