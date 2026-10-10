extends RefCounted
## One reversible Tiles/Walls stroke. Preview and validation use an isolated
## model; only a fresh, complete receipt can publish one wallet/layout change.
## The input owner must also guard its game-level save_recovery_blocked flag.
const Motion=preload("res://scripts/cafe_furniture_motion.gd")
const Walls=preload("res://scripts/cafe_walls.gd")
const Segments=preload("res://scripts/cafe_shell_segments.gd")
const Money=preload("res://scripts/cafe_money.gd")
const COPY_FIELDS=["floor_finishes","decoration_build_purchases","_next_wall_id","_next_attachment_id","wall_actor_positions","checkout_staff_claims","duty_counts","duty_targets"]
var _state:Array=[]
var _request:Array=[]
var _receipt:Dictionary={}
var _receipt_copy:Dictionary={}
var _mode=""
var _material=""
var _targets:Array=[]

func stamp(model,actors:Array)->Array:
 return [model.get_instance_id(),model.revision,model.coins,
  hash(model.floor_finishes),hash(model.built_walls),hash(model.shell_segment_products),
  hash(model.shell_products),model.shell_material,hash(model.wall_attachments),
  hash(model.items),hash(model.dining_sets),hash(model.customers),
  hash(model.owned_parcels),model.width,model.depth,model.expanded,
  hash(model.wall_actor_positions),hash(model.checkout_staff_claims),hash(actors),
  model._next_wall_id,model._next_attachment_id,model._next_item_id,
  model.decoration_session_active,hash(model.decoration_build_purchases),
  hash(model.decoration_purchases),hash(model.catalog),hash(model.duty_counts),hash(model.duty_targets),
  model.cooks,model.waiters,model.cleaners,model.cashiers,model.operating_open]

func prepare(model,mode:String,material:String,targets:Array,actors:Array=[])->Dictionary:
 var state=stamp(model,actors)
 if state==_state and [mode,material,targets]==_request and _receipt==_receipt_copy:return _receipt
 invalidate()
 _state=state;_mode=mode;_material=material;_targets=targets.duplicate(true)
 _request=[mode,material,_targets.duplicate(true)]
 var planned=_plan(model,mode,material,_targets,actors)
 _receipt=planned.receipt;_receipt_copy=_receipt.duplicate(true)
 return _receipt

func commit(model,receipt:Dictionary,actors:Array=[])->bool:
 if not is_same(receipt,_receipt) or receipt!=_receipt_copy:return model._fail("Stroke belongs to another preview")
 if _state.is_empty() or stamp(model,actors)!=_state:return model._fail("Stroke changed · review the tiles again")
 if not bool(_receipt_copy.get("ok",false)):return model._fail(str(_receipt_copy.get("error","Invalid stroke")))
 # Validate the complete stroke again. Never trust mutable public receipt data
 # or publish a succession of model.place_* calls to autosave/UI listeners.
 var planned=_plan(model,_mode,_material,_targets,actors)
 if planned.receipt!=_receipt_copy or not planned.receipt.ok:return model._fail("Stroke changed · review the tiles again")
 if int(_receipt_copy.changed_count)==0:
  invalidate();model.last_error="";return true
 var shadow=planned.shadow
 if _mode=="floor":model.floor_finishes=shadow.floor_finishes.duplicate(true)
 else:
  # Existing wall dictionaries can be held by rendering/service callers.
  # Keep their identity and append only newly purchased walls.
  var old_count=model.built_walls.size()
  for index in shadow.built_walls.size():
   var proposed:Dictionary=shadow.built_walls[index]
   if index<old_count:
    var original:Dictionary=model.built_walls[index]
    original.clear();original.merge(proposed.duplicate(true))
   else:model.built_walls.append(proposed.duplicate(true))
  model.shell_segment_products=shadow.shell_segment_products.duplicate(true)
  model.decoration_build_purchases=shadow.decoration_build_purchases.duplicate(true)
  model._next_wall_id=shadow._next_wall_id
 model.coins-=int(_receipt_copy.net)
 model.last_error=""
 model.last_event="%s placed · %d · new %s · refund %s · pay %s"%["Tiles" if _mode=="floor" else "Walls",int(_receipt_copy.changed_count),Money.amount(int(_receipt_copy.paid)),Money.amount(int(_receipt_copy.refund)),Money.amount(int(_receipt_copy.net))]
 # Invalidate before emitting, so a synchronous listener cannot reuse receipt.
 invalidate();model._notify();return true

func invalidate():
 _state=[];_request=[];_receipt={};_receipt_copy={};_mode="";_material="";_targets=[]

static func _shadow(model):
 var copy=Motion.copy_model(model)
 for field in COPY_FIELDS:
  var value=model.get(field)
  copy.set(field,value.duplicate(true) if value is Array or value is Dictionary else value)
 # Price every unique target even when the complete stroke is unaffordable.
 # This wallet exists only in the shadow; final funds are checked as a total.
 copy.coins=1<<50
 return copy

static func _plan(model,mode:String,material:String,targets:Array,actors:Array)->Dictionary:
 var receipt={"ok":false,"error":"","paid":0,"refund":0,"net":0,"count":0,"changed_count":0,"targets":[]}
 if mode not in ["floor","half","full"]:
  receipt.error="Choose Tiles or Walls";return {"receipt":receipt}
 if (mode=="floor" and material not in model.FLOOR_STYLES) or (mode!="floor" and material not in Walls.MATERIALS):
  receipt.error="Choose a listed finish";return {"receipt":receipt}
 if targets.is_empty():receipt.error="Drag across an owned tile or wall edge";return {"receipt":receipt}
 var shadow=_shadow(model)
 var seen={}
 for raw in targets:
  var target=_floor_target(raw,material) if mode=="floor" else _wall_target(shadow,raw,mode,material)
  var key=str(target.get("edge_key",target.get("key","")))
  if key!="" and seen.has(key):continue
  if key!="":seen[key]=true
  receipt.count+=1
  if str(target.error)=="":
   if mode=="floor":_apply_floor(shadow,target)
   else:_apply_wall(shadow,target,actors)
  target.valid=str(target.error)==""
  if not target.valid and receipt.error=="":receipt.error=target.error
  if target.action!="noop":
   receipt.paid+=int(target.new_cost);receipt.refund+=int(target.refund)
   if target.valid:receipt.changed_count+=1
  receipt.targets.append(target)
 receipt.net=int(receipt.paid)-int(receipt.refund)
 if receipt.error=="" and model.coins<int(receipt.net):receipt.error="Not enough coins · stroke needs %s after refund"%Money.amount(int(receipt.net))
 receipt.ok=receipt.error==""
 return {"receipt":receipt,"shadow":shadow}

static func _base_target()->Dictionary:
 return {"key":"","action":"place","valid":false,"error":"","new_cost":0,"refund":0,"net":0}

static func _integer(value)->bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value))

static func _floor_target(raw,material:String)->Dictionary:
 var result=_base_target()
 var cell
 if raw is Vector2i:cell=raw
 elif raw is Dictionary:
  if raw.get("cell") is Vector2i:cell=raw.cell
  elif _integer(raw.get("x")) and _integer(raw.get("z")):cell=Vector2i(int(raw.x),int(raw.z))
 if cell==null:result.error="Choose a valid floor tile";return result
 result.merge({"cell":cell,"x":cell.x,"z":cell.y,"key":"%d,%d"%[cell.x,cell.y],"style":material},true)
 return result

static func _wall_target(model,raw,height:String,material:String)->Dictionary:
 var result=_base_target()
 if not raw is Dictionary:result.error="Choose a valid wall edge";return result
 var wall=raw
 if not raw.has("axis") and raw.has("key"):wall=model.get_editable_wall(str(raw.key))
 if wall.is_empty() or wall.get("axis") not in ["x","z"] or not _integer(wall.get("x")) or not _integer(wall.get("z")):
  result.error="Choose a valid wall edge";return result
 result.merge({"axis":str(wall.axis),"x":int(wall.x),"z":int(wall.z),"height":height,"material":material})
 result.key=Walls.key_of(result);result.edge_key=result.key
 var shell=Segments.edge_key(result)
 if model.get_wall(result.key).is_empty() and shell!="" and not model.get_editable_wall(shell).is_empty():result.key=shell
 return result

static func _apply_floor(model,target:Dictionary):
 var quote=model.floor_quote(target.cell,target.style)
 # A revisited or already installed finish is a free part of the stroke,
 # rather than an error that prevents painting its neighboring tiles.
 if model.is_floor_owned(target.cell) and model.floor_style_at(target.cell)==target.style:
  target.action="noop";return
 if model.floor_finishes.has(target.key):target.action="replace"
 _quote(target,quote)
 if not quote.valid:target.error=str(quote.reason);return
 if not model.place_floor(target.cell,target.style):target.error=model.last_error

static func _apply_wall(model,target:Dictionary,actors:Array):
 if not Walls.valid_shape(target,model.MAX_WIDTH,model.MAX_DEPTH):target.error="Choose a valid wall edge";return
 var sides=Walls.adjacent_cells(target)
 if not model.is_floor_owned(sides[0]) and not model.is_floor_owned(sides[1]):target.error="Buy the adjacent plot before building a wall";return
 var current=model.get_editable_wall(target.key)
 if not current.is_empty():
  target.action="replace"
  if current.height==target.height and current.material==target.material:target.action="noop";return
  var quote=model.wall_replacement_quote(target.key,target.height,target.material,actors)
  _quote(target,quote)
  if not quote.valid:target.error=str(quote.reason);return
  if not model.replace_wall(target.key,target.height,target.material,actors):target.error=model.last_error
 else:
  target.new_cost=model.wall_price(target.height);target.net=target.new_cost
  if not model.place_wall(target.axis,target.x,target.z,target.height,target.material,actors):target.error=model.last_error

static func _quote(target:Dictionary,quote:Dictionary):
 for field in ["new_cost","refund","net"]:target[field]=int(quote.get(field,0))
