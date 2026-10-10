extends RefCounted
const StoveLayout=preload("res://scripts/cafe_stove_layout.gd")
const CookingFood=preload("res://scripts/cooking_tool_pose.gd")
# Presentation only: the cooking assembly fills the existing range naturally.
const PAN_WIDTH=1.90
const PAN_DEPTH=1.62
const PAN_HANDLE_HEIGHT=39.0
# Artwork uses a 34px basis; the live grid uses 39px. This is exactly one tile.
const STOVE_TILE_SPAN=39.0/34.0
# Modular cabinet tops use the same one-cell ground diamond as the range.
# Equipment, usable slots, model occupancy and prices are independent.
const CABINET_TILE_SPAN=39.0/34.0
# Plain full-cell cabinet body reaches the floor, with no feet or styled base.
const CABINET_SOLID_BODY=true
# The enlarged rear handle keeps its lower collar but no extra ground outset.
# This keeps its full anti-alias envelope inside the single occupied tile.
const PAN_REAR_HANDLE_DROP=2.0
const PAN_REAR_HANDLE_OUTSET=0.0
const KitchenGeometry=preload("res://scripts/kitchen_worktop_geometry.gd")
var kitchen_height := false
var checkout_height := false
const CheckoutArt=preload("res://scripts/cafe_checkout_art.gd")
# Original rotatable isometric furniture. Geometry and use-side details share
# the floor's 2:1 ground basis; height is never screen-rotated.
var a: Node2D
var origin: Vector2
var turn: int

# Experimental: off until native same-state pixels and frame callbacks are checked.
# This singleton holds only static art. It never receives model/service records.
const StaticAtlas = preload("res://scripts/furniture_static_atlas.gd")
static var static_atlas = StaticAtlas.new()
var cache_enabled := false
var use_retained_station_parts=true
# Matched control: keep the established station/decor cache but bypass new items.
var expanded_parts_enabled := true

func prepare_cache(artist: Node2D):
	if cache_enabled: static_atlas.request(artist)

func _can_cache(artist: Node2D,p:Vector2=Vector2.ZERO) -> bool:
	# A single faded composite is not equal to individually faded overlapping
	# primitives. Keep the original .63-opacity drag preview exactly intact.
	return cache_enabled and static_atlas.is_ready() and (not "opacity" in artist or is_equal_approx(float(artist.opacity),1.0)) and artist.art_cache_covers(Rect2(p+Vector2(-40,-100),Vector2(80,140)),StaticAtlas.BAKE_SCALE)

func _cached_part(artist: Node2D,part: String,p: Vector2,rotation: int):
	static_atlas.draw_part(artist,part,p,posmod(rotation,4))

# Guards in the real artist's table body/chair/plant/lamp helpers use this.
# The bake artist has cache_enabled=false and executes their original geometry.
# Table vase offsets and all service payloads are deliberately absent.
func try_draw_static(artist: Node2D,part: String,p: Vector2,rotation=0) -> bool:
	if not expanded_parts_enabled or not part in StaticAtlas.PARTS:return false
	prepare_cache(artist)
	if not _can_cache(artist,p):return false
	_cached_part(artist,part,p,rotation)
	return true

# Native tests can inspect this exact sequence without baking or a live model.
static func part_sequence(kind: String,rotation: int) -> Array:
	var r := posmod(rotation,4)
	match kind:
		"stove": return ["stove_base","heat","payload","stove_pan","stove_controls"] if r in [1,2] else ["stove_base","heat","stove_pan","payload","stove_controls"]
		"beverage":
			var parts:Array=["beverage_base"]
			if not beverage_accessories_in_front(r):parts.append("beverage_accessories")
			if r in [1,2]:parts.append("payload")
			parts.append("beverage_machine")
			if r in [0,3]:parts.append("payload")
			if beverage_accessories_in_front(r):parts.append("beverage_accessories")
			return parts
		"bench": return ["bench_back","bench_seat"] if r in [1,2] else ["bench_seat","bench_back"]
		"counter","sink","bookshelf","divider","rug": return [kind]
		_: return []

func draw_item(artist: Node2D,kind: String,p: Vector2,rotation: int,id=0):
	checkout_height=false
	if kind=="register":
		kitchen_height=false
		return CheckoutArt.draw_register(self,artist,p,rotation,id)
	var sequence := part_sequence(kind,rotation)
	if sequence.is_empty(): return false
	prepare_cache(artist)
	var cached=_can_cache(artist,p)
	var retained=use_retained_station_parts and artist.has_method("retain_native_local_object") and artist.use_native_object_nodes and artist.canvas_stream.active
	if not cached and not retained:return _draw_item_legacy(artist,kind,p,rotation,id)
	a=artist;origin=p;turn=posmod(rotation,4)
	for part in sequence:
		if part=="heat":
			if artist.has_method("_stove_heat"):artist._stove_heat(id,turn)
		elif part=="payload":
			if artist.has_method("_station_payloads"): artist._station_payloads(id,kind,turn)
		elif part=="stove_pan":draw_stove_vessel(artist,p,turn,id)
		else:
			if retained:
				var paint=_paint_retained_part.bind(artist,part,turn,cached)
				var placement=artist._art_transform.translated_local(p)
				if not artist.retain_native_local_object(paint,["station-part",part,turn,cached],placement):_paint_retained_part_at(artist,part,p,turn,cached)
			else:_paint_retained_part_at(artist,part,p,turn,cached)
	return true

# Every atlas cell is rendered from these original procedural helpers. Keep
# quarter-turn geometry, static subparts and live payload slots independent.
func draw_static_part(artist: Node2D,part: String,p: Vector2,rotation: int):
	checkout_height=false
	kitchen_height=KitchenGeometry.is_kitchen_part(part)
	a=artist;origin=p;turn=posmod(rotation,4)
	match part:
		"stove_base": _stove_base()
		"stove_pan": stove_pan()
		"stove_controls": _stove_controls()
		"beverage_base": _beverage_base()
		"beverage_machine": espresso()
		"beverage_accessories": beverage_accessories()
		"bench_seat": _draw_bench_part_legacy(artist,p,turn,false)
		"bench_back": _draw_bench_part_legacy(artist,p,turn,true)
		"counter","sink","bookshelf","divider","rug": _draw_item_legacy(artist,part,p,turn,0)
		"table_body": artist._table_body(p)
		"chair_seat": artist._chair(p,turn,false)
		"chair_back": artist._chair(p,turn,true)
		"plant": artist._plant(p)
		"lamp": artist._lamp(p)

func _stove_base():
	# The initial range has one centered burner and one cooking surface.
	box(0,0,STOVE_TILE_SPAN-.025,STOVE_TILE_SPAN-.025,1,29,"b7c4af","849e8c","708d7d","839a84")
	box(0,0,STOVE_TILE_SPAN,STOVE_TILE_SPAN,29,31,"d9deca","adbca9","a2b3a0")
	for burner in [StoveLayout.POT_CENTER]:
		top_ellipse(burner.x,burner.y,31.2,.155*PAN_WIDTH,.155*PAN_WIDTH,"536e61")
		top_ellipse(burner.x,burner.y,31.4,.11*PAN_WIDTH,.11*PAN_WIDTH,"8f9f88")
		top_ellipse(burner.x,burner.y,31.6,.063*PAN_WIDTH,.063*PAN_WIDTH,"5b7665")
		for d in [Vector2.RIGHT,Vector2.DOWN]:
			edge(point(burner.x-d.x*.18*PAN_WIDTH,burner.y-d.y*.18*PAN_WIDTH,31.8),point(burner.x+d.x*.18*PAN_WIDTH,burner.y+d.y*.18*PAN_WIDTH,31.8),"556e60",1.15)

	# A short raised grate supports the pan and leaves a real burner gap.
	for q in [Vector2(-.13,0),Vector2(.13,0),Vector2(0,.13)]:
		edge(point(StoveLayout.POT_CENTER.x+q.x*PAN_WIDTH,StoveLayout.POT_CENTER.y+q.y*PAN_WIDTH,31.5),point(StoveLayout.POT_CENTER.x+q.x*PAN_WIDTH,StoveLayout.POT_CENTER.y+q.y*PAN_WIDTH,34),"536e61",1.25)

func draw_stove_heat(artist:Node2D,p:Vector2,rotation:int,elapsed_seconds:float):
	kitchen_height=true;a=artist;origin=p;turn=posmod(rotation,4)
	var base=point(StoveLayout.POT_CENTER.x,StoveLayout.POT_CENTER.y,34)+Vector2(0,2.15)
	# The live blue gas jets are below the pan, not painted over the food.
	# Drawn before the pan layer, the upper tips are naturally occluded.
	for i in range(3):
		var x=(-7.3+i*7.3)*PAN_WIDTH
		var at=base+Vector2(x,.6*(1.0-absf(x)/(7.3*PAN_WIDTH)))
		var height=3.1+.60*sin(elapsed_seconds*8.5+i*1.9)
		a.rounded_poly([at+Vector2(-1.0,0),at+Vector2(-.65,-height*.55),at+Vector2(.12,-height),at+Vector2(.9,-height*.25),at+Vector2(.9,0)],.22,"59a9cf")
		a.line(at+Vector2(0,-.05),at+Vector2(.1,-height*.60),"c2e4d5",.65)

func _stove_controls():
	if front_visible():
		# One centered control for the single burner; this pedestal has no oven.
		var marker=point(0,STOVE_TILE_SPAN*.5,26)
		a.ellipse(marker,Vector2(1.8,1.8),"f0e5c7")
		# A one-pixel indicator is smaller than the generic AA feather. Draw
		# its real capsule silhouette so HD/4x atlas views cannot turn it
		# into a pinched square. Keep its color and knob bounds intact.
		a._face_line(marker,marker+Vector2(0,-1),"73806a",.7)
		for tip in [marker,marker+Vector2(0,-1)]:
			a._face_ellipse(tip,Vector2.ONE*.35,"73806a")

func _beverage_base():
	cabinet(CABINET_TILE_SPAN,CABINET_TILE_SPAN,29,"b7bd9d","9fab8f","e9dfc0")
	# Drip tray has the same rotated front as the cup's actual preparation slot.
	box(.17,.26,.27,.22,29,30,"aebba6","8c9f8d","91a18e")
	for x in [.09,.15,.21,.27]:edge(point(x,.17,30.4),point(x,.34,30.4),"7e9380",.7)

func point(x: float,z: float,h: float=0.0) -> Vector2:
	var q=Vector2(x,z).rotated(turn*PI/2.0)
	var height=KitchenGeometry.height(h) if kitchen_height else (CheckoutArt.height(h) if checkout_height else h)
	return origin+Vector2((q.x-q.y)*34,(q.x+q.y)*17-height)
func front_visible() -> bool:
	return Vector2(0,1).rotated(turn*PI/2.0).dot(Vector2.ONE)>0
func face(points: Array,c,rounding=1.5): a.rounded_poly(points,rounding,c)
func edge(p: Vector2,q: Vector2,c,w=1.0): a.line(p,q,c,w)
func top_ellipse(x: float,z: float,h: float,rx: float,rz: float,c):
	var pts=[]
	for i in range(32):pts.append(point(x+cos(i*TAU/32)*rx,z+sin(i*TAU/32)*rz,h))
	a.poly(pts,c)
func box(x: float,z: float,w: float,d: float,lo: float,hi: float,top,front,side,back=""):
	var corners=[Vector2(x-w/2,z-d/2),Vector2(x+w/2,z-d/2),Vector2(x+w/2,z+d/2),Vector2(x-w/2,z+d/2)]
	var normals=[Vector2(0,-1),Vector2(1,0),Vector2(0,1),Vector2(-1,0)]
	for i in range(4):
		if normals[i].rotated(turn*PI/2).dot(Vector2.ONE)<=0:continue
		var b=corners[i];var c=corners[(i+1)%4]
		var color=front if i==2 else (back if i==0 and back!="" else side)
		face([point(b.x,b.y,lo),point(c.x,c.y,lo),point(c.x,c.y,hi),point(b.x,b.y,hi)],color)
	var pts=[]
	for q in corners:pts.append(point(q.x,q.y,hi))
	face(pts,top,2.0)
func cabinet(w=CABINET_TILE_SPAN,d=CABINET_TILE_SPAN,h=29.0,paint="c3a168",side="b49461",top="e6cca0"):
	box(0,0,w,d,0,h,top,paint,side,paint)
	if not front_visible():return
	var z=d/2+.006
	for part in [-1,1]:
		var l=(-w/2+w*.08235) if part<0 else w*.02118
		var r=-w*.02118 if part<0 else (w/2-w*.08235)
		face([point(l,z,8),point(r,z,8),point(r,z,h-5),point(l,z,h-5)],"bc9a63",1)
		edge(point(l+.025,z,h-5),point(r-.025,z,h-5),"d4b782",.75)
		edge(point((r-.055) if part<0 else (l+.055),z,16),point((r-.055) if part<0 else (l+.055),z,20),"8f7950",1.6)
func cup(x: float,z: float,h: float):
	var c=point(x,z,h)
	a.rounded_poly([c+Vector2(-3.5,-6),c+Vector2(3.5,-6),c+Vector2(2.5,0),c+Vector2(-2.5,0)],1,"fff1d2")
	a.outlined_ellipse(c+Vector2(0,-6),Vector2(3.5,1.6),"b08c60","eee2bb",.6)
	a.art_arc(c+Vector2(3,-3.5),2.5,-PI/2,PI/2,10,a.col("eee2bb"),1.2)
func espresso():
	# Original countertop juice dispenser, recognisable reservoir, lid and tap.
	# Kept as a part name for existing atlas compatibility; it is no espresso box.
	box(.08,-.13,.45,.36,29,35,"c9d4be","8ca28d","7d9683")
	box(.08,-.13,.44,.34,35,53,"e3e9cf","d6dfbe","bdceb0")
	box(.08,-.13,.39,.29,36,47.5,"f4d790","e7be6c","d2ac60")
	edge(point(-.08,-.29,39),point(-.08,-.29,51),Color(.99,1,.89,.58),1.2)
	edge(point(.285,-.26,37),point(.285,-.26,51),Color(.98,1,.9,.45),.9)
	box(.08,-.13,.47,.38,53,55,"8ca58f","6f8e79","698570")
	top_ellipse(.08,-.13,56,.065,.065,"b9c7aa")
	if front_visible():
		var path=beverage_spout_path(turn)
		# One welded silhouette follows a tangent fillet; separate AA line ends
		# previously made the elbow look like several disconnected blocks.
		var vertices:Array=[]
		for q in beverage_spout_silhouette(turn):vertices.append(origin+q)
		a.poly(vertices,"5e7d69")
		edge(point(.17,.08,43),point(.17,.08,48),"466b57",1.1)
		a.ellipse(point(.17,.08,48),Vector2(1.7,1.0),"527862")
static func beverage_spout_path(rotation:int)->PackedVector2Array:
	var start=KitchenGeometry.surface(Vector2(.17,.06),43,rotation)
	var elbow=KitchenGeometry.surface(Vector2(.17,.24),43,rotation)
	var end=KitchenGeometry.surface(Vector2(.17,.24),39.5,rotation)
	var incoming=elbow-(elbow-start).normalized()*1.2
	var outgoing=elbow+(end-elbow).normalized()*1.2
	var path=PackedVector2Array([start,incoming])
	for index in range(1,13):
		var t=float(index)/12
		path.append((1-t)*(1-t)*incoming+2*(1-t)*t*elbow+t*t*outgoing)
	path.append(end)
	return path
static func beverage_spout_silhouette(rotation:int)->PackedVector2Array:
	# Float coordinates retain subpixel tube width; polygon offsets rounded
	# this small equipment to coarse corners in the native closeup.
	var path=beverage_spout_path(rotation)
	var normals=PackedVector2Array()
	for index in range(path.size()):
		var tangent=path[min(index+1,path.size()-1)]-path[max(index-1,0)]
		normals.append(tangent.normalized().orthogonal())
	var result=PackedVector2Array()
	for index in range(path.size()):result.append(path[index]+normals[index]*.70)
	var end_axis=(path[-1]-path[-2]).normalized()
	for index in range(1,17):
		var angle=index*PI/16
		result.append(path[-1]+(cos(angle)*normals[-1]+sin(angle)*end_axis)*.70)
	for index in range(path.size()-2,-1,-1):result.append(path[index]-normals[index]*.70)
	var start_axis=(path[1]-path[0]).normalized()
	for index in range(1,16):
		var angle=index*PI/16
		result.append(path[0]+(-cos(angle)*normals[0]-sin(angle)*start_axis)*.70)
	return result

static func beverage_accessories_in_front(rotation:int)->bool:
	# Compare countertop ground depth, not the cup's elevated screen position.
	return Vector2(-.40,.28).rotated(posmod(rotation,4)*PI/2).dot(Vector2.ONE)>0.0

func beverage_accessories():
	# A small stack of clean tumblers stays beside, not in front of, the tap.
	var spare=point(-.32,.15,30)
	for h in [0,3,6]:
		a.rounded_poly([spare+Vector2(-3,-5-h),spare+Vector2(3,-5-h),spare+Vector2(2,-h),spare+Vector2(-2,-h)],1,"e5ecd4")
		a.outlined_ellipse(spare+Vector2(0,-5-h),Vector2(3,1.1),"c4d4b7","f4edd3",.7)

func draw_beverage_foreground(artist:Node2D,p:Vector2,rotation:int):
	kitchen_height=true
	prepare_cache(artist)
	if _can_cache(artist,p):
		if not beverage_accessories_in_front(rotation):_cached_part(artist,"beverage_accessories",p,rotation)
		_cached_part(artist,"beverage_machine",p,rotation)
		if beverage_accessories_in_front(rotation):_cached_part(artist,"beverage_accessories",p,rotation)
		return
	# A rear-side reaching hand is above the cabinet but behind the machine.
	# Keep this same occlusion before and after the cup enters the hand.
	a=artist;origin=p;turn=posmod(rotation,4)
	if not beverage_accessories_in_front(turn):beverage_accessories()
	espresso()
	if beverage_accessories_in_front(turn):beverage_accessories()
static func stove_food_surface(rotation:int)->Vector2:
	return KitchenGeometry.surface(StoveLayout.POT_CENTER,41,rotation)

static func stove_handle_height(rotation:int)->float:
	return PAN_HANDLE_HEIGHT if stove_handle_in_front(rotation) else PAN_HANDLE_HEIGHT-PAN_REAR_HANDLE_DROP

const PAN_GRIP_LENGTH=2.311199861544 # Original projected .10*PAN_WIDTH stem Ã— .32 grip.
static func stove_handle_points(rotation:int)->PackedVector2Array:
	# A radial metal stem connects the repositioned pan to the same reachable
	# front grip. Preserve grip size/material; its end moves inward <1px.
	var outset=0.0 if stove_handle_in_front(rotation) else PAN_REAR_HANDLE_OUTSET
	var height=stove_handle_height(rotation)
	var tip=StoveLayout.HANDLE_GRIP+Vector2(0,outset)
	var axis=(tip-StoveLayout.POT_CENTER).normalized()
	var projected=KitchenGeometry.surface(axis,0,rotation)
	var rim_radius=1.0/sqrt(pow(projected.x/(8.5*PAN_WIDTH),2)+pow(projected.y/(4.2*PAN_DEPTH),2))
	var mount=StoveLayout.POT_CENTER+axis*rim_radius
	return PackedVector2Array([KitchenGeometry.surface(mount,height,rotation),KitchenGeometry.surface(tip,height,rotation)])

static func stove_handle_in_front(rotation:int)->bool:
	return posmod(rotation,4) in [0,3]

func _stove_pan_handle():
	var handle=stove_handle_points(turn)
	var mount=origin+handle[0];var tip=origin+handle[1]
	var grip=tip-(tip-mount).normalized()*PAN_GRIP_LENGTH
	# A short metal collar joins the rim to a rounded, matte wood grip.
	# The highlight follows the same axis; no tiny texture or animated layer.
	edge(mount,grip.lerp(tip,.375),"6d8475",2.2)
	edge(grip,tip,"79674e",2.2)
	for end in [grip,tip]:a.ellipse(end,Vector2.ONE*1.1,"79674e")
	var light=Vector2(-.25,-.35)
	edge(grip+light,tip+light,"b49b73",.65)

func stove_pan():
	var c=point(StoveLayout.POT_CENTER.x,StoveLayout.POT_CENTER.y,34)
	var handle_in_front=stove_handle_in_front(turn)
	# The far-side collar belongs behind the vessel. Do not repaint it over
	# the lip or wood grip after the pan has occluded the attachment.
	if not handle_in_front:_stove_pan_handle()
	# Joined upper/back and lower/front arcs form a continuous tapered vessel,
	# rather than a rounded trapezoid with a separate oval painted on it.
	var body:Array=[]
	for index in range(33):
		var angle=PI+index*PI/32
		body.append(c+Vector2(cos(angle)*8.5*PAN_WIDTH,-7+sin(angle)*4.2*PAN_DEPTH))
	for index in range(33):
		var angle=index*PI/32
		body.append(c+Vector2(cos(angle)*7*PAN_WIDTH,sin(angle)*1.4*PAN_DEPTH))
	a.poly(body,"9eac94")
	a.outlined_ellipse(c+Vector2(0,-7),Vector2(8.5*PAN_WIDTH,4.2*PAN_DEPTH),"607d6b","dce0c9",1.2)
	a.ellipse(c+Vector2(0,-7),Vector2(6.8*PAN_WIDTH,2.8*PAN_DEPTH),"718c77")
	if handle_in_front:_stove_pan_handle()

func draw_stove_food(artist:Node2D,p:Vector2,rotation:int,remaining:float):
	kitchen_height=true;a=artist;origin=p;turn=posmod(rotation,4)
	CookingFood.draw_rest_food(artist,point(StoveLayout.POT_CENTER.x,StoveLayout.POT_CENTER.y,34)+Vector2(0,-7),remaining,-1.0 if turn in [2,3] else 1.0)

func draw_stove_vessel(artist:Node2D,p:Vector2,rotation:int,id=0):
	var motion={"pot":Vector2.ZERO,"lid":Vector2.ZERO}
	if artist.has_method("_stove_vessel_motion"):motion=artist._stove_vessel_motion(id)
	kitchen_height=true;a=artist;turn=posmod(rotation,4);origin=p+motion.pot
	stove_pan()
	# Reuse the vessel's original palette and elliptical rim geometry.
	var lid=point(StoveLayout.POT_CENTER.x,StoveLayout.POT_CENTER.y,34)+Vector2(0,-7.6)+motion.lid-motion.pot
	a.outlined_ellipse(lid,Vector2(8.4*PAN_WIDTH,4.1*PAN_DEPTH),"b5c2a7","dce0c9",1.0)
	a.ellipse(lid+Vector2(0,-.6),Vector2(6.8*PAN_WIDTH,2.8*PAN_DEPTH),"c9d1b7")
	a.line(lid+Vector2(0,-1.0),lid+Vector2(0,-3.0),"6d8475",1.6)
	a.ellipse(lid+Vector2(0,-3.0),Vector2(2.1,1.0),"79674e")
	origin=p

func draw_stove_foreground(artist:Node2D,p:Vector2,rotation:int,id=0):
	draw_stove_vessel(artist,p,rotation,id)

func _sink_faucet():
	# One centered tap serves the full basin; there is no decorative rack.
	var x=KitchenGeometry.SINK_BASIN_CENTER.x
	var back=KitchenGeometry.SINK_TAP_BACK
	top_ellipse(x,back,30.2,.045,.050,"819b88")
	top_ellipse(x,back,30.4,.033,.038,"c2d3bc")
	var pipe=[point(x,back,30),point(x,back,KitchenGeometry.SINK_TAP_CREST_HEIGHT),point(x,KitchenGeometry.SINK_TAP_OUTLET_Z,KitchenGeometry.SINK_TAP_CREST_HEIGHT),point(x,KitchenGeometry.SINK_TAP_OUTLET_Z,KitchenGeometry.SINK_TAP_OUTLET_HEIGHT)]
	for i in range(pipe.size()-1):a._face_line(pipe[i],pipe[i+1],"93ac9c",2.5)
	for joint in pipe:a._face_ellipse(joint,Vector2.ONE*1.25,"93ac9c")

	var light=Vector2(-.38,-.16)
	for i in range(pipe.size()-1):a._face_line(pipe[i]+light,pipe[i+1]+light,"d8e4d1",.65)
	for joint in pipe:a._face_ellipse(joint+light,Vector2.ONE*.325,"d8e4d1")

func _sink_clip(shape:PackedVector2Array,opening:PackedVector2Array,color):
	for polygon in Geometry2D.intersect_polygons(shape,opening):a.poly(Array(polygon),color)

func _sink_outline(radius:Vector2,source_height:float)->PackedVector2Array:
	var result=KitchenGeometry.sink_outline(radius,source_height,turn)
	for index in range(result.size()):result[index]+=origin
	return result

func _sink_cavity():
	var center=KitchenGeometry.SINK_BASIN_CENTER
	var outer=KitchenGeometry.SINK_BASIN_OUTER
	var inner=KitchenGeometry.SINK_BASIN_INNER
	var bottom=KitchenGeometry.SINK_BOTTOM_RADIUS
	var opening=_sink_outline(inner,KitchenGeometry.SINK_OPENING_HEIGHT)
	top_ellipse(center.x,center.y,KitchenGeometry.SINK_RIM_HEIGHT,outer.x,outer.y,"eef0d7")
	a.poly(Array(opening),"537b70")
	# Actual vertical interior walls join the upper opening to a lower floor.
	# Both the floor and wall faces are clipped by the opening: the near wall
	# cannot paint over the countertop just because its floor lies lower.
	for index in range(32):
		var t=index*TAU/32.0;var next=(index+1)*TAU/32.0
		var u=Vector2(cos(t),sin(t));var v=Vector2(cos(next),sin(next))
		var front=(u+v).rotated(turn*PI/2).dot(Vector2.ONE)>0.0
		var color="739a8b" if front else ("5c8275" if (u+v).rotated(turn*PI/2).x>0 else "688f80")
		var wall=PackedVector2Array([point(center.x+u.x*inner.x,center.y+u.y*inner.y,KitchenGeometry.SINK_OPENING_HEIGHT),point(center.x+v.x*inner.x,center.y+v.y*inner.y,KitchenGeometry.SINK_OPENING_HEIGHT),point(center.x+v.x*bottom.x,center.y+v.y*bottom.y,KitchenGeometry.SINK_BOTTOM_HEIGHT),point(center.x+u.x*bottom.x,center.y+u.y*bottom.y,KitchenGeometry.SINK_BOTTOM_HEIGHT)])
		_sink_clip(wall,opening,color)
	_sink_clip(_sink_outline(bottom,KitchenGeometry.SINK_BOTTOM_HEIGHT),opening,"91b0a0")
	# A small recessed drain belongs to the lower surface, not the rim plane.
	var drain=PackedVector2Array()
	for index in range(32):
		var angle=index*TAU/32.0
		drain.append(point(center.x+cos(angle)*.035,center.y+sin(angle)*.032,KitchenGeometry.SINK_BOTTOM_HEIGHT+.18))
	_sink_clip(drain,opening,"547c70")

func draw_sink_foreground(artist:Node2D,p:Vector2,rotation:int):
	kitchen_height=true;a=artist;origin=p;turn=posmod(rotation,4)
	var center=KitchenGeometry.SINK_BASIN_CENTER
	var outer=KitchenGeometry.SINK_BASIN_OUTER
	var inner=KitchenGeometry.SINK_BASIN_INNER
	# A continuous near lip occludes submerged dish edges. Clipping in the
	# payload painter preserves the original rounded countertop silhouette.
	var right=Vector2.RIGHT.rotated(turn*PI/2).dot(Vector2.ONE)*outer.x
	var down=Vector2.DOWN.rotated(turn*PI/2).dot(Vector2.ONE)*outer.y
	var start=atan2(down,right)-PI/2
	var rim_points=[];var inner_points=[]
	for index in range(33):
		var angle=start+index*PI/32.0;var ray=Vector2(cos(angle),sin(angle))
		var q=center+ray*outer;var inner_q=center+ray*inner
		rim_points.append(point(q.x,q.y,KitchenGeometry.SINK_RIM_HEIGHT))
		inner_points.append(point(inner_q.x,inner_q.y,KitchenGeometry.SINK_OPENING_HEIGHT))
	inner_points.reverse()
	a.poly(rim_points+inner_points,"f4f1da")
	# The rear-mounted stem changes depth with rotation. Its spout now clears
	# the entire six-dish stack in projection, without an always-front trick.
	if KitchenGeometry.sink_tap_in_front(turn):_sink_faucet()

func _draw_item_legacy(artist: Node2D,kind: String,p: Vector2,rotation: int,_id=0):
	checkout_height=false
	kitchen_height=kind in ["counter","stove","beverage","sink"]
	a=artist;origin=p;turn=posmod(rotation,4)
	match kind:
		"counter":cabinet()
		"stove":
			_stove_base()
			if a.has_method("_stove_heat"):a._stove_heat(_id,turn)
			# The front-center output lip is behind the pan only in rear views.
			# Match sub-object depth, rather than painting every dish last.
			if turn in [1,2] and a.has_method("_station_payloads"):a._station_payloads(_id,"stove",turn)
			draw_stove_vessel(artist,p,turn,_id)
			if turn in [0,3] and a.has_method("_station_payloads"):a._station_payloads(_id,"stove",turn)
			_stove_controls()
		"beverage":
			_beverage_base()
			if not beverage_accessories_in_front(turn):beverage_accessories()
			if not front_visible() and a.has_method("_station_payloads"):a._station_payloads(_id,"beverage",turn)
			espresso()
			if front_visible() and a.has_method("_station_payloads"):a._station_payloads(_id,"beverage",turn)
			if beverage_accessories_in_front(turn):beverage_accessories()
		"sink":
			cabinet(CABINET_TILE_SPAN,CABINET_TILE_SPAN,29,"bac4aa","99ad98","cbd7be")
			# Recessed floor, side walls and front lip, all on the same sink.
			_sink_cavity()
			_sink_faucet()
		"bookshelf":
			box(0,0,.72,.46,0,61,"c7a574","ae8955","ba945e","b08b58")
			if front_visible():
				var z=.238
				for row in range(2):
					var h=7+row*25
					face([point(-.29,z,h),point(.29,z,h),point(.29,z,h+20),point(-.29,z,h+20)],"81754e",1)
					for i in range(5):
						var x=-.24+i*.10
						var hi=h+15+(i%3)*2
						face([point(x,z+.01,h+1),point(x+.065,z+.01,h+1),point(x+.065,z+.01,hi),point(x,z+.01,hi)],["dedcbb","9daa7d","d3b57e","b5c5a4","ddc59a"][i],.6)
						edge(point(x+.032,z+.017,h+4),point(x+.032,z+.017,h+6),"eee2bf",.7)
					edge(point(-.32,z+.02,h-1),point(.32,z+.02,h-1),"d1b47e",2)
			var q=point(0,-.05,61)
			a.rounded_poly([q+Vector2(-4,-8),q+Vector2(4,-8),q+Vector2(3,0),q+Vector2(-3,0)],1,"b68e5d")
			a.ellipse(q+Vector2(0,-10),Vector2(7,4),"91a66b")
		"bench":
			if turn in [1,2]:draw_bench_part(a,origin,turn,true)
			draw_bench_part(a,origin,turn,false)
			if turn in [0,3]:draw_bench_part(a,origin,turn,true)
		"divider":
			for x in [-.35,.35]:box(x,0,.12,.30,0,3,"b7a978","a5986a","a99d72")
			box(0,0,.91,.12,3,57,"e5dbb6","aabb93","9cac87","a3b48c")
			if front_visible():
				for x in [-.26,0,.26]:edge(point(x,.065,9),point(x,.065,50),"c2caa3",1)
		"rug":
			face([point(-.43,-.34),point(.43,-.34),point(.43,.34),point(-.43,.34)],"cca976",1)
			for x in range(-3,4):edge(point(x*.11,-.28),point(x*.11,.28),"ebd6a4",1.7)
			for z in range(-2,3):edge(point(-.38,z*.11),point(.38,z*.11),"ebd6a4",1.7)
		_:return false
	return true

func draw_bench_part(artist:Node2D,p:Vector2,rotation:int,back_only:bool):
	prepare_cache(artist)
	if _can_cache(artist,p):
		_cached_part(artist,"bench_back" if back_only else "bench_seat",p,rotation)
		return
	_draw_bench_part_legacy(artist,p,rotation,back_only)

func _draw_bench_part_legacy(artist:Node2D,p:Vector2,rotation:int,back_only:bool):
	kitchen_height=false
	a=artist;origin=p;turn=posmod(rotation,4)
	if back_only:
		box(0,.25,.87,.075,19,35,"cbd0a7","b6c39a","9aac84")
		edge(point(-.39,.297,31),point(.39,.297,31),"cdd4ae",1)
	else:
		for x in [-.34,.34]:
			for z in [-.20,.20]:edge(point(x,z,0),point(x,z,16),"9c8152",3)
		box(0,0,.87,.55,13,19,"c6c99e","a7b588","9aaa7d")

func _paint_retained_part(artist:Node2D,part:String,rotation:int,cached:bool):
	_paint_retained_part_at(artist,part,Vector2.ZERO,rotation,cached)

func _paint_retained_part_at(artist:Node2D,part:String,p:Vector2,rotation:int,cached:bool):
	if cached:_cached_part(artist,part,p,rotation)
	else:draw_static_part(artist,part,p,rotation)
