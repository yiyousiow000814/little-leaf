extends RefCounted
## Read-only projection of a strictly validated legacy building snapshot.
## It is not a save codec or live state owner. No caller data is changed and no
## missing product is created. Source-only history stays in the original backup.
const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
const Openings=preload("res://scripts/gameplay/cafe_wall_openings.gd")
const Segments=preload("res://scripts/gameplay/cafe_shell_segments.gd")
const EPS=0.00001

static func project_validated_legacy(products:Dictionary,segments:Dictionary,walls:Array,attachments:Array)->Dictionary:
	var state=Segments.state(products,segments)
	var error=Segments.validate(state,walls)
	if error!="":return {"ok":false,"error":error}
	var result={"ok":true,"edges":{},"openings":[],
		"migration_report":{"removed_ids":[],"discarded_covered_free_ids":[],"opening_aliases":{},"moved_origins":{}}}
	var identities={}
	var lookup:=Segments._legacy_wall_lookup(walls)
	# Only the old optional west-extension edge affects shell root extent.
	var root_walls:Array=walls if lookup.is_empty() else lookup.extension
	for root_id in Openings.SHELL_HOSTS:
		var root=Openings.resolve_host(root_id,root_walls,products)
		for index in Segments.full_count(root_id):
			var id=Segments.key(root_id,index)
			var receipt:Dictionary=segments[id]
			if receipt.get("removed",false):
				result.migration_report.removed_ids.append(id)
				continue
			if index>=Segments.active_count(root_id,root_walls):
				# User decision: discard only the hidden covered free default.
				# No inventory, refund or respawn; the original backup is kept.
				if int(receipt.paid_cost)!=0 or int(receipt.refund_credit)!=0:
					return {"ok":false,"error":"Covered wall has paid value"}
				result.migration_report.discarded_covered_free_ids.append(id)
				continue
			var host=Segments.segment_host(state,root_walls,root_id,index)
			var edge=_edge(id,host,int(receipt.paid_cost),int(receipt.refund_credit),root.a)
			error=_insert(result.edges,identities,edge)
			if error!="":return {"ok":false,"error":error}
	for wall in walls:
		var id="wall:%d"%int(wall.id)
		var paid=int(wall.get("paid_cost",Walls.PRICES[wall.height]))
		var refund=int(wall.get("refund_credit",paid/2))
		var host=Openings.wall_host(wall)
		error=_insert(result.edges,identities,_edge(id,host,paid,refund,host.a))
		if error!="":return {"ok":false,"error":error}
		if wall.has("origin_shell"):result.migration_report.moved_origins[id]=str(wall.origin_shell)
	var opening_ids={}
	for attachment in attachments:
		var id=int(attachment.id)
		if opening_ids.has(id):return {"ok":false,"error":"Duplicate opening identity"}
		opening_ids[id]=true
		var host_walls:Array=walls
		if not lookup.is_empty() and not attachment.has("wall_ids") and attachment.get("host_id") is String:
			host_walls=Segments._legacy_host_rows(attachment.host_id,lookup.by_id,lookup.by_ref,lookup.extension)
		var aperture=Openings.aperture(attachment,host_walls,products)
		if aperture.is_empty():return {"ok":false,"error":"Opening has no legacy host"}
		var supports=_supports(result.edges,aperture,not lookup.is_empty())
		if not supports.ok:return supports
		result.openings.append({"id":id,"kind":str(attachment.kind),"paid_cost":int(attachment.paid_cost),
			"a":aperture.a,"b":aperture.b,"width":float(aperture.width),"bottom":float(aperture.bottom),
			"top":float(aperture.top),"wall_ids":supports.ids})
		result.migration_report.opening_aliases[id]={"host_id":str(attachment.host_id),"offset":float(attachment.offset)}
	return result

static func _edge(id:String,host:Dictionary,paid:int,refund:int,pattern_origin:Vector2)->Dictionary:
	var x=int(host.a.x);var z=int(host.a.y)
	return {"id":id,"edge":Walls.key(host.axis,x,z),"axis":str(host.axis),"x":x,"z":z,
		"height":str(host.height),"material":str(host.material),"paid_cost":paid,"refund_credit":refund,
		"a":host.a,"b":host.b,"physical_rect":Openings.segment_rect({"host":host,"a":host.a,"b":host.b}),
		"pattern_origin":pattern_origin}

static func _insert(edges:Dictionary,identities:Dictionary,edge:Dictionary)->String:
	if edges.has(edge.edge):return "Two installed walls occupy one grid edge"
	if identities.has(edge.id):return "Duplicate installed wall identity"
	edges[edge.edge]=edge
	identities[edge.id]=true
	return ""

static func _coordinate_supports(edges:Dictionary,host:Dictionary,low:float,high:float)->Array:
	var axis:String=host.axis
	var cross:float=host.a.y if axis=="x" else host.a.x
	# Legacy unit grid inputs have finite integer perpendicular coordinates.
	# Keep the old geometry path for an unproven caller or unusual aperture.
	if axis not in ["x","z"] or not is_finite(cross) or cross!=floorf(cross) or absf(cross)>64.0:
		return edges.values()
	if not is_finite(low) or not is_finite(high) or absf(low)>64.0 or absf(high)>64.0 or high<low or high-low>2.0:
		return edges.values()
	var rows:Array=[]
	for along in range(floori(low),ceili(high)):
		var edge_key:=Walls.key(axis,along,int(cross)) if axis=="x" else Walls.key(axis,int(cross),along)
		if edges.has(edge_key):rows.append(edges[edge_key])
	return rows

static func _supports(edges:Dictionary,aperture:Dictionary,indexed:bool=false)->Dictionary:
	var host:Dictionary=aperture.host
	var low=Openings.axis_value(aperture.a,host.axis)
	var high=Openings.axis_value(aperture.b,host.axis)
	var supporting=[]
	for edge in (_coordinate_supports(edges,host,low,high) if indexed else edges.values()):
		if edge.axis!=host.axis:continue
		if not (is_equal_approx(edge.a.y,host.a.y) if host.axis=="x" else is_equal_approx(edge.a.x,host.a.x)):continue
		var start=Openings.axis_value(edge.a,host.axis)
		var finish=Openings.axis_value(edge.b,host.axis)
		if minf(high,finish)-maxf(low,start)>EPS:
			if edge.height!="full":return {"ok":false,"error":"Opening support is not full height"}
			supporting.append({"id":edge.id,"start":start,"finish":finish})
	# A wide legacy aperture stays one object with every supporting edge. A
	# geometric neighbor outside its half-open interval is not a support.
	supporting.sort_custom(func(a,b):return float(a.start)<float(b.start))
	var cursor=low
	var ids:Array[String]=[]
	for support in supporting:
		if float(support.start)>cursor+EPS:return {"ok":false,"error":"Opening crosses a missing wall edge"}
		cursor=maxf(cursor,float(support.finish))
		ids.append(str(support.id))
	if ids.is_empty() or cursor<high-EPS:return {"ok":false,"error":"Opening crosses a missing wall edge"}
	return {"ok":true,"ids":ids}
