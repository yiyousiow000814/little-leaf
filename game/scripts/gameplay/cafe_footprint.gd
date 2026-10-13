extends RefCounted
## Canonical starter geometry. Historical dimensions are only for migration.
const WIDTH := 12
const DEPTH := 9
const LEGACY_DEPTH := 8
const SAVE_REVISION := 1
const ENTRANCE := Vector2i(0, 5)
const ENTRY_LANDING := ENTRANCE + Vector2i.RIGHT
const DOOR_START := float(ENTRANCE.y)
const DOOR_END := DOOR_START + 1.0
const DOOR_CENTER := (DOOR_START + DOOR_END) * .5
const DOOR_WIDTH := DOOR_END - DOOR_START
const EXTERIOR_DOOR := Vector2(-.5, DOOR_CENTER)
const LEGACY_DOOR_WIDTH := 1.5

static func is_extension_wall(wall:Dictionary)->bool:
	return wall.get("axis")=="z" and int(wall.get("x",-1))==0 and int(wall.get("z",-1))==LEGACY_DEPTH

static func west_shell_depth(walls:Array=[])->int:
	# A player-built wall on the formerly missing edge remains the authoritative
	# wall there, including its finish, height, paid value and hosted openings.
	for wall in walls:
		if is_extension_wall(wall):return LEGACY_DEPTH
	return DEPTH

static func is_shell_edge(wall:Dictionary)->bool:
	return (wall.axis=="x" and int(wall.z)==0 and int(wall.x)>=0 and int(wall.x)<WIDTH) or (wall.axis=="z" and int(wall.x)==0 and int(wall.z)>=0 and int(wall.z)<DEPTH)
