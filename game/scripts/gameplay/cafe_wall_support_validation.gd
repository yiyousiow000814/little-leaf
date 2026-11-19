extends RefCounted
## Installed wall opening validation. Keep renderer geometry and ordered error
## precedence; index only the bounded, canonical footprint in supported saves.
const Geometry=preload("res://scripts/gameplay/cafe_wall_openings.gd")
const EPS:=.00001
const SUPPORT_LIMIT:=18
const GRID_LIMIT:=64.0

static func error(walls:Array,attachments:Array)->String:
	if attachments.is_empty():return ""
	var by_id:Dictionary={}
	for wall in walls:
		if wall.axis not in ["x","z"] or not _grid_coordinate(float(wall.x)) or not _grid_coordinate(float(wall.z)):
			return Geometry.installed_support_error(walls,attachments)
		var id:=Geometry.Walls.identity(wall)
		if not by_id.has(id):by_id[id]=wall # Match first original support identity.
	var seen_ids:Dictionary={}
	var rows:Array=[]
	var lines:Dictionary={}
	for i in range(attachments.size()):
		var attachment:Dictionary=attachments[i]
		var id:=int(attachment.id)
		if seen_ids.has(id) or not attachment.get("wall_ids") is Array or attachment.wall_ids.size()>SUPPORT_LIMIT:
			return Geometry.installed_support_error(walls,attachments)
		seen_ids[id]=true
		var supports:Array=[]
		for support_id in attachment.wall_ids:
			if not support_id is String or not by_id.has(support_id):
				supports.clear()
				break
			supports.append(by_id[support_id])
		var opening:=Geometry.aperture(attachment,supports) if supports.size()==attachment.wall_ids.size() else {}
		rows.append({"opening":opening,"supports":supports})
		if opening.is_empty():continue
		var axis:String=opening.host.axis
		var cross:float=opening.host.a.y if axis=="x" else opening.host.a.x
		var low:=Geometry.axis_value(opening.a,axis)
		var high:=Geometry.axis_value(opening.b,axis)
		if not is_finite(low) or not is_finite(high) or high<low or not _grid_coordinate(cross):
			return Geometry.installed_support_error(walls,attachments)
		if high-low<=EPS:continue
		var line:=Vector2i(0 if axis=="x" else 1,int(cross))
		if not lines.has(line):lines[line]=[]
		lines[line].append({"index":i,"low":low,"high":high})
	var overlaps:=_overlapping_rows(lines)
	# Resolve conflicts in original attachment order, not geometry sort order.
	# Even a later malformed-but-resolved opening can conflict with an earlier
	# row; this is why overlap discovery precedes the ordered error checks.
	for i in range(attachments.size()):
		var attachment:Dictionary=attachments[i]
		var opening:Dictionary=rows[i].opening
		if opening.is_empty() or opening.host.height!="full":return "Opening needs complete full-height wall support"
		var low:=float(attachment.offset)-float(attachment.width)*.5
		var high:=float(attachment.offset)+float(attachment.width)*.5
		if low < -EPS or high>opening.host.a.distance_to(opening.host.b)+EPS:return "Opening extends beyond its supporting walls"
		for wall in rows[i].supports:
			var origin:=Vector2(float(wall.x),float(wall.z))
			var start:=Geometry.axis_value(origin-opening.host.a,opening.host.axis)
			if minf(high,start+1.0)-maxf(low,start)<=EPS:return "Opening lists an unused supporting wall"
		if overlaps.has(i):return "A door or window already occupies this wall interval"
	return ""

static func _overlapping_rows(lines:Dictionary)->Dictionary:
	var result:Dictionary={}
	for line in lines.values():
		line.sort_custom(func(a,b):return float(a.low)<float(b.low))
		var furthest_end:float=-INF
		for i in range(line.size()):
			var row:Dictionary=line[i]
			# Previous intervals start no later; only their farthest end matters.
			var previous:=minf(float(row.high),furthest_end)-float(row.low)>EPS
			# Later intervals each have length > EPS; if the very next start
			# cannot overlap this row, no later start can overlap it either.
			var subsequent:bool=i+1<line.size() and float(row.high)-float(line[i+1].low)>EPS
			if previous or subsequent:result[int(row.index)]=true
			furthest_end=maxf(furthest_end,float(row.high))
	return result

static func _grid_coordinate(value:float)->bool:
	return is_finite(value) and absf(value)<=GRID_LIMIT and value==floorf(value)
