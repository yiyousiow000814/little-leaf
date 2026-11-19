extends RefCounted
## Draw-local lookup of installed wall endpoints and resolved opening cuts.
## Geometry, original attachment order and painter ownership stay unchanged.
const Geometry=preload("res://scripts/gameplay/cafe_wall_openings.gd")
const GRID_LIMIT=64.0 # Canonical cafe and previews are within 0..18.
const MAX_SUPPORT=18 # Save codec bound.

var walls:Array
var apertures:Array[Dictionary]=[]
var endpoints:Dictionary={}
var aperture_cells:Dictionary={}
var grid_enabled=true
var cuts_enabled=true

func _init(wall_rows:Array,attachments:Array)->void:
	walls=wall_rows
	var by_id:Dictionary={}
	for wall in walls:
		var id:=Geometry.Walls.identity(wall)
		if not by_id.has(id):by_id[id]=wall
		var a:=Vector2(float(wall.x),float(wall.z))
		if not _grid_point(a) or wall.axis not in ["x","z"]:
			grid_enabled=false
			continue
		_add(endpoints,Vector2i(a),wall)
		_add(endpoints,Vector2i(a)+(Vector2i.RIGHT if wall.axis=="x" else Vector2i.DOWN),wall)
	for attachment in attachments:
		var opening:=_resolve(attachment,by_id)
		if opening.is_empty():continue
		opening["preview"]=bool(attachment.get("preview",false))
		apertures.append(opening)
		var host:Dictionary=opening.host
		var horizontal:bool=host.axis=="x"
		var axis:int=0 if horizontal else 1
		var cross:float=opening.a.y if horizontal else opening.a.x
		var low:=Geometry.axis_value(opening.a,host.axis)
		var high:=Geometry.axis_value(opening.b,host.axis)
		if not _bounded_integer(cross) or not is_finite(low) or not is_finite(high) or absf(low)>GRID_LIMIT or absf(high)>GRID_LIMIT:
			cuts_enabled=false
			continue
		for along in range(floori(low),ceili(high)):
			_add(aperture_cells,Vector3i(axis,int(cross),along),opening)

func _resolve(attachment:Dictionary,by_id:Dictionary)->Dictionary:
	if not attachment.has("wall_ids") or attachment.wall_ids.size()>MAX_SUPPORT:
		return Geometry.aperture(attachment,walls)
	var support:Array=[]
	for id in attachment.wall_ids:
		if not id is String or not by_id.has(id):return {}
		support.append(by_id[id])
	return Geometry.aperture(attachment,support)

func walls_at(point:Vector2)->Array:
	return endpoints.get(Vector2i(point),[]) if grid_enabled and _grid_point(point) else walls

func apertures_for(host:Dictionary)->Array:
	if cuts_enabled and host.axis in ["x","z"] and _grid_point(host.a) and _grid_point(host.b):
		var horizontal:bool=host.axis=="x"
		var step:=Vector2.RIGHT if horizontal else Vector2.DOWN
		if host.b-host.a==step:
			return aperture_cells.get(Vector3i(0,int(host.a.y),int(host.a.x)) if horizontal else Vector3i(1,int(host.a.x),int(host.a.y)),[])
	return apertures

static func _add(index:Dictionary,key:Variant,row:Dictionary)->void:
	if not index.has(key):index[key]=[]
	index[key].append(row)

static func _bounded_integer(value:float)->bool:
	return is_finite(value) and absf(value)<=GRID_LIMIT and value==floorf(value)

static func _grid_point(point:Vector2)->bool:
	return _bounded_integer(point.x) and _bounded_integer(point.y)
