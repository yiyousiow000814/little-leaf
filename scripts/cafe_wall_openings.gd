extends RefCounted
## Pure hosted-opening geometry. Attachments never become floor furniture.
const WALL_HEIGHT=128.0
const DOOR_TOP=97.0
const WINDOW_BOTTOM=43.0
const WINDOW_TOP=91.0
const PRICES={"door":40,"window":30}
const WIDTHS={"door":.76,"window":.70}
const SHELL_HOSTS=["shell:back","shell:west"]
static func initial_attachments()->Array[Dictionary]:
	return [{"id":1,"kind":"door","host_id":"shell:west","offset":5.5,"width":1.5,"paid_cost":0}]
static func initial_shell_products(material="original")->Dictionary:
	return {"shell:back":{"height":"full","material":material,"paid_cost":0},"shell:west":{"height":"full","material":material,"paid_cost":0}}
static func shell_hosts(material="original")->Array[Dictionary]:
	var products=material if material is Dictionary else initial_shell_products(material)
	var result:Array[Dictionary]=[{"host_id":"shell:back","a":Vector2.ZERO,"b":Vector2(12,0),"axis":"x","normal":Vector2(0,-.26),"wall_ids":[],"shell":true},
		{"host_id":"shell:west","a":Vector2.ZERO,"b":Vector2(0,8),"axis":"z","normal":Vector2(-.26,0),"wall_ids":[],"shell":true}]
	for host in result:
		var product=products.get(host.host_id,{"height":"full","material":"original","paid_cost":0})
		host.height=product.height;host.material=product.material;host.paid_cost=int(product.paid_cost)
	return result
static func wall_host(wall:Dictionary)->Dictionary:
	var a=Vector2(float(wall.x),float(wall.z));var direction=Vector2.RIGHT if wall.axis=="x" else Vector2.DOWN
	return {"host_id":"wall:%d"%int(wall.get("id",-1)),"a":a,"b":a+direction,"axis":wall.axis,"height":wall.height,"material":wall.material,"normal":Vector2.DOWN*.16 if wall.axis=="x" else Vector2.RIGHT*.16,"wall_ids":[int(wall.get("id",-1))],"shell":false}
static func hosts(walls:Array,material="original")->Array[Dictionary]:
	var result=shell_hosts(material)
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
	var host=resolve_host(str(attachment.get("host_id","")),walls,material)
	if host.is_empty():return {}
	var direction=(host.b-host.a).normalized();var center=host.a+direction*float(attachment.offset)
	return {"id":int(attachment.id),"kind":attachment.kind,"host_id":attachment.host_id,"host":host,"a":center-direction*float(attachment.width)*.5,"b":center+direction*float(attachment.width)*.5,"bottom":0.0 if attachment.kind=="door" else WINDOW_BOTTOM,"top":DOOR_TOP if attachment.kind=="door" else WINDOW_TOP,"width":float(attachment.width)}
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
