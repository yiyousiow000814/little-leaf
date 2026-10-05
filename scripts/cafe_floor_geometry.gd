extends RefCounted
## Continuous, saved mess geometry. Routing cells never define its silhouette.
const VERSION=1
const BODY_CLEARANCE=.27
const MAX_REACH=1.15
const NO_CELL=Vector2i(-1,-1)
const DIRECTIONS=[Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]
const FloorApproach=preload("res://scripts/floor_cleaning_approach.gd")
var game
var layout_revision=-1
var layout_cache={}
var work_cell_cache={}

func _init(owner=null):game=owner

static func _fraction(seed:int,salt:int)->float:
	return float(posmod(seed*7919+salt*104729,65521))/65521.0

static func _created_precision(value:float)->float:
	# Creation only: these binary-exact increments survive JSON's decimal
	# parser without a one-ULP scalar drift. Build and paint from this value;
	# never quantize an existing shape, legacy target or loaded vertex.
	return roundf(value*1024.0)/1024.0

static func piece_points(piece:Dictionary)->Array:
	var template=[]
	match str(piece.kind):
		"banana":template=[Vector2(-.04,-.22),Vector2(.04,-.2),Vector2(.08,-.03),Vector2(.30,.07),Vector2(.19,.15),Vector2(0,.04),Vector2(-.22,.18),Vector2(-.29,.08),Vector2(-.07,-.02)]
		"paper":template=[Vector2(-.22,-.14),Vector2(.09,-.20),Vector2(.24,-.05),Vector2(.16,.18),Vector2(-.18,.14),Vector2(-.13,.01)]
		"bag":template=[Vector2(-.18,-.17),Vector2(.12,-.20),Vector2(.21,-.07),Vector2(.23,.18),Vector2(-.20,.19),Vector2(-.24,-.04)]
		_:template=[Vector2(-.055,-.02),Vector2(-.02,-.055),Vector2(.06,-.015),Vector2(.045,.04),Vector2(-.035,.035)]
	var result=[]
	for point in template:result.append(piece.center+(point*float(piece.size)).rotated(float(piece.angle)))
	return result

static func piece_bounds(piece:Dictionary)->Array:
	var result=piece_points(piece)
	if str(piece.kind)=="bag":
		for point in [Vector2(-.075,-.26),Vector2(.065,-.26)]:result.append(piece.center+(point*float(piece.size)).rotated(float(piece.angle)))
	return result

static func _hull(points:Array)->Array:
	if points.size()<3:return points.duplicate()
	var result=Array(Geometry2D.convex_hull(PackedVector2Array(points)))
	if result.size()>1 and result[0].is_equal_approx(result[-1]):result.pop_back()
	return result

static func _build(entry:Dictionary,seed:int,scale:float,natural_scatter:bool=false)->Dictionary:
	var center:Vector2=entry.floor_target
	var spill=[];var pieces=[];var occupied=[]
	var angle=_fraction(seed,1)*TAU
	if bool(entry.get("floor_spill",false)):
		var anchor:Vector2=entry.spill_target
		for index in range(14):
			var theta=TAU*index/14.0
			var radius=.78+_fraction(seed,index+2)*.22
			var point=anchor+Vector2(cos(theta)*.73,sin(theta)*.43).rotated(angle)*radius*scale
			spill.append(point);occupied.append(point)
	var kind=str(entry.get("floor_debris","none"))
	if kind!="none":
		var anchor:Vector2=entry.debris_target
		var types=["banana"] if kind=="banana" else [["paper","crumbs","crumbs"],["bag","paper","crumbs"],["paper","bag"]][posmod(int(seed/11),3)]
		if natural_scatter and kind!="banana":types=[["paper"],["bag"],["paper"]][posmod(int(seed/7),3)]
		for index in range(types.size()):
			var spread=Vector2.ZERO if types.size()==1 else Vector2((index-(types.size()-1)*.5)*.43,(_fraction(seed,index+30)-.5)*.24).rotated(angle)*scale
			# New dry litter uses a loose cluster rather than equally spaced pieces.
			# Legacy generation and every loaded shape remain untouched.
			if natural_scatter and types.size()>1:
				var scatter=Vector2(_fraction(seed,index*3+83)-.5,_fraction(seed,index*5+109)-.5)
				spread=scatter.rotated(angle)*.54*scale
			var piece={"kind":types[index],"center":anchor+spread,"angle":_created_precision(_fraction(seed,index+40)*TAU),"size":_created_precision(scale*(.86+_fraction(seed,index+50)*.25))}
			# Orient new peel curls and the bag opening across the view so their
			# identity reads; loaded angles and legacy shapes stay authoritative.
			if natural_scatter and types[index] in ["banana","bag"]:
				piece.angle=_created_precision(PI*1.75+(_fraction(seed,142)-.5)*.50)
			pieces.append(piece);occupied.append_array(piece_bounds(piece))
	return {"version":VERSION,"seed":seed,"center":center,"outline":spill.duplicate() if pieces.is_empty() else _hull(occupied),"spill_outline":spill,"pieces":pieces}

static func canonicalize_metadata(entry:Dictionary):
	# JSON numbers decode as floats. Restore only validated integral metadata;
	# saved vertices, centers, angles and sizes remain exactly untouched.
	if not entry.has("mess_shape") or not entry.mess_shape is Dictionary:return
	var shape:Dictionary=entry.mess_shape
	var version=shape.get("version");var seed=shape.get("seed")
	if not (version is int or version is float) or version!=VERSION:return
	if not (seed is int or seed is float) or not is_finite(float(seed)) or float(seed)<0 or float(seed)>1000000000 or floor(float(seed))!=float(seed):return
	shape.version=int(version);shape.seed=int(seed)

func ensure(entry:Dictionary)->Dictionary:
	if entry.has("mess_shape"):
		canonicalize_metadata(entry)
		return entry.mess_shape
	# Existing targets are authoritative during migration. Never teleport a
	# stain, alter held trash, or restart the elapsed action to make room.
	var seed=posmod(int(entry.get("id",entry.get("token",1)))*47+int(entry.get("source_guest_id",0))*13,1000000000)
	for scale in [1.0,.82,.66,.5,.34]:
		var candidate=_build(entry,seed,scale)
		if layout_clear(candidate):entry.mess_shape=candidate;return candidate
	entry.mess_shape=_build(entry,seed,.34)
	return entry.mess_shape

func generate(entry:Dictionary,seed:int,size_scale:float=1.0,natural_scatter:bool=false)->bool:
	var original=Vector2(entry.floor_cell)+Vector2(.5,.5)
	for attempt in range(8):
		var center=original+Vector2(_fraction(seed,attempt*2+70)-.5,_fraction(seed,attempt*2+71)-.5)*(.24 if natural_scatter else .64)
		entry.floor_target=center;entry.debris_target=center;entry.spill_target=center
		var candidate=_build(entry,seed,size_scale*(1.0 if attempt<4 else .72),natural_scatter)
		if natural_scatter:
			var contained=true
			for point in candidate.outline:
				if Vector2i(floori(point.x),floori(point.y))!=entry.floor_cell:contained=false;break
			if not contained:continue
		if not layout_clear(candidate):continue
		entry.mess_shape=candidate
		if not work_cells(entry).is_empty():return true
	return false

func _point_clear(point:Vector2)->bool:
	# Small padding accounts for the painted outline, including at wall ends.
	for offset in [Vector2.ZERO,Vector2(.035,0),Vector2(-.035,0),Vector2(0,.035),Vector2(0,-.035)]:
		var sample=point+offset;var cell=Vector2i(floori(sample.x),floori(sample.y))
		if not game._staff_walkable(cell):return false
		if game.model.segment_blocked(point,sample):return false
	return true

func layout_clear(shape:Dictionary)->bool:
	if layout_revision!=int(game.model.revision):layout_revision=int(game.model.revision);layout_cache.clear();work_cell_cache.clear()
	if layout_cache.size()>256:layout_cache.clear();work_cell_cache.clear()
	var key=hash(shape)
	if layout_cache.has(key):return bool(layout_cache[key])
	var outline:Array=shape.outline
	if outline.size()<3:layout_cache[key]=false;return false
	var valid=true
	for index in range(outline.size()):
		var a:Vector2=outline[index];var b:Vector2=outline[(index+1)%outline.size()]
		if game.model.segment_blocked(a,b) or game.model.segment_blocked(shape.center,a):valid=false;break
		var count=maxi(1,ceili(a.distance_to(b)/.07))
		for step in range(count+1):
			if not _point_clear(a.lerp(b,step/float(count))):valid=false;break
		if not valid:break
	# Sample the interior too: a large polygon may surround a narrow obstacle.
	if valid:
		var low:Vector2=outline[0];var high=low
		for point in outline:low=low.min(point);high=high.max(point)
		for ix in range(ceili((high.x-low.x)/.12)+1):
			for iz in range(ceili((high.y-low.y)/.12)+1):
				var point=low+Vector2(ix,iz)*.12
				if Geometry2D.is_point_in_polygon(point,PackedVector2Array(outline)) and not _point_clear(point):valid=false;break
			if not valid:break
	layout_cache[key]=valid
	return valid

static func nearest_boundary(point:Vector2,outline:Array)->Vector2:
	var result=outline[0];var shortest=INF
	for index in range(outline.size()):
		var candidate=Geometry2D.get_closest_point_to_segment(point,outline[index],outline[(index+1)%outline.size()])
		var distance=point.distance_squared_to(candidate)
		if distance<shortest:result=candidate;shortest=distance
	return result

static func outside(point:Vector2,outline:Array,clearance=BODY_CLEARANCE)->bool:
	return outline.size()>=3 and not Geometry2D.is_point_in_polygon(point,PackedVector2Array(outline)) and point.distance_to(nearest_boundary(point,outline))>=clearance

func work_cells(entry:Dictionary)->Array:
	var shape=ensure(entry);var result=[]
	if not layout_clear(shape):return result
	var action="sweeping" if str(entry.get("trash_owner","none"))=="floor" and str(entry.get("floor_debris","none")) in ["banana","crumbs"] else "mopping"
	var cache_key=hash([shape,action])
	if work_cell_cache.has(cache_key):return work_cell_cache[cache_key]
	var anchor:Vector2=shape.center;var base=Vector2i(floori(anchor.x),floori(anchor.y))
	for dz in range(-2,3):
		for dx in range(-2,3):
			var cell=base+Vector2i(dx,dz);var center=Vector2(cell)+Vector2(.5,.5)
			if cell==entry.floor_cell or not game._staff_walkable(cell) or not outside(center,shape.outline):continue
			var contact=nearest_boundary(center,shape.outline)
			if center.distance_to(contact)>MAX_REACH or game.model.segment_blocked(center,contact):continue
			# The tool cannot reach through a furnishing even when its endpoint
			# and the actor are both on otherwise accessible floor.
			var clear=true;var samples=maxi(1,ceili(center.distance_to(contact)/.1))
			for step in range(samples+1):
				if not _point_clear(center.lerp(contact,step/float(samples))):clear=false;break
			if not clear:continue
			# A reachable tool endpoint is not enough: the cleaner must also
			# fit the bounded physical approach. The existing destination/claim
			# policy chooses another side or leaves the unchanged mess pending.
			var actual_contact=_contact_from(entry,shape,center,action)
			if FloorApproach.solve(center,actual_contact,game.model).obstruction!="":continue
			result.append(cell)
	work_cell_cache[cache_key]=result
	return result

func available(cell:Vector2i,staff:Dictionary,claimed:Array)->bool:
	# Passing people do not interrupt cleanup. Only standing work ownership
	# reserves a face; actual mess/furniture/wall geometry stays authoritative.
	if claimed.has(cell) or game.model.checkout_claims().has(cell):return false
	var point=Vector2(cell)+Vector2(.5,.5)
	for other in game.staff_states:
		if is_same(other,staff):continue
		if other.job_kind!="" and (other.destination==cell or other.get("table_face_cell",NO_CELL)==cell):return false
	if game.floor_tasks!=null:
		for other_mess in game.floor_tasks.messes.values():
			if other_mess.has("mess_shape") and not outside(point,other_mess.mess_shape.outline):return false
	if "service_guests" in game:
		for other_mess in game.service_guests.values():
			if bool(other_mess.get("floor_dirty",false)) and not bool(other_mess.get("floor_cleaned",false)) and other_mess.has("mess_shape") and not outside(point,other_mess.mess_shape.outline):return false
	return true

func destination(entry:Dictionary,staff:Dictionary,from:Vector2i,claimed:Array)->Vector2i:
	var cells=work_cells(entry)
	var pinned:Vector2i=entry.get("floor_work_cell",NO_CELL)
	if cells.has(pinned) and available(pinned,staff,claimed) and (from==pinned or not game._static_service_path(from,pinned).is_empty()):return pinned
	var best=NO_CELL;var shortest=1000000
	for cell in cells:
		if not available(cell,staff,claimed):continue
		var route=game._static_service_path(from,cell)
		if route.is_empty() and from!=cell:continue
		if route.size()<shortest:best=cell;shortest=route.size()
	# Keep the original pin during a competing work reservation, so a waiting
	# cleaner returns to the same side. No target or stage is moved.
	if best!=NO_CELL:entry.floor_work_cell=best
	return best

func contact_target(entry:Dictionary,staff:Dictionary,action:String)->Vector2:
	var shape=ensure(entry)
	var cell:Vector2i=entry.get("floor_work_cell",NO_CELL)
	var from=Vector2(cell)+Vector2(.5,.5) if cell!=NO_CELL else Vector2(staff.pos)
	return _contact_from(entry,shape,from,action)

static func _contact_from(entry:Dictionary,shape:Dictionary,from:Vector2,action:String)->Vector2:
	var outline:Array=shape.spill_outline if action=="mopping" else shape.outline
	if outline.is_empty():return entry.spill_target if action=="mopping" else entry.debris_target
	# A fixed near-edge point keeps the cleaner's facing stable while the
	# painted spill shrinks. The animation moves only the tool around it.
	var edge=nearest_boundary(from,outline)
	return edge.move_toward(shape.center,.055)

static func validate(entry:Dictionary,codec)->String:
	if entry.has("floor_work_cell") and not codec._cell(entry.floor_work_cell):return "Invalid floor work cell"
	if not entry.has("mess_shape"):return ""
	var shape=entry.mess_shape
	if not shape is Dictionary or shape.get("version")!=VERSION or not codec._integer(shape.get("seed"),0,1000000000) or not codec._point(shape.get("center")):return "Invalid floor shape identity"
	if shape.center.distance_to(entry.floor_target)>.0001:return "Floor shape anchor differs from its saved target"
	for key in ["outline","spill_outline"]:
		if not shape.get(key) is Array or shape[key].size()>24 or (key=="outline" and shape[key].size()<3) or (key=="spill_outline" and shape[key].size() not in [0,14]):return "Invalid floor shape outline"
		for point in shape[key]:
			if not codec._point(point) or point.distance_to(shape.center)>1.05:return "Floor shape exceeds its footprint"
	if not shape.get("pieces") is Array or shape.pieces.size()>6:return "Invalid floor litter pieces"
	for piece in shape.pieces:
		if not piece is Dictionary or piece.get("kind") not in ["banana","paper","bag","crumbs"] or not codec._point(piece.get("center")) or piece.center.distance_to(shape.center)>.75 or not codec._number(piece.get("angle"),0,TAU) or not codec._number(piece.get("size"),.05,1.2):return "Invalid floor litter shape"
		for point in piece_bounds(piece):
			if point.distance_to(shape.center)>1.05:return "Floor litter exceeds its footprint"
	var occupied=shape.spill_outline.duplicate()
	for piece in shape.pieces:occupied.append_array(piece_bounds(piece))
	var expected=shape.spill_outline if shape.pieces.is_empty() else _hull(occupied)
	if shape.outline!=expected:return "Floor outline does not match its visible mess"
	if Geometry2D.triangulate_polygon(PackedVector2Array(shape.outline)).is_empty():return "Floor outline is not a valid polygon"
	canonicalize_metadata(entry)
	return ""
