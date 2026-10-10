extends RefCounted
## Shared logical-pixel layout budgets. Boundaries are validated by real controls.
const FULL_SHOP_HEIGHT=170.0
const SHORT_SHOP_HEIGHT=144.0
const SELECTION_HEIGHT=84.0
const SHORT_VIEW_HEIGHT=600.0
const MIN_WORLD_HEIGHT=160.0
const WORLD_EDGE_GAP=12.0
const ACTION_CLEARANCE=72.0
const MIN_SAFE_WIDTH=344.0
static func compact_shop(view:Vector2)->bool:return view.y<SHORT_VIEW_HEIGHT
static func shop_height(view:Vector2,safe_width:float=-1)->float:
 var width=view.x if safe_width<0 else safe_width
 if view.y<500.0 and width>=566.0:return 90.0 if view.y<360.0 else 96.0
 return clampf(roundf(view.y*.185),154.0 if width<460 else SHORT_SHOP_HEIGHT,FULL_SHOP_HEIGHT)
static func short_landscape(view:Vector2,insets:Vector4=Vector4.ZERO)->bool:
 return view.y<500.0 and view.x-insets.x-insets.z>=566.0
static func world_budget(view:Vector2,insets:Vector4=Vector4.ZERO)->float:
 return 80.0 if short_landscape(view,insets) else MIN_WORLD_HEIGHT
static func edge_gap(view:Vector2,insets:Vector4=Vector4.ZERO)->float:
 return 4.0 if short_landscape(view,insets) else WORLD_EDGE_GAP
static func action_clearance(view:Vector2,insets:Vector4=Vector4.ZERO)->float:
 return 60.0 if short_landscape(view,insets) else ACTION_CLEARANCE
static func minimum_size(hud_bottom:float,insets:Vector4,view:Vector2,browse_height:float=-1.0)->Vector2:
 var height=browse_height if browse_height>=0 else shop_height(view,view.x-insets.x-insets.z)
 return Vector2(MIN_SAFE_WIDTH+insets.x+insets.z,hud_bottom+2.0*edge_gap(view,insets)+world_budget(view,insets)+action_clearance(view,insets)+height+12.0+insets.w)
static func supports(view:Vector2,hud_bottom:float,insets:Vector4,browse_top:float)->bool:
 return view.x-insets.x-insets.z>=MIN_SAFE_WIDTH and browse_top-hud_bottom-2.0*edge_gap(view,insets)-action_clearance(view,insets)>=world_budget(view,insets)
