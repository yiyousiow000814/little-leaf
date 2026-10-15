extends RefCounted
## Strict scalar codec for the isolated unified-building candidate. Import only
## consumes the existing reader's validated legacy snapshot without editing it,
## granting value or creating missing edges. The separate backup helper preserves
## exact original bytes before a native migration save may replace its target.
const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
const Openings=preload("res://scripts/gameplay/cafe_wall_openings.gd")
const LegacyEdges=preload("res://scripts/gameplay/cafe_building_edges.gd")
const Runtime=preload("res://scripts/persistence/cafe_runtime_codec.gd")
const Contract=preload("res://scripts/persistence/cafe_save_contract.gd")
const Footprint=preload("res://scripts/gameplay/cafe_footprint.gd")
const FORMAT="little_leaf.grid_building.v2"
const WALL_FORMAT=4
const PREVIOUS_FORMAT="little_leaf.grid_building.v1"
const PREVIOUS_WALL_FORMAT=3
const ATTACHMENT_FORMAT=2
# Existing aggregate allocations include an odd credit and the historical
# nine-unit payment divided over eight active edges. New purchases still use
# the ordinary exact catalog price and floor(paid/2), never these import sums.
const RECEIPTS={"half":[[0,0],[35,17],[35,18],[39,19],[39,20],[40,20]],
	"full":[[0,0],[55,27],[55,28],[61,30],[61,31],[62,31]]}

static func identity_sequence(value)->int:
	if not value is String:return -1
	if value.begins_with("wall:"):
		var suffix=value.trim_prefix("wall:")
		if not suffix.is_valid_int():return -1
		var id=int(suffix)
		return id if id>=1 and id<=1000000000 and str(id)==suffix else -1
	for root in ["shell:back#","shell:west#"]:
		if not value.begins_with(root):continue
		var suffix=value.trim_prefix(root)
		if not suffix.is_valid_int():return -1
		var id=int(suffix);var limit=Footprint.WIDTH if root=="shell:back#" else Footprint.DEPTH
		return 0 if id>=0 and id<limit and str(id)==suffix else -1
	return -1

static func is_grid_format(value:int)->bool:
	return value in [PREVIOUS_WALL_FORMAT,WALL_FORMAT]

static func _placement(raw,previous:bool=false)->Dictionary:
	if not raw is Dictionary or raw.size()!=Walls.PLACEMENT.size():return {}
	var codec=Runtime.new();var result={}
	for field in Walls.PLACEMENT:
		if not codec._number(raw.get(field),-1.0,Footprint.WIDTH):return {}
		result[field]=float(raw[field])
	var centered=is_equal_approx(result.physical_back,-.08) and is_equal_approx(result.physical_front,.08) and is_equal_approx(result.visual_back,-.13) and is_equal_approx(result.visual_front,.13)
	var standard=is_equal_approx(result.physical_back,-.08) and is_equal_approx(result.physical_front,.08) and is_equal_approx(result.visual_back,-.18) and is_equal_approx(result.visual_front,.08)
	var outward=is_equal_approx(result.physical_back,-.26) and is_zero_approx(result.physical_front) and is_equal_approx(result.visual_back,-.26) and is_zero_approx(result.visual_front)
	if not (standard or outward) if previous else not centered:return {}
	if not codec._integer(result.pattern_offset,0,Footprint.WIDTH-1):return {}
	return result

static func read_walls(data:Dictionary,max_width:int,max_depth:int,owned:Callable,floor_styles:Array)->Dictionary:
	var bad={"ok":false,"error":"Invalid unified building data"};var codec=Runtime.new()
	var previous=data.get("wall_format")==PREVIOUS_WALL_FORMAT
	if not codec._integer(data.get("version"),Contract.VERSION,Contract.VERSION) or not codec._integer(data.get("wall_format"),PREVIOUS_WALL_FORMAT,WALL_FORMAT) or data.get("building_format")!=(PREVIOUS_FORMAT if previous else FORMAT):return bad
	if not codec._integer(data.get("wall_attachment_format"),ATTACHMENT_FORMAT,ATTACHMENT_FORMAT) or not codec._integer(data.get("starter_geometry_version"),Footprint.SAVE_REVISION,Footprint.SAVE_REVISION):return bad
	for obsolete in ["shell_products","shell_segment_products","shell_segment_format","shell_material"]:
		if data.has(obsolete):return bad
	if data.get("floor_style") not in floor_styles or not data.get("built_walls") is Array or data.built_walls.size()>max_width*(max_depth+1)+(max_width+1)*max_depth:return bad
	var walls:Array[Dictionary]=[];var ids={};var edges={};var highest=0
	for raw in data.built_walls:
		if not raw is Dictionary or raw.size()!=(9 if raw.has("placement") else 8) or not Walls.valid_shape(raw,max_width,max_depth):return bad
		var sequence=identity_sequence(raw.get("id"))
		if sequence<0 or ids.has(raw.id) or edges.has(Walls.key_of(raw)):return bad
		if not codec._integer(raw.get("paid_cost"),0,62) or not codec._integer(raw.get("refund_credit"),0,31) or [int(raw.paid_cost),int(raw.refund_credit)] not in RECEIPTS[raw.height]:return bad
		var sides=Walls.adjacent_cells(raw)
		if not owned.call(sides[0]) and not owned.call(sides[1]):return bad
		var placement={}
		if raw.has("placement"):
			placement=_placement(raw.placement,previous)
			if placement.is_empty():return bad
		walls.append(Walls.installed(str(raw.id),raw,int(raw.paid_cost),int(raw.refund_credit),placement))
		ids[raw.id]=true;edges[Walls.key_of(raw)]=true;highest=maxi(highest,sequence)
	if not codec._integer(data.get("next_wall_id"),highest+1,1000000001):return bad
	return {"ok":true,"walls":walls,"next_wall_id":int(data.next_wall_id),"floor_style":str(data.floor_style)}

static func read_openings(data:Dictionary,walls:Array)->Dictionary:
	var bad={"ok":false,"error":"Invalid unified door/window data"};var codec=Runtime.new()
	if not codec._integer(data.get("wall_attachment_format"),ATTACHMENT_FORMAT,ATTACHMENT_FORMAT) or not data.get("wall_attachments") is Array or data.wall_attachments.size()>300:return bad
	var attachments:Array[Dictionary]=[];var ids={};var highest=0
	for raw in data.wall_attachments:
		if not raw is Dictionary or raw.size()!=6 or not codec._integer(raw.get("id"),1,1000000000) or ids.has(int(raw.id)) or raw.get("kind") not in Openings.PRICES:return bad
		if not raw.get("wall_ids") is Array or raw.wall_ids.is_empty() or raw.wall_ids.size()>18:return bad
		for id in raw.wall_ids:
			if identity_sequence(id)<0:return bad
		if not codec._number(raw.get("offset"),0,18) or not codec._number(raw.get("width"),.01,18):return bad
		var width=float(raw.width)
		if not is_equal_approx(width,float(Openings.WIDTHS[raw.kind])) and not (raw.kind=="door" and (is_equal_approx(width,.76) or is_equal_approx(width,Footprint.LEGACY_DOOR_WIDTH) or is_equal_approx(width,Footprint.DOOR_WIDTH))):return bad
		if not codec._integer(raw.get("paid_cost"),0,int(Openings.PRICES[raw.kind])) or int(raw.paid_cost) not in [0,int(Openings.PRICES[raw.kind])]:return bad
		attachments.append({"id":int(raw.id),"kind":str(raw.kind),"wall_ids":raw.wall_ids.duplicate(),"offset":float(raw.offset),"width":width,"paid_cost":int(raw.paid_cost)})
		ids[int(raw.id)]=true;highest=maxi(highest,int(raw.id))
	if not codec._integer(data.get("next_attachment_id"),highest+1,1000000001):return bad
	var error=Openings.installed_support_error(walls,attachments)
	if error!="":return {"ok":false,"error":error}
	return {"ok":true,"attachments":attachments,"next_attachment_id":int(data.next_attachment_id)}

static func import_validated(products:Dictionary,segments:Dictionary,old_walls:Array,old_openings:Array)->Dictionary:
	var projection=LegacyEdges.project_validated_legacy(products,segments,old_walls,old_openings)
	if not projection.ok:return projection
	var walls:Array[Dictionary]=[];var by_id={}
	for edge in projection.edges.values():
		var phase=Openings.axis_value(edge.a-edge.pattern_origin,edge.axis)
		var placement={}
		# The strict old projection remains read-only evidence. Normalize only
		# the installed body's normal profile, never its edge, receipts or phase.
		if not is_zero_approx(phase):
			placement=Walls.PLACEMENT.duplicate();placement.pattern_offset=phase
		var wall=Walls.installed(str(edge.id),edge,int(edge.paid_cost),int(edge.refund_credit),placement)
		walls.append(wall);by_id[wall.id]=wall
	var openings:Array[Dictionary]=[]
	for opening in projection.openings:
		var first:Dictionary=by_id[opening.wall_ids[0]]
		var offset=Openings.axis_value((opening.a+opening.b)*.5-Vector2(first.x,first.z),first.axis)
		openings.append({"id":int(opening.id),"kind":str(opening.kind),"wall_ids":opening.wall_ids.duplicate(),"offset":offset,"width":float(opening.width),"paid_cost":int(opening.paid_cost)})
	var error=Openings.installed_support_error(walls,openings)
	if error!="":return {"ok":false,"error":error}
	return {"ok":true,"walls":walls,"attachments":openings,"migration_report":projection.migration_report}

static func preserve_original(original:String,destination:String)->String:
	# The isolated candidate cannot replace an imported payload unless its exact
	# original bytes have a verified content-addressed recovery copy. Existing
	# recovery files are only read; a conflicting copy stops the entire save.
	if original=="":return ""
	var digest=original.sha256_text()
	var path=destination+".pre-grid-"+digest+".json"
	if FileAccess.file_exists(path):
		return "" if FileAccess.get_sha256(path)==digest else "Original building backup differs; save left unchanged"
	var file=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return "Could not preserve original building save; save left unchanged"
	file.store_string(original);file.flush();var error=file.get_error();file.close()
	if error!=OK or FileAccess.get_sha256(path)!=digest:return "Could not verify original building backup; save left unchanged"
	return ""
