extends RefCounted
## Gameplay-only snapshot. Door geometry and narrow-phase tests are still
## owned by CafeWallOpenings; no live actor/model rows enter the cache.
const Openings=preload("res://scripts/gameplay/cafe_wall_openings.gd")
const GRID_LIMIT:=64.0
const MAX_SUPPORTS:=18
const MAX_BUCKET_CELLS:=36
const BODY_RADIUS:=.23

var segments:Array[Dictionary]=[]
var _all_indices:Array[int]=[]
var _buckets:Dictionary={}
var _can_query_grid:=true

func _init(hosts:Array,walls:Array,attachments:Array)->void:
	var apertures:=resolved_apertures(walls,attachments,true)
	var aperture_cells:Dictionary={}
	var can_bucket_cuts:=true
	for opening in apertures:
		var axis:String=opening.host.axis
		var cross:float=opening.a.y if axis=="x" else opening.a.x
		var low:=Openings.axis_value(opening.a,axis)
		var high:=Openings.axis_value(opening.b,axis)
		if not _grid_line(cross) or not _bounded(low) or not _bounded(high):
			can_bucket_cuts=false
			continue
		for along in range(floori(low),ceili(high)):
			_add(aperture_cells,Vector3i(0 if axis=="x" else 1,int(cross),along),opening)
	for host in hosts:
		var candidates:Array=apertures
		var a:Vector2=host.a
		var direction:=Vector2.RIGHT if host.axis=="x" else Vector2.DOWN
		if can_bucket_cuts and _grid_line(a.x) and _grid_line(a.y) and host.b-a==direction:
			var cell:=Vector3i(0,int(a.y),int(a.x)) if host.axis=="x" else Vector3i(1,int(a.x),int(a.y))
			candidates=aperture_cells.get(cell,[])
		_append_segments(host,candidates)
	for i in range(segments.size()):_all_indices.append(i)
	for i in range(segments.size()):
		var rect:=Openings.segment_rect(segments[i])
		if not _small_range(rect.position,rect.end):
			_can_query_grid=false;_buckets.clear();break
		for x in range(floori(rect.position.x),floori(rect.end.x)+1):
			for z in range(floori(rect.position.y),floori(rect.end.y)+1):
				_add(_buckets,Vector2i(x,z),i)

## In input order, using the first installed wall per identity just like
## resolve_ids. Legacy host references still use the full geometry resolver.
static func resolved_apertures(walls:Array,attachments:Array,doors_only:bool=false)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if attachments.is_empty():return result
	var by_id:Dictionary={}
	for wall in walls:
		var id:=Openings.Walls.identity(wall)
		if not by_id.has(id):by_id[id]=wall
	for attachment in attachments:
		if doors_only and attachment.kind!="door":continue
		var opening:=_indexed_aperture(attachment,walls,by_id)
		if not opening.is_empty():result.append(opening)
	return result

static func _indexed_aperture(attachment:Dictionary,walls:Array,by_id:Dictionary)->Dictionary:
	if not attachment.has("wall_ids") or attachment.wall_ids.size()>MAX_SUPPORTS:
		return Openings.aperture(attachment,walls)
	var supports:Array=[]
	for id in attachment.wall_ids:
		if not id is String or not by_id.has(id):return {}
		supports.append(by_id[id])
	return Openings.aperture(attachment,supports)

func _append_segments(host:Dictionary,apertures:Array)->void:
	# Match the reference assembly exactly; only cut candidates differ.
	var direction:Vector2=(host.b-host.a).normalized()
	var cursor:=0.0
	var length:float=host.a.distance_to(host.b)
	for cut in Openings.cuts(host,[],[],true,apertures):
		if cut.from>cursor+.00001:segments.append({"a":host.a+direction*cursor,"b":host.a+direction*float(cut.from),"normal":host.normal,"host":host})
		cursor=maxf(cursor,float(cut.to))
	if cursor<length-.00001:segments.append({"a":host.a+direction*cursor,"b":host.b,"normal":host.normal,"host":host})

func crosses(a:Vector2,b:Vector2)->bool:
	for i in _indices(a.min(b),a.max(b)) if a.is_finite() and b.is_finite() else _all_indices:
		if Openings.crosses(segments[i],a,b):return true
	return false

func touches_body(point:Vector2)->bool:
	var radius:=Vector2.ONE*BODY_RADIUS
	for i in _indices(point-radius,point+radius):
		if Openings.body_touches(segments[i],point,BODY_RADIUS):return true
	return false

func _indices(low:Vector2,high:Vector2)->Array:
	if not _can_query_grid or not _small_range(low,high):return _all_indices
	var first:=Vector2i(floori(low.x),floori(low.y))
	var last:=Vector2i(floori(high.x),floori(high.y))
	if first==last:return _buckets.get(first,[])
	var seen:Dictionary={}
	var result:Array[int]=[]
	for x in range(first.x,last.x+1):
		for z in range(first.y,last.y+1):
			for index in _buckets.get(Vector2i(x,z),[]):
				if seen.has(index):continue
				seen[index]=true;result.append(index)
	result.sort() # Preserve original ordered narrow-phase candidates.
	return result

static func _add(index:Dictionary,key:Variant,row:Variant)->void:
	if not index.has(key):index[key]=[]
	index[key].append(row)

static func _small_range(low:Vector2,high:Vector2)->bool:
	if not _bounded(low.x) or not _bounded(low.y) or not _bounded(high.x) or not _bounded(high.y):return false
	var width:=floori(high.x)-floori(low.x)+1
	var depth:=floori(high.y)-floori(low.y)+1
	return width>0 and depth>0 and width*depth<=MAX_BUCKET_CELLS

static func _bounded(value:float)->bool:
	return is_finite(value) and absf(value)<=GRID_LIMIT

static func _grid_line(value:float)->bool:
	return _bounded(value) and value==floorf(value)
