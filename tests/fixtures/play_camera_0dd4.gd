extends RefCounted
## Frozen pre-change Play range oracle: 0dd4db11. Test-only, never runtime.
const Neighborhood=preload("res://tests/fixtures/play_camera_landmarks_0dd4.gd")
const ViewportLayout=preload("res://scripts/cafe_viewport_layout.gd")
## Finite map framing on both screen axes, independent of Decorate's tray.
static func play_rect(viewport:Vector2,hud_top:float=104.0)->Rect2:
	# Keep world scale stable; clear the restored tall HUD in both Play and Decorate.
	return Rect2(Vector2(26,hud_top),Vector2(maxf(250,viewport.x-52),maxf(260,viewport.y-250)))

static func safe_rect(viewport:Vector2,hud_top:float=104.0,insets:Vector4=Vector4.ZERO,browse_top:float=-1.0,reserve_shop:bool=true)->Rect2:
	# Decorate reserves its shop and context row. Play uses its visible HUD
	# and edge insets instead of budgeting for the hidden shop.
	var gap=ViewportLayout.edge_gap(viewport,insets)
	var width=maxf(1.0,viewport.x-insets.x-insets.z)
	if browse_top<0.0:
		browse_top=viewport.y-insets.w-12.0-ViewportLayout.shop_height(viewport,width)
	if not reserve_shop:browse_top=viewport.y-insets.w
	var left=clampf(insets.x+gap,0.0,maxf(0.0,viewport.x-1.0))
	var top=clampf(hud_top,0.0,maxf(0.0,viewport.y-1.0))
	var right=maxf(left+1.0,viewport.x-insets.z-gap)
	var bottom=maxf(top+1.0,browse_top-(ViewportLayout.action_clearance(viewport,insets) if reserve_shop else 0.0)-gap)
	return Rect2(Vector2(left,top),Vector2(right-left,bottom-top))

static func inspection_rect(viewport:Vector2,hud_top:float=104.0,insets:Vector4=Vector4.ZERO)->Rect2:
	# The close view uses the visible world below the HUD. Keep the same
	# budget in Play/Decorate so opening a tray cannot change camera scale.
	var size=Vector2(maxf(1.0,viewport.x),maxf(1.0,viewport.y))
	var top=clampf(hud_top,0.0,size.y-1.0)
	var left=clampf(insets.x,0.0,size.x-1.0)
	return Rect2(Vector2(left,top),Vector2(maxf(1.0,size.x-left-insets.z),maxf(1.0,size.y-top-insets.w)))

static func zoom_limits(viewport:Vector2,base_tile:Vector2,hud_top:float=104.0,insets:Vector4=Vector4.ZERO)->Vector2:
	var minimum=.35 if viewport.x<650 else .70
	# An isometric tile covers 2*x*y screen pixels. Four tile-equivalents
	# fill the usable view at maximum, regardless of map fit or aspect ratio.
	var area=inspection_rect(viewport,hud_top,insets).get_area()
	var tile_area=maxf(.0001,2.0*base_tile.x*base_tile.y)
	return Vector2(minimum,maxf(minimum,sqrt(area/(4.0*tile_area))))

static func clamp_pan(pan:Vector2,base_origin:Vector2,tile:Vector2,width:float,depth:float,viewport:Vector2,hud_top:float=104.0,safe_area:Rect2=Rect2(),inspection_bounds:Rect2=Rect2())->Vector2:
	var scale=tile.x/39.0
	var content=Rect2(base_origin+Vector2(-depth*tile.x,-128.0*scale),Vector2((width+depth)*tile.x,128.0*scale+(width+depth)*tile.y))
	if inspection_bounds.has_area():content=content.merge(Rect2(base_origin+inspection_bounds.position,inspection_bounds.size))
	var view=safe_area if safe_area.has_area() else safe_rect(viewport,hud_top)
	var margin=Vector2(40,32)
	var result=pan if pan.is_finite() else Vector2.ZERO
	for axis in [0,1]:
		var near_edge=view.position[axis]+margin[axis]-content.position[axis]
		var far_edge=view.end[axis]-margin[axis]-content.end[axis]
		# Large maps traverse the safe viewport; small maps may align within it.
		# A fixed centre +/-32 clamp made low corner plots unreachable behind UI.
		var inspection_slack=minf(view.size.y*.35,240.0) if axis==1 else 0.0
		result[axis]=clampf(result[axis],minf(near_edge,far_edge)-inspection_slack,maxf(near_edge,far_edge)+inspection_slack)
	return result

static func inspection_bounds(tile:Vector2)->Rect2:
	# Bounded authored landmarks may be inspected with normal pan controls.
	# This affects traversal only; Fit continues to frame the owned cafe.
	var bounds=Rect2(Vector2.ZERO,Vector2.ZERO)
	var first=true
	for ground in [Neighborhood.LOT,Neighborhood.MOUTH,Neighborhood.PEDESTRIAN_LINK,Neighborhood.STOP_PAD,Neighborhood.SHELTER_ROOF]:
		for point in [ground.position,Vector2(ground.end.x,ground.position.y),ground.end,Vector2(ground.position.x,ground.end.y)]:
			var projected=Vector2((point.x-point.y)*tile.x,(point.x+point.y)*tile.y)
			bounds=Rect2(projected,Vector2.ZERO) if first else bounds.expand(projected)
			first=false
	# Curved approaches extend beyond Neighborhood.STOP_PAD. Traverse their actual cached
	# pavement vertices so both ends remain reachable through normal controls.
	for row in Neighborhood.stop_rows:
		for point in row.points:
			var projected=Vector2((point.x-point.y)*tile.x,(point.x+point.y)*tile.y)
			bounds=bounds.expand(projected)
	# Include the shelter/people silhouette and a small inspection edge.
	return bounds.grow_individual(24*tile.x/39.0,(Neighborhood.SHELTER_HEIGHT+24)*tile.x/39.0,24*tile.x/39.0,24*tile.x/39.0)
