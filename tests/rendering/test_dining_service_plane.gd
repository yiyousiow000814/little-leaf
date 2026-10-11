extends "res://tests/diagnostics/capture_dining_service.gd"
const Wipe=preload("res://scripts/cleaning_tool_pose.gd")
func run():
 for forward in [Vector2.RIGHT,Vector2.DOWN,Vector2.UP,Vector2.LEFT]:
  var back=forward.x+forward.y<0;var mirror=-1.0 if forward.x-forward.y<0 else 1.0
  var inset=Wipe.table_inset(forward)
  var ground=Vector2((forward.x-forward.y)*39,(forward.x+forward.y)*19.5)*(1.0-inset)
  var top=(ground+Vector2(0,-Placement.TABLE_HEIGHT))*Vector2(mirror,1)
  var target=top+Vector2(0,-1)
  var near=Vector2(7,-24) if back else Vector2(-7,-24)
  var far=Vector2(-6,-26.5) if back else Vector2(6,-26.5)
  for step in range(2001):
   var pose=Wipe.table_pose(near,far,target,float(step)/2000.0)
   check(pose.contact,"Wiping cloth disappears after the lower tabletop")
   check(absf((pose.hand as Vector2).distance_to(near if pose.use_near else far)-10.5)<.0001,"Wiping alignment stretches an arm")
   for corner in [Vector2(-4,0),Vector2(3,-3),Vector2(7,1),Vector2(0,4)]:
    var rel=(pose.hand as Vector2)+corner-top
    check(pow(rel.x/Placement.ROUND_TOP.x,2)+pow(rel.y/Placement.ROUND_TOP.y,2)<1.0,"Cloth leaves the round tabletop")
    var world=Vector2((rel.x/34+rel.y/17)*.5,(rel.y/17-rel.x/34)*.5)
    check(absf(world.x)<.45 and absf(world.y)<.45 and absf(world.x)+absf(world.y)<.72,"Cloth leaves square or octagonal top")
 await super.run()
