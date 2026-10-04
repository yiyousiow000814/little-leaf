extends RefCounted
## Retains the nine ordered quads used by Godot 4.6.3's positive-width AA lines.
## No joins, welding, overlap removal, width compensation, or raster baking.
## Adapted from renderer_canvas_cull.cpp (MIT): docs/third-party/GODOT-AA-LICENSE.txt.
## The installed binary has an unresolved commit hash; native pixels are a gate.

const FEATHER_SIZE := 1.25
const VERTICES_PER_LINE := 36
const INDICES_PER_LINE := 54
var vertices := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var line_count := 0

func _quad(a: Vector2,b: Vector2,c: Vector2,d: Vector2,ca: Color,cb: Color,cc: Color,cd: Color):
	var first := vertices.size()
	vertices.append(a);vertices.append(b);vertices.append(c);vertices.append(d)
	colors.append(ca);colors.append(cb);colors.append(cc);colors.append(cd)
	# GLES3 CommandPrimitive uses 0,1,2 then 0,2,3, including the corner diagonal.
	for index in [0,1,2,0,2,3]:indices.append(first+index)

func add_line(from: Vector2,to: Vector2,color: Color,width: float):
	assert(is_finite(width) and width>=0.0,"Retained AA strokes require a finite nonnegative width")
	# The RenderingServer API takes a float32 width, even in GDScript's float64 VM.
	var native_width: float=PackedFloat32Array([width])[0]
	var diff := from-to
	var direction := diff.orthogonal().normalized()
	var half_width := direction*native_width*.5
	var a := from+half_width
	var b := from-half_width
	var c := to+half_width
	var d := to-half_width
	var feather := FEATHER_SIZE
	if native_width<1.0:feather=PackedFloat32Array([feather*native_width])[0]
	var side := direction*feather
	var end := diff.normalized()*feather
	var clear := Color(color,0.0)
	_quad(a,b,d,c,color,color,color,color)
	_quad(a,a+side,c+side,c,color,clear,clear,color)
	_quad(b,b-side,d-side,d,color,clear,clear,color)
	_quad(a,a+end,b+end,b,color,clear,clear,color)
	_quad(c,c-end,d-end,d,color,clear,clear,color)
	_quad(a,a+end,a+side+end,a+side,color,clear,clear,clear)
	_quad(b,b+end,b-side+end,b-side,color,clear,clear,clear)
	_quad(c,c-end,c+side-end,c+side,color,clear,clear,clear)
	_quad(d,d-end,d-side-end,d-side,color,clear,clear,clear)
	line_count+=1

func add_multiline(points: PackedVector2Array,color: Color,width: float):
	assert(points.size()%2==0,"AA multiline needs disconnected point pairs")
	for index in range(0,points.size(),2):add_line(points[index],points[index+1],color,width)

func make_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if vertices.is_empty():return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_INDEX]=indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return mesh
