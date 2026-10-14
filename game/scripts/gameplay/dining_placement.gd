extends RefCounted
## Pure presentation coordinates. Model cells, routes and saved positions stay put.
const CHAIR_PULL=.37
const DOCK_SPEED=1.4
const TABLE_HEIGHT=27.0
const ROUND_TOP=Vector2(25,12)
const PLATE_OFFSET=.14
const CUP_SIDE=.24
static func plane(point:Vector2)->Vector2:
 return Vector2((point.x-point.y)*34,(point.x+point.y)*17-TABLE_HEIGHT)
static func layout(toward_guest:Vector2)->Dictionary:
 var front=toward_guest.normalized() if toward_guest.length_squared()>.01 else Vector2.DOWN
 var side=Vector2(-front.y,front.x)
 return {"plate":plane(front*PLATE_OFFSET),"cup":plane(-front*.33+side*CUP_SIDE),"vase":plane(-front*.32-side*.04),"front":front,"side":side}
static func target_dock(toward_table:Vector2,eating:bool)->Vector2:
 return toward_table.normalized()*CHAIR_PULL if eating else Vector2.ZERO

static func table_height(height:float)->float:
 # Keep floor contacts fixed while lowering the dining top and supports together.
 return height if height<=1.0 else 1.0+(height-1.0)*(TABLE_HEIGHT-1.0)/32.0
