extends RefCounted
## Native-only occupied-layout movement has a separate save namespace.
## Version 14 belongs to an unrelated experiment and is never accepted here.
const SCHEMA = "little_leaf_reconstructed_cafe"
const VERSION = 15
const STAFF_NAVIGATION_VERSION = 16
const STAFF_NAVIGATION_FORMAT = "little_leaf.staff_navigation.v1"
const STAFF_NAVIGATION_FILE = "user://little_leaf_cafe_navigation_v16.json"
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
static func accepts_version(value,allow_staff_navigation:bool=false)->bool:
 if not (value is int or value is float) or not is_finite(float(value)) or floor(float(value))!=float(value):return false
 return (int(value)>=1 and int(value)<=CHECKOUT_INTRO_VERSION) or int(value)==VERSION or (allow_staff_navigation and int(value)==STAFF_NAVIGATION_VERSION)
static func has_checkout(version:int)->bool:
 return version>=CHECKOUT_INTRO_VERSION
static func has_layout_motion(version:int)->bool:
 return version>=LAYOUT_MOTION_INTRO_VERSION
static func accepts_header(data:Dictionary,allow_staff_navigation:bool=false)->bool:
 if not accepts_version(data.get("version"),allow_staff_navigation):return false
 var version=int(data.version)
 if version==STAFF_NAVIGATION_VERSION:
  if data.get("navigation_format")!=STAFF_NAVIGATION_FORMAT:return false
 elif data.has("navigation_format"):return false
 var saved_runtime=data.get("runtime",{})
 if saved_runtime is Dictionary:
  # The capability marker belongs only to the envelope, never a runtime row.
  if saved_runtime.has("navigation_format"):return false
  var service=saved_runtime.get("service",{})
  if version!=STAFF_NAVIGATION_VERSION and service is Dictionary:
   var staff=service.get("staff",[])
   if staff is Array:
    for row in staff:
     if row is Dictionary and row.has("navigation_phase"):return false
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
