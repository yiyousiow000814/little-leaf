extends RefCounted
## Bounded experimental cache of ORIGINAL static procedural furnishing layers.
## One shared 4x atlas; no game/model references, files, saved state, or payloads.
## A native one-off bake is required. Headless/failed/warming paths stay legacy.

const PARTS := ["counter","stove_base","stove_pan","stove_controls","beverage_base","beverage_machine","beverage_accessories","sink","bookshelf","bench_seat","bench_back","divider","rug","table_body","chair_seat","chair_back","plant","lamp"]
# Integer original-art coordinates retain the native 4x sampling phase. Each
# crop includes a conservative transparent guard around the widest AA fringe.
# Source/bounds checks must be rerun whenever the editable geometry changes.
# Kitchen equipment translates down 9px as a whole; keep the same cell sizes
# and move those crops with it so the lower machine cannot be clipped.
const PART_BOUNDS := {
	"counter":Rect2(-43,-47,86,69), "stove_base":Rect2(-43,-49,86,69),
	"stove_pan":Rect2(-36,-51,72,47), "stove_controls":Rect2(-28,-30,56,40),
	"beverage_base":Rect2(-43,-49,86,71), "beverage_machine":Rect2(-27,-61,54,56),
	"beverage_accessories":Rect2(-27,-51,54,47), "sink":Rect2(-43,-60,86,82),
	"bookshelf":Rect2(-26,-80,52,96), "bench_seat":Rect2(-28,-35,56,50),
	"bench_back":Rect2(-28,-51,56,51), "divider":Rect2(-23,-69,46,82),
	"rug":Rect2(-30,-17,60,34), "table_body":Rect2(-33,-51,66,66),
	"chair_seat":Rect2(-21,-32,42,43), "chair_back":Rect2(-19,-46,38,42),
	"plant":Rect2(-24,-75,48,85), "lamp":Rect2(-22,-87,44,98)
}
const SINGLE_VARIANT_PARTS := ["table_body","plant","lamp"]
const BAKE_SCALE := 4
const PACK_WIDTH := 1280
var size := Vector2i(PACK_WIDTH,0)
var state := "cold"
var texture: ImageTexture
# Historical filtering control only; ordinary opt-in uses level zero.
var use_mipmaps_for_qa := false
var regions: Dictionary = {}
var stats: Dictionary = {"state":"cold","warmup_ms":0.0,"conversion":"GPU straight-alpha; native alpha-edge repair; level-zero RGBA8"}
var _started_us := 0

func _init():
	var entries: Array = []
	var packed_area := 0
	for part in PARTS:
		for rotation in rotations_for(part):
			var pixels := Vector2i(bounds(part).size*BAKE_SCALE)
			entries.append({"key":key(part,rotation),"size":pixels})
			packed_area+=pixels.x*pixels.y
	# Best-fit decreasing-height shelves: deterministic, no redundant full-size
	# slots and no four copies of artwork which ignores rotation. One atlas.
	entries.sort_custom(func(a,b):
		if a.size.y!=b.size.y:return a.size.y>b.size.y
		if a.size.x!=b.size.x:return a.size.x>b.size.x
		return a.key<b.key)
	var shelves: Array = []
	for entry in entries:
		var best := -1
		var waste := PACK_WIDTH+1
		for i in range(shelves.size()):
			var shelf: Dictionary=shelves[i]
			var remaining: int=PACK_WIDTH-int(shelf.x)-int(entry.size.x)
			if remaining>=0 and entry.size.y<=shelf.height and remaining<waste:
				best=i;waste=remaining
		if best<0:
			best=shelves.size()
			shelves.append({"x":0,"y":size.y,"height":entry.size.y})
			size.y+=entry.size.y
		var shelf: Dictionary=shelves[best]
		regions[entry.key]=Rect2(Vector2(shelf.x,shelf.y),Vector2(entry.size))
		shelf.x+=entry.size.x
	stats.merge({"parts":regions.size(),"bake_scale":BAKE_SCALE,"width":size.x,"height":size.y,"retained_rgba_bytes_estimate":size.x*size.y*4,"packing_utilization":float(packed_area)/(size.x*size.y)},true)

static func bounds(part: String) -> Rect2: return PART_BOUNDS[part]

static func rotations_for(part: String): return range(1 if part in SINGLE_VARIANT_PARTS else 4)

static func key(part: String,rotation: int) -> String:
	return "%s/%d"%[part,0 if part in SINGLE_VARIANT_PARTS else posmod(rotation,4)]

func is_ready() -> bool: return state=="ready" and texture!=null

func request(artist: Node2D):
	if state!="cold" or not artist.is_inside_tree(): return
	if DisplayServer.get_name()=="headless":
		state="headless_fallback";stats.state=state
		return
	state="warming";stats.state=state
	_started_us=Time.get_ticks_usec()
	_build.call_deferred(artist.get_tree())

func _viewport(tree: SceneTree) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size=size
	viewport.disable_3d=true
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	viewport.render_target_clear_mode=SubViewport.CLEAR_MODE_ALWAYS
	tree.root.add_child(viewport)
	return viewport

func _build(tree: SceneTree):
	# Load only after all source scripts finish loading; the painter inherits
	# the real artist's primitives, so no second version of the art is kept.
	var painter_script=load("res://scripts/furniture_atlas_painter.gd")
	if painter_script==null:
		_fail("Painter script unavailable")
		return
	var viewport := _viewport(tree)
	var painter=painter_script.new()
	painter.atlas=self
	viewport.add_child(painter)
	await RenderingServer.frame_post_draw
	await tree.process_frame
	# Transparent viewport pixels are premultiplied by the native renderer.
	# Convert in one GPU pass, instead of a millions-of-pixels GDScript loop.
	var straight := _viewport(tree)
	var converter := TextureRect.new()
	converter.texture=viewport.get_texture()
	converter.size=Vector2(size)
	converter.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var shader := Shader.new()
	shader.code="shader_type canvas_item; render_mode unshaded, blend_disabled; void fragment(){ vec4 c=texture(TEXTURE,UV); COLOR=vec4(c.a>0.0 ? c.rgb/c.a : vec3(0.0),c.a); }"
	var material := ShaderMaterial.new()
	material.shader=shader
	converter.material=material
	straight.add_child(converter)
	await RenderingServer.frame_post_draw
	var image := straight.get_texture().get_image()
	if image==null or image.is_empty() or image.get_size()!=size:
		viewport.queue_free();straight.queue_free()
		_fail("Native atlas readback was empty")
		return
	image.convert(Image.FORMAT_RGBA8)
	image.fix_alpha_edges()
	if use_mipmaps_for_qa:
		stats["retained_rgba_bytes_estimate"]=int(size.x*size.y*4*4.0/3.0)
		stats["conversion"]="GPU straight-alpha; native alpha-edge repair; QA mipmapped RGBA8"
		var error := image.generate_mipmaps()
		if error!=OK:
			viewport.queue_free();straight.queue_free()
			_fail("Atlas mipmap generation failed: %d"%error)
			return
	stats["mipmaps"]=use_mipmaps_for_qa
	texture=ImageTexture.create_from_image(image)
	stats["retained_image_bytes"]=image.get_data().size()
	stats["warmup_ms"]=(Time.get_ticks_usec()-_started_us)/1000.0
	stats["bake_draws"]=int(painter.bake_draws)
	state="ready";stats.state=state
	viewport.queue_free();straight.queue_free()

func _fail(reason: String):
	state="failed_fallback";stats.state=state;stats["reason"]=reason
	push_warning("Static furniture atlas remains on original art: "+reason)

func draw_part(artist: Node2D,part: String,p: Vector2,rotation: int):
	var region: Rect2=regions[key(part,rotation)]
	# Use TEXTURE_FILTER_LINEAR (not mipmapped); the source has native AA.
	# Filtering is set once on the artist by the opt-in integration/harness.
	# Existing outer draw transform supplies the live pan, zoom and placement.
	var art_rect := bounds(part)
	artist.draw_texture_rect_region(texture,Rect2(p+art_rect.position,art_rect.size),region)
