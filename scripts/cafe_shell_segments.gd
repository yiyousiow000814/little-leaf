extends RefCounted
## Additive starter-shell segment ledger. Geometric roots and opening IDs stay stable.
## Pure validation, migration and quote operations never mutate caller state.
const Geometry=preload("res://scripts/cafe_wall_openings.gd")
const Walls=preload("res://scripts/cafe_walls.gd")
const Footprint=preload("res://scripts/cafe_footprint.gd")
const FORMAT="little_leaf.shell_segments.v1"
const EPS=.00001
# Accepted 0.1.8 payments are historical values, independent of current shop prices.
const LEGACY_PRICES={"half":35,"full":55}
const MAX_LEGACY_SEGMENT_PAID=62

static func key(root_id:String,index:int)->String:return root_id+"#"+str(index)
static func full_count(root_id:String)->int:return Footprint.WIDTH if root_id=="shell:back" else Footprint.DEPTH
static func active_count(root_id:String,walls:Array)->int:return Footprint.WIDTH if root_id=="shell:back" else Footprint.west_shell_depth(walls)
static func integer(value,low:int,high:int)->bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and int(value)>=low and int(value)<=high

static func migrate(products:Dictionary,walls:Array)->Dictionary:
 var segments={}
 for root_id in Geometry.SHELL_HOSTS:
  var product:Dictionary=products[root_id]
  var paid=int(product.paid_cost);var count=active_count(root_id,walls)
  var legacy_paid_units=Footprint.LEGACY_DEPTH if root_id=="shell:west" and count==Footprint.DEPTH and paid==LEGACY_PRICES[product.height]*Footprint.LEGACY_DEPTH else count
  var cumulative=0
  for index in full_count(root_id):
   var amount=0
   if index<legacy_paid_units:amount=floori(float(paid)*(index+1)/legacy_paid_units)-floori(float(paid)*index/legacy_paid_units)
   # Preserve the old aggregate half-refund exactly, including its odd coin.
   var credit=(cumulative+amount)/2-cumulative/2
   cumulative+=amount
   segments[key(root_id,index)]={"height":str(product.height),"material":str(product.material),"paid_cost":amount,"refund_credit":int(credit)}
 return {"format":FORMAT,"roots":products.duplicate(true),"segments":segments}

static func totals(state:Dictionary,root_id:String,walls:Array)->Dictionary:
 var paid=0;var refund=0
 for index in active_count(root_id,walls):
  var segment:Dictionary=state.segments[key(root_id,index)];paid+=int(segment.paid_cost);refund+=int(segment.refund_credit)
 return {"paid_cost":paid,"refund_credit":refund}

static func validate(state:Dictionary,walls:Array)->String:
 if state.get("format")!=FORMAT or not state.get("segments") is Dictionary or not state.get("roots") is Dictionary:return "Invalid shell segment format"
 if state.roots.size()!=Geometry.SHELL_HOSTS.size():return "Unexpected root host"
 var expected={}
 for root_id in Geometry.SHELL_HOSTS:
  if not state.roots.get(root_id) is Dictionary:return "Missing root host"
  var root:Dictionary=state.roots[root_id]
  if root.get("height") not in Walls.HEIGHTS or (root.get("material")!="original" and root.get("material") not in Walls.MATERIALS):return "Invalid root snapshot"
  var unit=int(LEGACY_PRICES[root.height]);var root_max=unit*full_count(root_id)
  var legacy=unit*(Footprint.LEGACY_DEPTH if root_id=="shell:west" else Footprint.WIDTH)
  if not integer(root.get("paid_cost"),0,root_max) or int(root.paid_cost) not in [0,legacy,root_max]:return "Invalid root paid snapshot"
 # The inherited allocation describes history, not today's active extent.
 # An extension can be moved or removed after an eight-unit migration.
 var allocations=[migrate(state.roots,[]).segments,migrate(state.roots,[Walls.make("z",0,Footprint.LEGACY_DEPTH)]).segments]
 for root_id in Geometry.SHELL_HOSTS:
  for index in full_count(root_id):
   var name=key(root_id,index);expected[name]=true
   if not state.segments.get(name) is Dictionary:return "Missing shell segment"
   var segment:Dictionary=state.segments[name]
   if segment.size()!=4 or segment.get("height") not in Walls.HEIGHTS or (segment.get("material")!="original" and segment.get("material") not in Walls.MATERIALS):return "Invalid shell appearance"
   if not integer(segment.get("paid_cost"),0,maxi(MAX_LEGACY_SEGMENT_PAID,int(Walls.PRICES[segment.height]))) or not integer(segment.get("refund_credit"),0,ceili(maxi(MAX_LEGACY_SEGMENT_PAID,int(Walls.PRICES[segment.height]))/2.0)):return "Invalid shell payment"
   if int(segment.refund_credit)>ceili(float(segment.paid_cost)/2):return "Excess segment refund"
   if index>=active_count(root_id,walls) and (int(segment.paid_cost)!=0 or int(segment.refund_credit)!=0):return "Dormant included segment has paid value"
  var recognized_basis=false
  for inherited in allocations:
   var consistent=true
   for index in full_count(root_id):
    var name=key(root_id,index);var segment:Dictionary=state.segments[name];var original:Dictionary=inherited[name]
    var inherited_payment=segment.height==original.height and segment.material==original.material and int(segment.paid_cost)==int(original.paid_cost) and int(segment.refund_credit)==int(original.refund_credit)
    var ordinary_purchase=int(segment.paid_cost) in [int(LEGACY_PRICES[segment.height]),int(Walls.PRICES[segment.height])] and int(segment.refund_credit)==int(segment.paid_cost)/2
    if not inherited_payment and not ordinary_purchase:consistent=false;break
   if consistent:recognized_basis=true;break
  if not recognized_basis:return "Unrecognized shell payment allocation"
  var sum=totals(state,root_id,walls)
  if int(sum.refund_credit)>int(sum.paid_cost)/2:return "Excess aggregate refund"
 if state.segments.size()!=expected.size():return "Unexpected shell segment"
 return ""

static func decode(raw:Dictionary,walls:Array)->Dictionary:
 var reason=validate(raw,walls)
 if reason!="":return {"ok":false,"error":reason}
 var normalized=raw.duplicate(true)
 for root_id in Geometry.SHELL_HOSTS:normalized.roots[root_id].paid_cost=int(normalized.roots[root_id].paid_cost)
 for name in normalized.segments:
  normalized.segments[name].paid_cost=int(normalized.segments[name].paid_cost)
  normalized.segments[name].refund_credit=int(normalized.segments[name].refund_credit)
 return {"ok":true,"state":normalized}

static func segment_host(state:Dictionary,walls:Array,root_id:String,index:int)->Dictionary:
 if root_id not in Geometry.SHELL_HOSTS or index<0 or index>=active_count(root_id,walls):return {}
 var root=Geometry.resolve_host(root_id,walls,state.roots)
 var direction=(root.b-root.a).normalized()
 var segment=root.duplicate(true);segment.root_id=root_id;segment.segment_key=key(root_id,index);segment.segment_index=index
 segment.a=root.a+direction*index;segment.b=segment.a+direction
 for field in ["height","material","paid_cost","refund_credit"]:segment[field]=state.segments[segment.segment_key][field]
 return segment

static func support_error(state:Dictionary,walls:Array,attachments:Array)->String:
 # Root hosts stay geometric anchors. Height support is evaluated over every
 # actual segment covered by the full aperture, not a scalar root height.
 var products=state.roots.duplicate(true)
 for root_id in Geometry.SHELL_HOSTS:products[root_id].height="full"
 for attachment in attachments:
  var reason=Geometry.compatible_error(attachment,walls,attachments,int(attachment.id),products)
  if reason!="":return reason
  if attachment.host_id not in Geometry.SHELL_HOSTS:continue
  var low=float(attachment.offset)-float(attachment.width)*.5;var high=float(attachment.offset)+float(attachment.width)*.5
  for index in range(maxi(0,floori(low+EPS)),mini(active_count(attachment.host_id,walls),ceili(high-EPS))):
   if state.segments[key(attachment.host_id,index)].height!="full":return "Opening needs every supporting segment at full height"
 return ""

static func quote(state:Dictionary,walls:Array,attachments:Array,root_id:String,index:int,height:String,material:String,coins:int)->Dictionary:
 var result={"valid":false,"new_cost":0,"refund":0,"net":0,"reason":""}
 if validate(state,walls)!="":result.reason="Invalid segment state";return result
 var host=segment_host(state,walls,root_id,index)
 if host.is_empty():result.reason="Choose an active shell segment";return result
 if height not in Walls.HEIGHTS or (material!="original" and material not in Walls.MATERIALS):result.reason="Choose a listed wall style";return result
 if host.height==height and host.material==material:result.reason="Already installed";return result
 result.new_cost=int(Walls.PRICES[height]);result.refund=int(host.refund_credit);result.net=result.new_cost-result.refund
 var proposed=state.duplicate(true);proposed.segments[host.segment_key].height=height;proposed.segments[host.segment_key].material=material
 result.reason=support_error(proposed,walls,attachments)
 if result.reason!="":return result
 if coins<int(result.net):result.reason="Not enough coins";return result
 result.valid=true;return result

static func replace(state:Dictionary,walls:Array,attachments:Array,root_id:String,index:int,height:String,material:String,coins:int)->Dictionary:
 var bill=quote(state,walls,attachments,root_id,index,height,material,coins)
 if not bill.valid:return {"ok":false,"state":state,"coins":coins,"quote":bill}
 var next=state.duplicate(true);var cost=int(bill.new_cost)
 next.segments[key(root_id,index)]={"height":height,"material":material,"paid_cost":cost,"refund_credit":cost/2}
 return {"ok":true,"state":next,"coins":coins-int(bill.net),"quote":bill}

static func render_runs(state:Dictionary,walls:Array,root_id:String)->Array:
 var root=Geometry.resolve_host(root_id,walls,state.roots);var runs=[]
 for index in active_count(root_id,walls):
  var segment:Dictionary=state.segments[key(root_id,index)]
  if not runs.is_empty() and runs[-1].height==segment.height and runs[-1].material==segment.material:runs[-1].to=index+1
  else:runs.append({"root_id":root_id,"root_a":root.a,"root_b":root.b,"normal":root.normal,"from":index,"to":index+1,"height":segment.height,"material":segment.material})
 return runs

static func uses_original_renderer(state:Dictionary,walls:Array,root_id:String)->bool:
 var runs=render_runs(state,walls,root_id)
 return runs.size()==1 and runs[0].height==state.roots[root_id].height and runs[0].material==state.roots[root_id].material

static func parse_key(value:String)->Dictionary:
 var parts=value.split("#",false)
 if parts.size()!=2 or parts[0] not in Geometry.SHELL_HOSTS or not parts[1].is_valid_int():return {}
 var index=int(parts[1])
 if str(index)!=parts[1] or index<0 or index>=full_count(parts[0]):return {}
 return {"root_id":parts[0],"index":index}

static func state(products:Dictionary,segments:Dictionary)->Dictionary:
 return {"format":FORMAT,"roots":products,"segments":segments}

static func from_save(data:Dictionary,walls:Array,products:Dictionary)->Dictionary:
 var format=int(data.get("wall_format",1))
 if format==1:
  if data.has("shell_segment_format") or data.has("shell_segment_products"):return {"ok":false,"error":"Unexpected shell segment data in legacy wall format"}
  return decode(migrate(products,walls),walls)
 if format!=2 or data.get("shell_segment_format")!=FORMAT or not data.get("shell_segment_products") is Dictionary:return {"ok":false,"error":"Invalid shell segment format"}
 return decode(state(products,data.shell_segment_products),walls)

static func selectable_hosts(products:Dictionary,segments:Dictionary,walls:Array)->Array[Dictionary]:
 var result:Array[Dictionary]=[];var current=state(products,segments)
 for root_id in Geometry.SHELL_HOSTS:
  for index in active_count(root_id,walls):result.append(segment_host(current,walls,root_id,index))
 for wall in walls:result.append(Geometry.wall_host(wall))
 return result

static func render_host(products:Dictionary,segments:Dictionary,walls:Array,root_id:String,preview:Dictionary={})->Dictionary:
 var root=Geometry.resolve_host(root_id,walls,products)
 if root.is_empty() or not root.shell:return root
 var current=state(products,segments).duplicate(true)
 if not preview.is_empty() and preview.get("root_id","")==root_id:
  var name=str(preview.get("segment_key",""))
  if current.segments.has(name):
   current.segments[name].height=preview.height;current.segments[name].material=preview.material
 var runs=render_runs(current,walls,root_id)
 if runs.size()==1:
  root.height=runs[0].height;root.material=runs[0].material
 else:root.segment_runs=runs
 return root
