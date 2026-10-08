extends RefCounted
## Presentation-only foot placement for an already-routed floor work cell.
const Relocation=preload("res://scripts/cafe_staff_relocation.gd")
const Openings=preload("res://scripts/cafe_wall_openings.gd")
const Walls=preload("res://scripts/cafe_walls.gd")
const MAX_OFFSET=.50
const CELL_MARGIN=.05
const CONTACT_GAP=.50

static func offset(position:Vector2,contact:Vector2,model,current:Vector2=Vector2.ZERO)->Vector2:
	return solve(position,contact,model,current).offset

static func cached_offset(position:Vector2,contact:Vector2,model,current:Vector2,cache:Dictionary)->Vector2:
	# A settled cleaner repeats the identical swept-body query every frame.
	# Cache one solve per actor, including the current stance: transitional
	# sweeps and any layout/ownership change still run the original full solve.
	if cache.get("model_id",-1)==model.get_instance_id() and cache.get("revision",-1)==model.revision and cache.get("position") == position and cache.get("contact") == contact and cache.get("current") == current:
		return cache.offset
	var result=offset(position,contact,model,current)
	cache.model_id=model.get_instance_id();cache.revision=model.revision
	cache.position=position;cache.contact=contact;cache.current=current;cache.offset=result
	return result

static func solve(position:Vector2,contact:Vector2,model,current:Vector2=Vector2.ZERO)->Dictionary:
	var toward=contact-position
	var distance=toward.length()
	if distance<=CONTACT_GAP:return {"offset":Vector2.ZERO,"obstruction":""}
	var direction=toward/distance
	var amount=minf(MAX_OFFSET,distance-CONTACT_GAP)
	var low=position.floor()+Vector2.ONE*CELL_MARGIN
	var high=position.floor()+Vector2.ONE*(1.0-CELL_MARGIN)
	# A grid edge on empty floor is not a physical wall. Keep the foot center
	# in its original cell; the existing furniture/wall bodies limit the step.
	for axis in range(2):
		if absf(direction[axis])<.000001:continue
		var edge=high[axis] if direction[axis]>0.0 else low[axis]
		amount=minf(amount,maxf(0.0,(edge-position[axis])/direction[axis]))
	var candidate=direction*amount
	var obstruction=blocked_by(model,position,position+candidate)
	if obstruction=="":obstruction=blocked_by(model,position+current,position+candidate)
	return {"offset":candidate if obstruction=="" else Vector2.ZERO,"obstruction":obstruction}

static func blocked_by(model,start:Vector2,finish:Vector2)->String:
	# Reuse the placement body's radius and the same solid wall rectangles as
	# routing. Test the swept body, including corners, not only its endpoint.
	for item in model.items:
		if str(item.kind)=="rug":continue
		if _segment_near_rect(start,finish,Rect2(Vector2(item.x,item.z),Vector2.ONE),model.STAFF_PLACEMENT_RADIUS):return "furniture "+str(item.id)
	if not Relocation.point_clear(model,start,model.items) or not Relocation.point_clear(model,finish,model.items):return "unowned floor"
	for host in Openings.hosts(model.built_walls,model.shell_products):
		for segment in Openings.solid_segments(host,model.built_walls,model.wall_attachments):
			if Openings.body_touches(segment,start) or Openings.body_touches(segment,finish) or _segment_near_rect(start,finish,Openings.segment_rect(segment),Walls.BODY_RADIUS):return "wall "+str(host.get("id","edge"))
	return ""

static func _segment_near_rect(start:Vector2,finish:Vector2,rect:Rect2,radius:float)->bool:
	if rect.has_point(start) or rect.has_point(finish):return true
	var corners=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	for index in range(4):
		var closest=Geometry2D.get_closest_points_between_segments(start,finish,corners[index],corners[(index+1)%4])
		if closest[0].distance_to(closest[1])<radius-.000001:return true
	return false
