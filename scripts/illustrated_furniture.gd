extends RefCounted
const KitchenGeometry=preload("res://scripts/kitchen_worktop_geometry.gd")
var kitchen_height := false
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
# Matched control: keep the established station/decor cache but bypass new items.
var expanded_parts_enabled := true

func prepare_cache(artist: Node2D):
	if cache_enabled: static_atlas.request(artist)

func _can_cache(artist: Node2D) -> bool:
	# A single faded composite is not equal to individually faded overlapping
	# primitives. Keep the original .63-opacity drag preview exactly intact.
	return cache_enabled and static_atlas.is_ready() and (not "opacity" in artist or is_equal_approx(float(artist.opacity),1.0))

func _cached_part(artist: Node2D,part: String,p: Vector2,rotation: int):
	static_atlas.draw_part(artist,part,p,posmod(rotation,4))

# Guards in the real artist's table body/chair/plant/lamp helpers use this.
# The bake artist has cache_enabled=false and executes their original geometry.
# Table vase offsets and all service payloads are deliberately absent.
func try_draw_static(artist: Node2D,part: String,p: Vector2,rotation=0) -> bool:
	if not expanded_parts_enabled or not part in StaticAtlas.PARTS:return false
	prepare_cache(artist)
	if not _can_cache(artist):return false
	_cached_part(artist,part,p,rotation)
	return true

# Native tests can inspect this exact sequence without baking or a live model.
static func part_sequence(kind: String,rotation: int) -> Array:
	var r := posmod(rotation,4)
	match kind:
		"stove": return ["stove_base","payload","stove_pan","stove_controls"] if r in [0,1] else ["stove_base","stove_pan","payload","stove_controls"]
		"beverage": return ["beverage_base","beverage_machine","payload","beverage_accessories"] if r in [0,3] else ["beverage_base","payload","beverage_machine","beverage_accessories"]
		"bench": return ["bench_back","bench_seat"] if r in [1,2] else ["bench_seat","bench_back"]
		"counter","sink","bookshelf","divider","rug": return [kind]
		_: return []

func draw_item(artist: Node2D,kind: String,p: Vector2,rotation: int,id=0):
	if kind=="register":
		kitchen_height=false
		return CheckoutArt.draw_register(self,artist,p,rotation,id)
	var sequence := part_sequence(kind,rotation)
	if sequence.is_empty(): return false
	prepare_cache(artist)
	if not _can_cache(artist): return _draw_item_legacy(artist,kind,p,rotation,id)
	a=artist;origin=p;turn=posmod(rotation,4)
	for part in sequence:
		if part=="payload":
			if artist.has_method("_station_payloads"): artist._station_payloads(id,kind,turn)
		else:
			_cached_part(artist,part,p,turn)
			if part=="stove_pan" and artist.has_method("_stove_food"):artist._stove_food(id,turn)
	return true

# Every atlas cell is rendered from these original procedural helpers. Keep
# quarter-turn geometry, static subparts and live payload slots independent.
func draw_static_part(artist: Node2D,part: String,p: Vector2,rotation: int):
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
	box(0,0,.88,.78,1,29,"b7c4af","849e8c","708d7d","839a84")
	box(0,0,.91,.81,29,31,"d9deca","adbca9","a2b3a0")
	for burner in [Vector2.ZERO]:
		top_ellipse(burner.x,burner.y,31.2,.155,.155,"536e61")
		top_ellipse(burner.x,burner.y,31.4,.11,.11,"8f9f88")
		top_ellipse(burner.x,burner.y,31.6,.063,.063,"5b7665")
		for d in [Vector2.RIGHT,Vector2.DOWN]:
			edge(point(burner.x-d.x*.18,burner.y-d.y*.18,31.8),point(burner.x+d.x*.18,burner.y+d.y*.18,31.8),"556e60",1.15)

func _stove_controls():
	if front_visible():
		var z=.404
		face([point(-.34,z,5),point(.34,z,5),point(.34,z,21),point(-.34,z,21)],"607f6d",2)
		face([point(-.27,z+.005,8),point(.27,z+.005,8),point(.27,z+.005,18),point(-.27,z+.005,18)],"405d52",1)
		edge(point(-.21,z+.01,15),point(.15,z+.01,17),"819386",.8)
		edge(point(-.26,z+.02,21.5),point(.26,z+.02,21.5),"d6ddc7",2.2)
		for x in [-.25,-.08,.09,.26]:
			a.ellipse(point(x,z,26),Vector2(1.8,1.8),"f0e5c7")
			# A one-pixel indicator is smaller than the generic AA feather. Draw
			# its real capsule silhouette so HD/4x atlas views cannot turn it
			# into a pinched square. Keep center, color and knob bounds intact.
			var marker=point(x,z,26)
			a._face_line(marker,marker+Vector2(0,-1),"73806a",.7)
			for tip in [marker,marker+Vector2(0,-1)]:
				a._face_ellipse(tip,Vector2.ONE*.35,"73806a")

func _beverage_base():
	cabinet(.90,.78,29,"b7bd9d","9fab8f","e9dfc0")
	# Drip tray has the same rotated front as the cup's actual preparation slot.
	box(.17,.26,.27,.22,29,30,"aebba6","8c9f8d","91a18e")
	for x in [.09,.15,.21,.27]:edge(point(x,.17,30.4),point(x,.34,30.4),"7e9380",.7)

func point(x: float,z: float,h: float=0.0) -> Vector2:
	var q=Vector2(x,z).rotated(turn*PI/2.0)
	var height=KitchenGeometry.height(h) if kitchen_height else h
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
func cabinet(w=.85,d=.75,h=29.0,paint="c3a168",side="b49461",top="e6cca0"):
	box(0,0,w,d,1,h,top,paint,side,paint)
	if not front_visible():return
	var z=d/2+.006
	for part in [-1,1]:
		var l=(-w/2+.07) if part<0 else .018
		var r=-.018 if part<0 else (w/2-.07)
		face([point(l,z,5),point(r,z,5),point(r,z,h-5),point(l,z,h-5)],"bc9a63",1)
		edge(point(l+.025,z,h-5),point(r-.025,z,h-5),"d4b782",.75)
		edge(point((r-.055) if part<0 else (l+.055),z,16),point((r-.055) if part<0 else (l+.055),z,20),"8f7950",1.6)
func cup(x: float,z: float,h: float):
	var c=point(x,z,h)
	a.rounded_poly([c+Vector2(-3.5,-6),c+Vector2(3.5,-6),c+Vector2(2.5,0),c+Vector2(-2.5,0)],1,"fff1d2")
	a.outlined_ellipse(c+Vector2(0,-6),Vector2(3.5,1.6),"b08c60","eee2bb",.6)
	a.draw_arc(c+Vector2(3,-3.5),2.5,-PI/2,PI/2,10,a.col("eee2bb"),1.2,true)
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
		edge(point(.17,.06,43),point(.17,.20,43),"5e7d69",2.4)
		edge(point(.17,.20,43),point(.17,.20,40),"5e7d69",2.4)
		edge(point(.17,.08,43),point(.17,.08,47),"466b57",1.7)
		a.ellipse(point(.17,.08,47),Vector2(2.3,1.5),"527862")
func beverage_accessories():
	# A small stack of clean tumblers stays beside, not in front of, the tap.
	var spare=point(-.32,.15,30)
	for h in [0,3,6]:
		a.rounded_poly([spare+Vector2(-3,-5-h),spare+Vector2(3,-5-h),spare+Vector2(2,-h),spare+Vector2(-2,-h)],1,"e5ecd4")
		a.outlined_ellipse(spare+Vector2(0,-5-h),Vector2(3,1.1),"c4d4b7","f4edd3",.7)

func draw_beverage_foreground(artist:Node2D,p:Vector2,rotation:int):
	kitchen_height=true
	prepare_cache(artist)
	if _can_cache(artist):
		_cached_part(artist,"beverage_machine",p,rotation)
		_cached_part(artist,"beverage_accessories",p,rotation)
		return
	# A rear-side reaching hand is above the cabinet but behind the machine.
	# Keep this same occlusion before and after the cup enters the hand.
	a=artist;origin=p;turn=posmod(rotation,4)
	espresso()
	beverage_accessories()
static func stove_food_surface(rotation:int)->Vector2:
	return KitchenGeometry.surface(Vector2.ZERO,39,rotation)

func stove_pan():
	var c=point(0,0,32)
	edge(point(0,-.17,36),point(0,-.32,36),"536e5f",2.2)
	edge(point(0,.15,36),point(0,.31,36),"536e5f",2.2)
	a.rounded_poly([c+Vector2(-8,-7),c+Vector2(8,-7),c+Vector2(7,0),c+Vector2(-6,0)],2,"9eac94")
	a.ellipse(c+Vector2(0,-.5),Vector2(7,3.5),"8ea08b")
	a.outlined_ellipse(c+Vector2(0,-7),Vector2(8.5,4.2),"607d6b","dce0c9",1.2)
	a.ellipse(c+Vector2(0,-7),Vector2(6.8,2.8),"718c77")

func draw_stove_food(artist:Node2D,p:Vector2,rotation:int,remaining:float):
	kitchen_height=true
	# Live food is excluded from static atlas cells, including shop icons.
	a=artist;origin=p;turn=posmod(rotation,4)
	var c=point(0,0,32)
	a.ellipse(c+Vector2(0,-7),Vector2(6.8,2.8)*remaining,"d9a962")
	for q in [Vector2(-3,-7),Vector2(2,-8),Vector2(3,-6)]:a.ellipse(c+Vector2(0,-7)+(q-Vector2(0,-7))*remaining,Vector2(1.6,.8)*remaining,"829760")

func draw_stove_foreground(artist:Node2D,p:Vector2,rotation:int,id=0):
	kitchen_height=true
	prepare_cache(artist)
	if _can_cache(artist):
		_cached_part(artist,"stove_pan",p,rotation)
	else:
		a=artist;origin=p;turn=posmod(rotation,4)
		stove_pan()
	if artist.has_method("_stove_food"):artist._stove_food(id,rotation)

func _sink_faucet():
	# The same planted stem and basin-directed outlet, with a readable matte
	# metal body. Joined round caps cannot become detached antialias blocks.
	top_ellipse(-.18,-.31,30.2,.045,.055,"819b88")
	top_ellipse(-.18,-.31,30.4,.033,.040,"c2d3bc")
	var pipe=[point(-.18,-.31,30),point(-.18,-.31,47),point(-.18,-.02,47),point(-.18,-.02,43)]
	for i in range(pipe.size()-1):a._face_line(pipe[i],pipe[i+1],"93ac9c",2.5)
	for joint in pipe:a._face_ellipse(joint,Vector2.ONE*1.25,"93ac9c")
	# A real faucet control, joined to the stem above the collar. This
	# replaces the old unexplained ivory dot elsewhere on the worktop.
	var valve_hub=point(-.18,-.31,32.4)
	var valve_tip=point(-.30,-.31,33.1)
	a._face_line(valve_hub,valve_tip,"799783",1.2)
	for tip in [valve_hub,valve_tip]:a._face_ellipse(tip,Vector2.ONE*.60,"799783")
	a._face_ellipse(valve_hub,Vector2.ONE*.82,"799783")
	# Shared screen-left light direction, thin enough to retain the metal body.
	var light=Vector2(-.38,-.16)
	for i in range(pipe.size()-1):a._face_line(pipe[i]+light,pipe[i+1]+light,"d8e4d1",.65)
	for joint in pipe:a._face_ellipse(joint+light,Vector2.ONE*.325,"d8e4d1")

func _draw_item_legacy(artist: Node2D,kind: String,p: Vector2,rotation: int,_id=0):
	kitchen_height=kind in ["counter","stove","beverage","sink"]
	a=artist;origin=p;turn=posmod(rotation,4)
	match kind:
		"counter":cabinet()
		"stove":
			_stove_base()
			# Local plate (-.20,.30) is behind the raised pan in these views.
			# Match sub-object depth, rather than painting every dish last.
			if turn in [0,1] and a.has_method("_station_payloads"):a._station_payloads(_id,"stove",turn)
			stove_pan()
			if a.has_method("_stove_food"):a._stove_food(_id,turn)
			if turn in [2,3] and a.has_method("_station_payloads"):a._station_payloads(_id,"stove",turn)
			_stove_controls()
		"beverage":
			_beverage_base()
			if not front_visible() and a.has_method("_station_payloads"):a._station_payloads(_id,"beverage",turn)
			espresso()
			if front_visible() and a.has_method("_station_payloads"):a._station_payloads(_id,"beverage",turn)
			beverage_accessories()
		"sink":
			cabinet(.94,.82,29,"bac4aa","99ad98","cbd7be")
			# Inset basin, separate ribbed draining rack and a planted gooseneck tap.
			top_ellipse(-.12,.035,30,.25,.28,"eef0d7")
			top_ellipse(-.12,.035,30.5,.205,.23,"6d9689")
			top_ellipse(-.12,.075,30.7,.16,.17,"92b6a8")
			top_ellipse(-.12,.10,30.9,.038,.035,"739187")
			box(.30,.01,.22,.54,29.5,31,"b6c7af","8ea58f","9baf97")
			for z in [-.19,-.10,0,.10,.20]:edge(point(.22,z,31.2),point(.39,z,31.2),"819b88",.9)
			for z in [-.10,.05]:
				var dish=point(.30,z,32)
				a.outlined_ellipse(dish+Vector2(0,-5),Vector2(2.6,5.5),"f7ecd1","cfceb0",.8)
			_sink_faucet()
			box(.29,-.31,.10,.10,30,37,"c9dab9","b1cba7","a4be9c")
			edge(point(.29,-.31,38),point(.29,-.24,38),"739783",1.2)
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
	if _can_cache(artist):
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
