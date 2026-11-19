extends RefCounted
## Pure hosted-opening geometry. Attachments never become floor furniture.
const Footprint=preload("res://scripts/gameplay/cafe_footprint.gd")
const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
const WALL_HEIGHT=128.0
const DOOR_TOP=97.0
const WINDOW_BOTTOM=43.0
const WINDOW_TOP=91.0
const PRICES={"door":40,"window":30}
const WIDTHS={"door":1.0,"window":.70}
const SHELL_HOSTS=["shell:back","shell:west"]
static func initial_attachments()->Array[Dictionary]:
	return [{"id":1,"kind":"door","host_id":"shell:west","offset":Footprint.DOOR_CENTER,"width":Footprint.DOOR_WIDTH,"paid_cost":0}]
static func is_legacy_starter_door(attachment:Dictionary)->bool:
	# Only the exact free starter signature is eligible; moved/replaced doors
	# and every purchased attachment retain their saved geometry and value.
	return int(attachment.id)==1 and attachment.kind=="door" and attachment.host_id=="shell:west" and float(attachment.offset)==Footprint.DOOR_CENTER and float(attachment.width)==Footprint.LEGACY_DOOR_WIDTH and int(attachment.paid_cost)==0
static func initial_shell_products(material="original")->Dictionary:
	return {"shell:back":{"height":"full","material":material,"paid_cost":0},"shell:west":{"height":"full","material":material,"paid_cost":0}}
static func shell_hosts(material="original",walls:Array=[])->Array[Dictionary]:
	var products=material if material is Dictionary else initial_shell_products(material)
	var result:Array[Dictionary]=[{"host_id":"shell:back","a":Vector2.ZERO,"b":Vector2(Footprint.WIDTH,0),"axis":"x","normal":Vector2(0,-.26),"wall_ids":[],"shell":true},
		{"host_id":"shell:west","a":Vector2.ZERO,"b":Vector2(0,Footprint.west_shell_depth(walls)),"axis":"z","normal":Vector2(-.26,0),"wall_ids":[],"shell":true}]
	for host in result:
		var product=products.get(host.host_id,{"height":"full","material":"original","paid_cost":0})
		host.height=product.height;host.material=product.material;host.paid_cost=int(product.paid_cost)
	return result
static func wall_host(wall:Dictionary)->Dictionary:
	var a=Vector2(float(wall.x),float(wall.z));var direction=Vector2.RIGHT if wall.axis=="x" else Vector2.DOWN
	var normal=Walls.normal(wall)
	return {"host_id":Walls.identity(wall),"a":a,"b":a+direction,"axis":wall.axis,"height":wall.height,"material":wall.material,
		"normal":normal*(Walls.placement_value(wall,"physical_front")-Walls.placement_value(wall,"physical_back")),
		"physical_front":normal*Walls.placement_value(wall,"physical_front"),"physical_back":normal*Walls.placement_value(wall,"physical_back"),
		"visual_front":Walls.visual_front(wall),"visual_back":Walls.visual_back(wall),"pattern_origin":Walls.pattern_origin(wall),
		"wall_ids":[wall.get("id",-1)],"shell":false}

static func host_ref(ids:Array)->String:
	return str(ids[0]) if ids.size()==1 else "span:"+",".join(ids)

static func resolve_ids(ids:Array,walls:Array)->Dictionary:
	# A complete ordered support set replaces both starter roots and the old
	# hard-coded two-wall span. Identity never selects a different product type.
	if ids.is_empty():return {}
	var members=[];var seen={}
	for id in ids:
		if not id is String or seen.has(id):return {}
		seen[id]=true
		for wall in walls:
			if Walls.identity(wall)==id:members.append(wall);break
	if members.size()!=ids.size():return {}
	var first:Dictionary=members[0];var host=wall_host(first)
	var cursor=axis_value(host.a,host.axis)
	for wall in members:
		var next=wall_host(wall)
		if not collinear(host,next) or not is_equal_approx(axis_value(next.a,host.axis),cursor):return {}
		if members.size()>1 and (next.height!="full" or next.physical_front!=host.physical_front or next.physical_back!=host.physical_back or next.visual_front!=host.visual_front or next.visual_back!=host.visual_back):return {}
		cursor=axis_value(next.b,host.axis);host.b=next.b
	host.host_id=host_ref(ids);host.wall_ids=ids.duplicate()
	return host

static func installed_support_error(walls:Array,attachments:Array)->String:
	for attachment in attachments:
		var opening=aperture(attachment,walls)
		if opening.is_empty() or opening.host.height!="full":return "Opening needs complete full-height wall support"
		var low=float(attachment.offset)-float(attachment.width)*.5
		var high=float(attachment.offset)+float(attachment.width)*.5
		if low<-.00001 or high>opening.host.a.distance_to(opening.host.b)+.00001:return "Opening extends beyond its supporting walls"
		for id in attachment.wall_ids:
			var unit=resolve_ids([id],walls)
			var start=axis_value(unit.a-opening.host.a,opening.host.axis)
			if minf(high,start+1.0)-maxf(low,start)<=.00001:return "Opening lists an unused supporting wall"
		for other in attachments:
			if int(other.id)==int(attachment.id):continue
			var occupied=aperture(other,walls)
			if not occupied.is_empty() and collinear(opening.host,occupied.host) and minf(axis_value(opening.b,opening.host.axis),axis_value(occupied.b,opening.host.axis))-maxf(axis_value(opening.a,opening.host.axis),axis_value(occupied.a,opening.host.axis))>.00001:return "A door or window already occupies this wall interval"
	return ""
static func installed_hosts(walls:Array)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for wall in walls:result.append(wall_host(wall))
	return result

static func resolve_installed(ref:String,walls:Array)->Dictionary:
	var ids:Array=[]
	if ref.begins_with("span:"):
		for id in ref.trim_prefix("span:").split(",",false):ids.append(str(id))
	else:ids.append(ref)
	return resolve_ids(ids,walls)

static func hosts(walls:Array,material="original")->Array[Dictionary]:
	var result=shell_hosts(material,walls)
	for wall in walls:result.append(wall_host(wall))
	return result
static func resolve_host(ref:String,walls:Array,material="original")->Dictionary:
	for host in hosts(walls,material):
		if host.host_id==ref:return host
	if not ref.begins_with("span:"):return {}
	var ids=ref.trim_prefix("span:").split(",",false)
	if ids.size()!=2 or not ids[0].is_valid_int() or not ids[1].is_valid_int() or ids[0]==ids[1]:return {}
	var members=[]
	for id in ids:
		for wall in walls:
			if int(wall.get("id",-1))==int(id):members.append(wall)
	if members.size()!=2:return {}
	var first:Dictionary=members[0];var second:Dictionary=members[1]
	if first.axis!=second.axis or first.height!="full" or second.height!="full":return {}
	if (first.axis=="x" and (first.z!=second.z or absi(int(first.x)-int(second.x))!=1)) or (first.axis=="z" and (first.x!=second.x or absi(int(first.z)-int(second.z))!=1)):return {}
	members.sort_custom(func(a,b):return int(a.x+a.z)<int(b.x+b.z))
	var host=wall_host(members[0]);host.host_id=ref;host.b=wall_host(members[1]).b;host.wall_ids=[int(members[0].id),int(members[1].id)];return host
static func aperture(attachment:Dictionary,walls:Array,material="original")->Dictionary:
	var host=resolve_ids(attachment.wall_ids,walls) if attachment.has("wall_ids") else resolve_host(str(attachment.get("host_id","")),walls,material)
	if host.is_empty():return {}
	var direction=(host.b-host.a).normalized();var center=host.a+direction*float(attachment.offset)
	return {"id":int(attachment.id),"kind":attachment.kind,"host_id":host.host_id,"host":host,"a":center-direction*float(attachment.width)*.5,"b":center+direction*float(attachment.width)*.5,"bottom":0.0 if attachment.kind=="door" else WINDOW_BOTTOM,"top":DOOR_TOP if attachment.kind=="door" else WINDOW_TOP,"width":float(attachment.width)}
static func compatible_error(attachment:Dictionary,walls:Array,attachments:Array,ignore_id=-1,shell_products="original")->String:
	var kind=str(attachment.get("kind",""))
	if kind not in PRICES:return "Choose a door or window"
	var host=resolve_host(str(attachment.get("host_id","")),walls,shell_products)
	if host.is_empty():return "Attach to an existing wall; empty floor is not a host"
	if host.height!="full":return "Doors and windows need a full-height wall"
	var offset=float(attachment.offset);var width=float(attachment.width);var length=host.a.distance_to(host.b)
	if not is_finite(offset) or not is_finite(width) or width<=0 or offset-width*.5<-.00001 or offset+width*.5>length+.00001:return "The opening must fit completely within its wall host"
	var proposed=aperture(attachment,walls)
	for other in attachments:
		if int(other.id)==ignore_id:continue
		var existing=aperture(other,walls)
		if existing.is_empty():continue
		if collinear(proposed.host,existing.host) and minf(axis_value(proposed.b,host.axis),axis_value(existing.b,host.axis))-maxf(axis_value(proposed.a,host.axis),axis_value(existing.a,host.axis))>.00001:return "A door or window already occupies this part of the wall"
	return ""
static func collinear(a:Dictionary,b:Dictionary)->bool:
	return a.axis==b.axis and (is_equal_approx(a.a.y,b.a.y) if a.axis=="x" else is_equal_approx(a.a.x,b.a.x))
static func axis_value(point:Vector2,axis:String)->float:return point.x if axis=="x" else point.y
static func cuts(host:Dictionary,walls:Array,attachments:Array,doors_only=false)->Array[Dictionary]:
	var result:Array[Dictionary]=[];var origin=axis_value(host.a,host.axis);var length=host.a.distance_to(host.b)
	for attachment in attachments:
		if doors_only and attachment.kind!="door":continue
		var opening=aperture(attachment,walls)
		if opening.is_empty() or not collinear(host,opening.host):continue
		var low=maxf(0.0,axis_value(opening.a,host.axis)-origin);var high=minf(length,axis_value(opening.b,host.axis)-origin)
		if high>low+.00001:result.append({"from":low,"to":high,"bottom":opening.bottom,"top":opening.top,"opening":opening})
	result.sort_custom(func(a,b):return float(a.from)<float(b.from));return result
static func solid_segments(host:Dictionary,walls:Array,attachments:Array)->Array[Dictionary]:
	var result:Array[Dictionary]=[];var direction=(host.b-host.a).normalized();var cursor=0.0;var length=host.a.distance_to(host.b)
	for cut in cuts(host,walls,attachments,true):
		if cut.from>cursor+.00001:result.append({"a":host.a+direction*cursor,"b":host.a+direction*float(cut.from),"normal":host.normal,"host":host})
		cursor=maxf(cursor,float(cut.to))
	if cursor<length-.00001:result.append({"a":host.a+direction*cursor,"b":host.b,"normal":host.normal,"host":host})
	return result
static func solid_panels(host:Dictionary,walls:Array,attachments:Array)->Array[Dictionary]:
	var result:Array[Dictionary]=[];var cursor=0.0;var height=WALL_HEIGHT if host.height=="full" else 58.0;var length=host.a.distance_to(host.b)
	for cut in cuts(host,walls,attachments):
		if cut.from>cursor+.00001:result.append({"from":cursor,"to":cut.from,"bottom":0.0,"top":height})
		if cut.bottom>0:result.append({"from":cut.from,"to":cut.to,"bottom":0.0,"top":minf(height,float(cut.bottom))})
		if cut.top<height:result.append({"from":cut.from,"to":cut.to,"bottom":float(cut.top),"top":height})
		cursor=maxf(cursor,float(cut.to))
	if cursor<length-.00001:result.append({"from":cursor,"to":length,"bottom":0.0,"top":height})
	return result
static func point_in_door(point:Vector2,host:Dictionary,walls:Array,attachments:Array,clearance=0.0)->bool:
	var position=axis_value(point-host.a,host.axis)
	for cut in cuts(host,walls,attachments,true):
		if position>float(cut.from)+clearance+.00001 and position<float(cut.to)-clearance-.00001:return true
	return false
static func segment_rect(segment:Dictionary)->Rect2:
	var host:Dictionary=segment.host;var normal:Vector2=host.normal
	var a:Vector2=segment.a;var b:Vector2=segment.b
	if host.has("physical_front") and host.has("physical_back"):
		return Rect2(a+host.physical_back,b-a+host.physical_front-host.physical_back).abs()
	var shift=Vector2.ZERO if host.shell else -normal*.5
	return Rect2(a+shift,b-a+normal).abs()
static func body_touches(segment:Dictionary,point:Vector2,radius=.23)->bool:
	var rect=segment_rect(segment);var closest=point.clamp(rect.position,rect.end)
	return closest.distance_to(point)<radius-.000001
static func crosses(segment:Dictionary,a:Vector2,b:Vector2)->bool:
	var rect=segment_rect(segment);var low=rect.position;var high=rect.end
	if maxf(a.x,b.x)<=low.x+.000001 or minf(a.x,b.x)>=high.x-.000001 or maxf(a.y,b.y)<=low.y+.000001 or minf(a.y,b.y)>=high.y-.000001:return false
	var delta=b-a;var t0=0.0;var t1=1.0
	for axis in range(2):
		if absf(delta[axis])>.000001:
			var x=(low[axis]-a[axis])/delta[axis];var y=(high[axis]-a[axis])/delta[axis]
			t0=maxf(t0,minf(x,y));t1=minf(t1,maxf(x,y))
	return t0<t1-.000001 and t1>.000001 and t0<1.0-.000001
