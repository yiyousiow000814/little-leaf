extends RefCounted
## Read-only payload for the existing developer profiler, not a sampler or UI.
## Caller owns explicit activation, low-rate sampling and bounded retention.
## Hashes are diagnostic fingerprints, not cryptographic integrity receipts.
const MAX_NODE_RECORDS=4
const MAX_NODE_SCAN=4096

static func _digest(value)->String:
	return "%08x" % hash(value)

static func _style_counts()->Dictionary:
	return {"warm_oak":0,"cream_tile":0,"sage_tile":0,"other":0}

static func _region(cell:Vector2i,model)->String:
	return "base" if cell.x<model.BASE_WIDTH and cell.y<model.BASE_DEPTH else "expansion"

static func _regions()->Dictionary:
	return {"base":{"owned_count":0,"styles":_style_counts()},
		"expansion":{"owned_count":0,"styles":_style_counts()}}

static func _terrain(model)->Dictionary:
	var styles=_style_counts()
	var cells=[]
	var owned=[]
	var regions=_regions()
	var content_key=""
	for z in range(model.MAX_DEPTH):
		for x in range(model.MAX_WIDTH):
			var cell=Vector2i(x,z)
			if not model.is_floor_owned(cell):
				content_key+="/"
				continue
			owned.append(cell)
			var region=regions[_region(cell,model)]
			region.owned_count+=1
			var style=str(model.floor_style_at(cell))
			content_key+="/"+style
			if style=="":continue
			cells.append([cell,style])
			var name=style if styles.has(style) else "other"
			styles[name]+=1;region.styles[name]+=1
	return {"content_key":content_key,"count":cells.size(),"report":{
		"instance":str(model.get_instance_id()),"revision":int(model.revision),
		"record_count":model.floor_finishes.size(),"owned_count":owned.size(),
		"styles":styles,"regions":regions,"content_hash":_digest(cells),"ownership_hash":_digest(owned)}}

static func _mesh(ground,model)->Dictionary:
	var mesh=ground.floor_mesh
	var vertices=0
	var indices=0
	var colors=_style_counts()
	var regions={"base":_style_counts(),"expansion":_style_counts()}
	var regions_complete=true
	var geometry_hashes=[]
	var surfaces=mesh.get_surface_count() if mesh!=null else 0
	for surface in range(surfaces):
		var arrays=mesh.surface_get_arrays(surface)
		vertices+=arrays[Mesh.ARRAY_VERTEX].size()
		indices+=arrays[Mesh.ARRAY_INDEX].size()
		geometry_hashes.append([hash(arrays[Mesh.ARRAY_VERTEX]),
			hash(arrays[Mesh.ARRAY_COLOR]),hash(arrays[Mesh.ARRAY_INDEX])])
		var color_array=arrays[Mesh.ARRAY_COLOR]
		var mapped=surfaces==1 and color_array.size()==ground.floor_cells.size()*4
		regions_complete=regions_complete and mapped
		for index in color_array.size():
			var color=color_array[index]
			var style="other"
			for known in ["warm_oak","cream_tile","sage_tile"]:
				if color.is_equal_approx(ground.floor_palette(known)[0]):
					style=known
					break
			colors[style]+=1
			if mapped:regions[_region(ground.floor_cells[index/4],model)][style]+=1
	regions_complete=regions_complete and vertices==ground.floor_cells.size()*4
	return {"instance":str(mesh.get_instance_id()) if mesh!=null else "",
		"surfaces":surfaces,"vertices":vertices,"indices":indices,
		"style_vertices":colors,"regions":regions,"regions_complete":regions_complete,
		"region_basis":"cached_floor_cells","geometry_hash":_digest(geometry_hashes)}

static func _native_expected(artist)->bool:
	# Stream.active describes submission only and is false after finish().
	# Match the actual artist routing guards, not that transient frame flag.
	return artist.use_batched_ground and artist.use_native_object_nodes \
		and artist.use_command_retention and artist.use_retained_geometry \
		and is_instance_valid(artist.game) and artist.icon_kind=="" \
		and artist.material==null and not artist.use_parent_material \
		and artist.clip_children==CanvasItem.CLIP_CHILDREN_DISABLED

static func _native(artist)->Dictionary:
	var nodes=[]
	var matching=0
	var visible=0
	var scanned=0
	for order in artist.native_world_shapes:
		if scanned>=MAX_NODE_SCAN:break
		scanned+=1
		var node=artist.native_world_shapes[order]
		if not is_instance_valid(node) or node.draw_method!=&"draw_mesh" \
			or node.draw_arguments.is_empty() \
			or node.draw_arguments[0]!=artist.ground_art.floor_mesh:continue
		matching+=1
		if node.is_visible_in_tree():visible+=1
		if nodes.size()>=MAX_NODE_RECORDS:continue
		var placement=node.global_transform
		nodes.append({"instance":str(node.get_instance_id()),"order":int(order),
			"tree_index":node.get_index(),"draw_method":str(node.draw_method),
			"generation":int(node.get_meta("generation",-1)),
			"visible":node.visible,"visible_in_tree":node.is_visible_in_tree(),
			"material_instance":str(node.material.get_instance_id()) if node.material!=null else "",
			"use_parent_material":node.use_parent_material,
			"alpha":node.modulate.a,"self_alpha":node.self_modulate.a,
			"transform":[placement.x.x,placement.x.y,placement.y.x,
				placement.y.y,placement.origin.x,placement.origin.y]})
	return {"expected":_native_expected(artist),
		"submission_active":bool(artist.canvas_stream.active),
		"generation":int(artist.canvas_stream.frame_id),"scanned":scanned,
		"scan_complete":scanned==artist.native_world_shapes.size(),
		"matching":matching,"visible":visible,"nodes":nodes}

static func capture(artist)->Dictionary:
	var started=Time.get_ticks_usec()
	var model=artist.game.model
	var ground=artist.ground_art
	var terrain=_terrain(model)
	var mesh=_mesh(ground,model)
	var native=_native(artist)
	var owner_matches=ground.model_ref!=null and ground.model_ref.get_ref()==model
	var flags=[]
	if not owner_matches:flags.append("terrain_cache_model_differs")
	if ground.floor_content_key!=terrain.content_key:flags.append("terrain_cache_content_differs")
	if ground.floor_cells.size()!=terrain.count:flags.append("terrain_cell_count_differs")
	for style in terrain.report.styles:
		if mesh.style_vertices[style]!=terrain.report.styles[style]*4:
			flags.append("mesh_style_count_differs:"+style)
	if mesh.regions_complete:
		for region in mesh.regions:
			for style in mesh.regions[region]:
				if mesh.regions[region][style]!=terrain.report.regions[region].styles[style]*4:
					flags.append("mesh_region_style_differs:"+region+":"+style)
	if native.expected and native.scan_complete and native.visible!=1:
		flags.append("visible_native_floor_count_differs")
	return {"schema":1,"engine_rendered_frames":Engine.get_frames_drawn(),
		"model":terrain.report,"mesh":mesh,"native":native,"observations":flags,
		"ground":{"revision":int(ground.revision),"model_matches":owner_matches,
			"rebuilds":ground.floor_rebuilds,"cell_count":ground.floor_cells.size(),
			"cells_hash":_digest(ground.floor_cells),
			"content_key_hash":_digest(ground.floor_content_key)},
		"capture_usec":Time.get_ticks_usec()-started}
