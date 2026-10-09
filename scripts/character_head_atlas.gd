extends RefCounted
## Original-art rigid head layers only. Animated limbs, body, feet and props
## remain live, with the original depth order and actor transform unchanged.
const ART_RECT:=Rect2(-19,-76,40,54)
const BAKE_SCALE:=4
const COLUMNS:=10
const CELL:=Vector2i(160,216)
const SIZE:=Vector2i(1600,1728)
var state:="cold"
var texture:Texture2D
var entries:Array=[]
var regions:Dictionary={}
var stats:Dictionary={"state":"cold","parts":78,"bake_scale":4,"width":1600,"height":1728,"retained_rgba_bytes_estimate":11059200,"warmup_ms":0.0,"conversion":"GPU straight-alpha; native alpha-edge repair; level-zero RGBA8"}
var _bake_viewports: Array = []
var _started_us:=0

func _init():
	for species in range(3):
		for chef in [false,true]:
			for view in range(4):
				var away=view==3
				for blink in ([false] if away else [false,true]):
					for blocked in ([false] if away else [false,true]):
						var entry={"species":species,"away":away,"blink":blink,"chef":chef,"blocked":blocked,"view":view}
						var index:=entries.size()
						entries.append(entry)
						regions[key(species,away,blink,chef,blocked,view)]=Rect2(Vector2(index%COLUMNS,index/COLUMNS)*Vector2(CELL),Vector2(CELL))

static func key(species:int,away:bool,blink:bool,chef:bool,blocked:bool,view:int=-1)->String:
	var direction=3 if away else (0 if view<0 else view)
	return "%d/%d/%d/%d/%d"%[posmod(species,3),direction,0 if away else int(blink),int(chef),0 if away else int(blocked)]

func is_ready()->bool:return state=="ready" and texture!=null

func request(artist:Node2D):
	if state!="cold" or not artist.is_inside_tree():return
	if DisplayServer.get_name()=="headless":
		state="headless_fallback";stats.state=state;return
	if preload("res://scripts/cafe_prebaked_atlas.gd").try_load(self,"heads",SIZE):return
	state="warming";stats.state=state
	_started_us=Time.get_ticks_usec()
	_build.call_deferred(artist.get_tree())

func _viewport(tree:SceneTree)->SubViewport:
	var viewport:=SubViewport.new()
	viewport.size=SIZE;viewport.disable_3d=true;viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	viewport.render_target_clear_mode=SubViewport.CLEAR_MODE_ALWAYS
	tree.root.add_child(viewport)
	_bake_viewports.append(viewport)
	return viewport

func _build(tree:SceneTree):
	if state != "warming":return
	var script=load("res://scripts/character_head_painter.gd")
	if script==null:_fail("Painter unavailable");return
	var viewport:=_viewport(tree)
	var painter=script.new();painter.atlas=self;viewport.add_child(painter)
	await RenderingServer.frame_post_draw
	if state != "warming":return
	await tree.process_frame
	if state != "warming":return
	var straight:=_viewport(tree)
	var converter:=TextureRect.new()
	converter.texture=viewport.get_texture();converter.size=Vector2(SIZE)
	converter.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var shader:=Shader.new()
	shader.code="shader_type canvas_item; render_mode unshaded, blend_disabled; void fragment(){ vec4 c=texture(TEXTURE,UV); COLOR=vec4(c.a>0.0 ? c.rgb/c.a : vec3(0.0),c.a); }"
	var material:=ShaderMaterial.new();material.shader=shader;converter.material=material
	straight.add_child(converter)
	await RenderingServer.frame_post_draw
	if state != "warming":return
	var image:=straight.get_texture().get_image()
	if image==null or image.is_empty() or image.get_size()!=SIZE:
		viewport.queue_free();straight.queue_free();_fail("Empty native readback");return
	image.convert(Image.FORMAT_RGBA8);image.fix_alpha_edges()
	texture=ImageTexture.create_from_image(image)
	stats["retained_image_bytes"]=image.get_data().size()
	stats["warmup_ms"]=(Time.get_ticks_usec()-_started_us)/1000.0
	stats["bake_draws"]=int(painter.bake_draws)
	state="ready";stats.state=state
	viewport.queue_free();straight.queue_free()

func cancel_prepare(reason: String):
	if state not in ["cold","warming"]:return
	state = "failed_fallback";stats.state = state;stats["reason"] = reason
	for viewport in _bake_viewports:
		if is_instance_valid(viewport) and not viewport.is_queued_for_deletion():viewport.queue_free()
	_bake_viewports.clear()

func _fail(reason:String):
	state="failed_fallback";stats.state=state;stats["reason"]=reason
	push_warning("Head cache remains on original geometry: "+reason)

func draw_head(artist:Node2D,p:Vector2,species:int,away:bool,blink:bool,chef:bool,blocked:bool,view:int=-1):
	var region:Rect2=regions[key(species,away,blink,chef,blocked,view)]
	artist.draw_texture_rect_region(texture,Rect2(p+ART_RECT.position,ART_RECT.size),region)
