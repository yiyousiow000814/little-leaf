extends RefCounted
## Presentation-only kitchen worktop proportions. Keep ground footprints and
## characters unchanged; compress the cabinet, translate its equipment whole.
const SOURCE_WORKTOP_HEIGHT := 29.0
const WORKTOP_HEIGHT := 20.0
const DROP := SOURCE_WORKTOP_HEIGHT-WORKTOP_HEIGHT
# Presentation-only single-basin sink. A 28px plate fits inside this rim.
const SINK_BASIN_CENTER := Vector2(0.0,.025)
const SINK_BASIN_OUTER := Vector2(.36,.32)
const SINK_BASIN_INNER := Vector2(.325,.295)
const SINK_RIM_HEIGHT := 30.0
const SINK_OPENING_HEIGHT := 30.2
const SINK_BOTTOM_HEIGHT := 21.5
const SINK_BOTTOM_RADIUS := Vector2(.312,.285)
const SINK_STACK_HEIGHT := 23.5
const SINK_TAP_CREST_HEIGHT := 58.0
const SINK_TAP_OUTLET_HEIGHT := 53.5

static func sink_plate_anchor(rotation:int)->Vector2:
 return surface(SINK_BASIN_CENTER,SINK_STACK_HEIGHT,rotation)

static func sink_outline(radius:Vector2,source_height:float,rotation:int)->PackedVector2Array:
 var result=PackedVector2Array()
 for index in range(64):
  var angle=index*TAU/64.0
  result.append(surface(SINK_BASIN_CENTER+Vector2(cos(angle)*radius.x,sin(angle)*radius.y),source_height,rotation))
 return result

static func sink_tap_in_front(rotation:int)->bool:
 return Vector2(0,-.35).rotated(posmod(rotation,4)*PI/2).dot(Vector2.ONE)>0.0

static func height(source_height:float)->float:
 if source_height<=1.0:return source_height
 if source_height>=SOURCE_WORKTOP_HEIGHT:return source_height-DROP
 return 1.0+(source_height-1.0)*(WORKTOP_HEIGHT-1.0)/(SOURCE_WORKTOP_HEIGHT-1.0)

static func surface(local:Vector2,source_height:float,rotation:int=0)->Vector2:
 var q=local.rotated(posmod(rotation,4)*PI/2)
 return Vector2((q.x-q.y)*34,(q.x+q.y)*17-height(source_height))

static func is_kitchen_part(part:String)->bool:
 return part in ["counter","sink","stove_base","stove_pan","stove_controls","beverage_base","beverage_machine","beverage_accessories"]
