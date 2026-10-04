extends RefCounted
## Presentation-only kitchen worktop proportions. Keep ground footprints and
## characters unchanged; compress the cabinet, translate its equipment whole.
const SOURCE_WORKTOP_HEIGHT := 29.0
const WORKTOP_HEIGHT := 20.0
const DROP := SOURCE_WORKTOP_HEIGHT-WORKTOP_HEIGHT

static func height(source_height:float)->float:
 if source_height<=1.0:return source_height
 if source_height>=SOURCE_WORKTOP_HEIGHT:return source_height-DROP
 return 1.0+(source_height-1.0)*(WORKTOP_HEIGHT-1.0)/(SOURCE_WORKTOP_HEIGHT-1.0)

static func surface(local:Vector2,source_height:float,rotation:int=0)->Vector2:
 var q=local.rotated(posmod(rotation,4)*PI/2)
 return Vector2((q.x-q.y)*34,(q.x+q.y)*17-height(source_height))

static func is_kitchen_part(part:String)->bool:
 return part in ["counter","sink","stove_base","stove_pan","stove_controls","beverage_base","beverage_machine","beverage_accessories"]
