extends RefCounted
## Physical point clearance shared by floor-cleaning approach.
static func point_clear(model,point:Vector2,layout:Array)->bool:
 var cell=Vector2i(point.floor())
 if cell.x<1 or not model.is_floor_owned(cell):return false
 for item in layout:
  if str(item.kind)=="rug":continue
  var minimum=Vector2(item.x,item.z)
  if point.distance_squared_to(point.clamp(minimum,minimum+Vector2.ONE))<model.STAFF_PLACEMENT_RADIUS*model.STAFF_PLACEMENT_RADIUS:return false
 return true

