extends RefCounted
## Retained, untextured ground geometry. Furniture and actors are still individual
## live drawing commands. The mesh preserves exact per-tile colors; dark grid and
## fine grain retain the engine's AA triangles in two additional native meshes.
## Pan transforms the retained vertices. Effective scale changes rebuild only
## stroke offsets, preserving the legacy width/feather behavior at every zoom.

const ExteriorExtent=preload("res://scripts/exterior_world_extent.gd")
const AAStrokes=preload("res://scripts/retained_aa_strokes.gd")
var use_stroke_mesh := true
var pavement_mesh: ArrayMesh
var floor_mesh: ArrayMesh
var pavement_stroke_mesh: ArrayMesh
var floor_stroke_mesh: ArrayMesh
var pavement_stroke_rebuilds := 0
var floor_stroke_rebuilds := 0
var pavement_stroke_scale := -1.0
var floor_stroke_scale := -1.0
var floor_content_key := ""
var floor_strokes: Array[Dictionary] = []
var pavement_grid := PackedVector2Array()
var floor_grid := PackedVector2Array()
var floor_marks := PackedVector2Array()
var pavement_edges := [PackedVector2Array(),PackedVector2Array()]
var floor_edges := [PackedVector2Array(),PackedVector2Array()]
var floor_cells: Array[Vector2i] = []
var revision := -2147483647
var floor_rebuilds := 0
# Edge-AA batches keep their two slots; a purchased indoor product has one tint.
# Alternating colours come only from separately installed products.
const FLOOR_COLORS := [Color("edd5ab"),Color("edd5ab")]
const FLOOR_PALETTES := {"bare":[Color("cbbfa8"),Color("cbbfa8")],"warm_oak":[Color("edd5ab"),Color("edd5ab")],"cream_tile":[Color("ece8d4"),Color("ece8d4")],"sage_tile":[Color("cbd7ba"),Color("cbd7ba")]}
var floor_colors=FLOOR_COLORS
var floor_line_color=Color("d4bf95")
const PAVEMENT_COLORS := [Color("dfe0c8"),Color("d7dcc2")]
const PAVEMENT_LEFT := -3.26

static func point(x: float,z: float) -> Vector2:
	return Vector2((x-z)*39,(x+z)*19.5)

func _add_line(lines: PackedVector2Array,a: Vector2,b: Vector2):
	lines.append(a);lines.append(b)

func _make_mesh(vertices: PackedVector2Array,colors: PackedColorArray,indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return mesh

func _quad(vertices: PackedVector2Array,colors: PackedColorArray,indices: PackedInt32Array,x: float,z: float,color: Color):
	var start := vertices.size()
	for p in [point(x,z),point(x+1,z),point(x+1,z+1),point(x,z+1)]:
		vertices.append(p);colors.append(color)
	for i in [0,1,2,0,2,3]:indices.append(start+i)

func _owns(model,cell: Vector2i) -> bool:
	return model.is_floor_owned(cell) if model.has_method("is_floor_owned") else cell.x>=0 and cell.x<12 and cell.y>=0 and cell.y<int(model.depth)

func prepare(model):
	if pavement_mesh==null:_build_pavement()
	if revision!=int(model.revision):
		revision=int(model.revision)
		# A notification is a dirty signal, not terrain content. Buying furniture,
		# wages and shifts must not allocate another floor/stroke buffer.
		var key := _floor_content_key(model)
		if key!=floor_content_key:
			floor_content_key=key
			_build_floor(model)

static func floor_palette(style:String)->Array:
	return FLOOR_PALETTES.get(style,FLOOR_PALETTES.bare)

static func floor_line(style:String)->Color:
	return Color("b5bea7") if style=="sage_tile" else (Color("c9c7b2") if style=="cream_tile" else Color("d4bf95"))

func _floor_content_key(model) -> String:
	var key := ""
	for z in range(model.MAX_DEPTH):
		for x in range(model.MAX_WIDTH):
			var cell=Vector2i(x,z)
			# Empty owned land and unowned land expose the same underlying grass.
			key+="/"+model.floor_style_at(cell) if _owns(model,cell) else "/"
	return key

func _build_pavement():
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	pavement_grid.clear()
	pavement_edges=[PackedVector2Array(),PackedVector2Array()]
	for z in range(ExteriorExtent.PAVEMENT_Z_MIN,ExteriorExtent.PAVEMENT_Z_MAX):
		var parity := posmod(z,2)
		for column in range(3):
			var x := PAVEMENT_LEFT+column
			_quad(vertices,colors,indices,x,z,PAVEMENT_COLORS[parity])
			_add_line(pavement_grid,point(x,z),point(x+1,z))
			_add_line(pavement_grid,point(x,z),point(x,z+1))
			if column==0:_add_line(pavement_edges[parity],point(x,z),point(x,z+1))
			if column==2:_add_line(pavement_edges[parity],point(x+1,z),point(x+1,z+1))
			if z==ExteriorExtent.PAVEMENT_Z_MIN:_add_line(pavement_edges[parity],point(x,z),point(x+1,z))
			if z==ExteriorExtent.PAVEMENT_Z_MAX-1:_add_line(pavement_edges[parity],point(x,z+1),point(x+1,z+1))
	pavement_mesh=_make_mesh(vertices,colors,indices)

func _build_floor(model):
	floor_rebuilds+=1
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	floor_grid.clear();floor_marks.clear();floor_cells.clear();floor_strokes.clear()
	floor_edges=[PackedVector2Array(),PackedVector2Array()]
	var layers={}
	for z in range(model.MAX_DEPTH):
		for x in range(model.MAX_WIDTH):
			var cell := Vector2i(x,z)
			if not _owns(model,cell):continue
			var style=str(model.floor_style_at(cell))
			# Ownership makes land usable; only an installed finish covers grass.
			if style=="":continue
			floor_cells.append(cell)
			var palette=floor_palette(style)
			if not layers.has(style):layers[style]={"grid":PackedVector2Array(),"edges":[PackedVector2Array(),PackedVector2Array()]}
			var layer=layers[style]
			var parity := posmod(x+z,2)
			_quad(vertices,colors,indices,x,z,palette[parity])
			_add_line(layer.grid,point(x,z),point(x+1,z));_add_line(layer.grid,point(x,z),point(x,z+1))
			_add_line(floor_grid,point(x,z),point(x+1,z));_add_line(floor_grid,point(x,z),point(x,z+1))
			if style=="warm_oak" and (x*7+z*13)%11==0:_add_line(floor_marks,point(x+.3,z+.4),point(x+.56,z+.4))
			if model.floor_style_at(cell+Vector2i.LEFT)=="":_add_line(layer.edges[parity],point(x,z),point(x,z+1))
			if model.floor_style_at(cell+Vector2i.RIGHT)=="":_add_line(layer.edges[parity],point(x+1,z),point(x+1,z+1))
			if model.floor_style_at(cell+Vector2i.UP)=="":_add_line(layer.edges[parity],point(x,z),point(x+1,z))
			if model.floor_style_at(cell+Vector2i.DOWN)=="":_add_line(layer.edges[parity],point(x,z+1),point(x+1,z+1))
	for style in layers:
		var layer=layers[style];var palette=floor_palette(str(style))
		for i in range(2):
			floor_edges[i].append_array(layer.edges[i])
			floor_strokes.append({"lines":layer.edges[i],"color":palette[i],"width":.7})
		floor_strokes.append({"lines":layer.grid,"color":floor_line(str(style)),"width":.65})
	floor_strokes.append({"lines":floor_marks,"color":Color(.69,.56,.35,.13),"width":.6})
	floor_mesh=_make_mesh(vertices,colors,indices)
	floor_stroke_mesh=null
	floor_stroke_scale=-1.0

func prepare_pavement_strokes(scale: float):
	assert(is_finite(scale) and scale>0.0)
	if pavement_stroke_mesh!=null and pavement_stroke_scale==scale:return
	var strokes := AAStrokes.new()
	for i in range(2):strokes.add_multiline(pavement_edges[i],PAVEMENT_COLORS[i],.7/scale)
	strokes.add_multiline(pavement_grid,Color("c7cbae"),.7/scale)
	pavement_stroke_mesh=strokes.make_mesh()
	pavement_stroke_scale=scale
	pavement_stroke_rebuilds+=1

func prepare_floor_strokes(scale: float):
	assert(is_finite(scale) and scale>0.0)
	if floor_stroke_mesh!=null and floor_stroke_scale==scale:return
	var strokes := AAStrokes.new()
	for batch in floor_strokes:strokes.add_multiline(batch.lines,batch.color,float(batch.width)/scale)
	floor_stroke_mesh=strokes.make_mesh()
	floor_stroke_scale=scale
	floor_stroke_rebuilds+=1

func _begin(artist) -> float:
	var scale: float=artist.tile.x/39.0
	artist.draw_set_transform(artist.origin,0,Vector2.ONE*scale)
	return scale

func draw_pavement(artist):
	var scale := _begin(artist)
	artist.draw_mesh(pavement_mesh,null)
	if use_stroke_mesh:
		prepare_pavement_strokes(scale)
		artist.draw_mesh(pavement_stroke_mesh,null)
	else:
		for i in range(2):
			if not pavement_edges[i].is_empty():artist.draw_multiline(pavement_edges[i],PAVEMENT_COLORS[i],.7/scale,true)
		artist.draw_multiline(pavement_grid,Color("c7cbae"),.7/scale,true)
	artist.draw_set_transform(Vector2.ZERO)

func draw_floor(artist):
	var scale := _begin(artist)
	artist.draw_mesh(floor_mesh,null)
	if use_stroke_mesh:
		prepare_floor_strokes(scale)
		artist.draw_mesh(floor_stroke_mesh,null)
	else:
		for batch in floor_strokes:
			if not batch.lines.is_empty():artist.draw_multiline(batch.lines,batch.color,float(batch.width)/scale,true)
	artist.draw_set_transform(Vector2.ZERO)
