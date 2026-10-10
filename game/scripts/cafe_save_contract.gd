extends RefCounted
## Native-only occupied-layout movement has a separate save namespace.
## Version 14 belongs to an unrelated experiment and is never accepted here.
const SCHEMA = "little_leaf_reconstructed_cafe"
const VERSION = 15
const RECEPTION_REVIEW_VERSION = 18
const RECEPTION_REVIEW_FORMAT = "little_leaf.reception_review.v1"
const RECEPTION_REVIEW_FILE = "user://little_leaf_cafe_reception_review_v18.json"
const RECEPTION_FORMAT = "little_leaf.reception.v2"
const RECEPTION_LEGACY_FORMAT = "little_leaf.reception.v1" # recovered evidence only; not accepted
const CHECKOUT_INTRO_VERSION = 13
const LAYOUT_MOTION_INTRO_VERSION = 15
const PRIMARY_FILE = "user://little_leaf_cafe_layout_motion_v15.json"
const CHECKOUT_FORMAT = "little_leaf.checkout.v1"
const LAYOUT_MOTION_FORMAT = "little_leaf.layout_motion.v1"
const SERVICE_VERSION = 5
const MEAL_DEPARTURE_SERVICE_VERSION = 5
const LEGACY_SERVICE_VERSION = 3
const LEGACY_MAX_VERSION = 12
const PROFILES = [{"file":"little_leaf_cafe_layout_motion_v15.json","app":"Little Leaf Cafe"}]
static func accepts_version(value,allow_reception_review:bool=false)->bool:
 if not (value is int or value is float) or not is_finite(float(value)) or floor(float(value))!=float(value):return false
 return (int(value)>=1 and int(value)<=CHECKOUT_INTRO_VERSION) or int(value)==VERSION or (allow_reception_review and int(value)==RECEPTION_REVIEW_VERSION)
static func has_checkout(version:int)->bool:
 return version>=CHECKOUT_INTRO_VERSION
static func has_layout_motion(version:int)->bool:
 return version>=LAYOUT_MOTION_INTRO_VERSION
static func accepts_header(data:Dictionary,allow_reception_review:bool=false)->bool:
 if not accepts_version(data.get("version"),allow_reception_review):return false
 var version=int(data.version)
 if version==RECEPTION_REVIEW_VERSION:
  if data.get("reception_review_format")!=RECEPTION_REVIEW_FORMAT or data.get("reception_format")!=RECEPTION_FORMAT:return false
  if not data.get("reception") is Dictionary or data.reception.get("format")!=RECEPTION_FORMAT or not data.reception.get("visitors") is Array or not data.reception.get("departures") is Array:return false
 elif data.has("reception_review_format") or data.has("reception_format") or data.has("reception"):return false
 # Check before the legacy early-return paths, and never grant capabilities
 # through a row or nested envelope. Existing defaults remain cardinal.
 for key in data:
  if key in ["reception_review_format","reception_format","reception"]:continue
  if key in ["navigation_format","navigation_phase","footprint_placement_format"] or foreign_runtime_fields(data[key]):return false
 if version==RECEPTION_REVIEW_VERSION and foreign_runtime_fields(data.reception):return false
 if has_checkout(version) and data.get("checkout_format")!=CHECKOUT_FORMAT:return false
 if has_layout_motion(version):return data.get("layout_motion_format")==LAYOUT_MOTION_FORMAT
 if data.has("layout_motion_format"):return false
 # v1/v2 do not otherwise decode a runtime. They still cannot disguise motion.
 var runtime=data.get("runtime",{})
 if runtime is Dictionary:
  if runtime.has("layout_motion_format"):return false
  var guests=runtime.get("customers",[])
  if guests is Array:
   for guest in guests:
    if guest is Dictionary and guest.has("mobility"):return false
 return true

static func foreign_runtime_fields(value,depth:int=0)->bool:
 if depth>12:return true
 if value is Dictionary:
  for key in value:
   if key in ["reception","reception_format","reception_review_format","navigation_format","navigation_phase","footprint_placement_format"]:return true
   if key=="mobility" and value[key] is Dictionary and value[key].get("kind")=="blocked":return true
   if foreign_runtime_fields(value[key],depth+1):return true
 elif value is Array:
  for entry in value:
   if foreign_runtime_fields(entry,depth+1):return true
 return false
