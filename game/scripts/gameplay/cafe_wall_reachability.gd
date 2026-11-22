extends RefCounted
## Structural pedestrian reachability, separate from rendering wall cuts.
const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
const Openings=preload("res://scripts/gameplay/cafe_wall_openings.gd")
const MAX_CANONICAL_DOOR_SUPPORTS=18 # Save codec bound; larger inputs use the legacy resolver.

static func _indexed_aperture(attachment:Dictionary,walls:Array,by_id:Dictionary)->Dictionary:
	if not attachment.has("wall_ids") or attachment.wall_ids.size()>MAX_CANONICAL_DOOR_SUPPORTS:
		return Openings.aperture(attachment,walls)
	var support:Array=[]
	for id in attachment.wall_ids:
		if not id is String or not by_id.has(id):return {}
		support.append(by_id[id])
	# Reuse the canonical ordered support, product and clearance geometry.
	# The resolver scans only the bounded support set, not the entire wall list.
	return Openings.aperture(attachment,support)

static func _clear_cut(position:float,low:float,high:float,clearance:float)->bool:
	# Match the installed-door midpoint test. The render cut list is not rebuilt.
	return position>low+clearance+.00001 and position<high-clearance-.00001

## Same answer as the direct midpoint oracle only for supported grid rows.
## Avoid silently replacing first-wall and legacy host behavior in edit/save guards.
static func direct_edge_snapshot(walls:Array,attachments:Array)->Variant:
	var edges:Dictionary={}
	var ids:Dictionary={}
	for wall in walls:
		var x:float=float(wall.x)
		var z:float=float(wall.z)
		if wall.axis not in ["x","z"] or not is_finite(x) or not is_finite(z) or absf(x)>64.0 or absf(z)>64.0 or x!=floorf(x) or z!=floorf(z):return null
		var edge:=Walls.key_of(wall)
		var id:=Walls.identity(wall)
		if edges.has(edge) or ids.has(id):return null
		edges[edge]=true;ids[id]=true
	for attachment in attachments:
		if attachment.kind!="door":continue
		if not attachment.has("wall_ids") or not attachment.wall_ids is Array or attachment.wall_ids.size()>MAX_CANONICAL_DOOR_SUPPORTS:return null
		var offset:=float(attachment.offset)
		var width:=float(attachment.width)
		if not is_finite(offset) or not is_finite(width) or absf(offset)>64.0 or width<=0.0 or width>64.0:return null
	return blocked_grid_edges(walls,attachments)

static func blocked_grid_edges(walls:Array,attachments:Array)->Dictionary:
	# One snapshot of unit grid edges. Door support is resolved in authored
	# order once per opening; windows never affect pedestrian clearance.
	var blocked:Dictionary={}
	if walls.is_empty():return blocked
	var by_id:Dictionary={}
	var min_coord:=Vector2i(int(walls[0].x),int(walls[0].z))
	var max_coord:=min_coord
	for wall in walls:
		var id:=Walls.identity(wall)
		if not by_id.has(id):by_id[id]=wall
		blocked[Walls.key_of(wall)]=true
		var cell:=Vector2i(int(wall.x),int(wall.z))
		min_coord=min_coord.min(cell);max_coord=max_coord.max(cell)
	for attachment in attachments:
		if attachment.kind!="door":continue
		var opening:=_indexed_aperture(attachment,walls,by_id)
		if opening.is_empty():continue
		var axis:String=opening.host.axis
		var horizontal:=axis=="x"
		var a:Vector2=opening.a
		var cross:=a.y if horizontal else a.x
		if not is_equal_approx(cross,roundf(cross)):continue
		var low:=Openings.axis_value(a,axis)
		var high:=Openings.axis_value(opening.b,axis)
		# Only the overlapped unit edges can contain an open midpoint.
		var extent_start:=float(min_coord.x if horizontal else min_coord.y)
		var extent_end:=float((max_coord.x if horizontal else max_coord.y)+1)
		if not is_finite(low) or not is_finite(high) or high<=extent_start or low>=extent_end:continue
		var first:=floori(maxf(extent_start,low))
		var end:=ceili(minf(extent_end,high))
		for i in range(first,end):
			if not _clear_cut(.5,maxf(0.0,low-i),minf(1.0,high-i),.23):continue
			var edge:=Walls.key(axis,i,roundi(cross)) if horizontal else Walls.key(axis,roundi(cross),i)
			blocked.erase(edge)
	return blocked
