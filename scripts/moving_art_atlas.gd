extends RefCounted
## Original rigid pieces only: limbs rotate continuously; body/head/props keep
## their existing transforms and depth order. No frame or action is quantized.
const BAKE_SCALE=4
const WIDTH=1024
const SHIRTS=["9cbbbd","c98e83","d6b16b","a9b78a","739c7f","b99578","91b2ad","d2b485"]
const ARM_LENGTH=10.5
const LEG_LENGTH=9.5
var state="cold"
var texture:Texture2D
var size=Vector2i(WIDTH,0)
var entries:Array=[]
var regions={}
var rectangles={}
var bases={}
var stats={"state":"cold","bake_scale":4,"conversion":"Native4x original geometry, straight-alpha conversion, alpha-edge repair; level-zero filtering"}
var _started_us=0
func _init():
	add_part("arm_cream",Rect2(-5,-5,10,23),{"type":"limb","length":ARM_LENGTH,"color":"efe5c7","width":4.8})
	add_part("arm_fox",Rect2(-5,-5,10,23),{"type":"limb","length":ARM_LENGTH,"color":"c68b46","width":4.8})
	add_part("leg",Rect2(-5,-5,10,22),{"type":"limb","length":LEG_LENGTH,"color":"858366","width":4.0})
	add_part("foot",Rect2(-6,-5,13,10),{"type":"foot"})
	add_part("shadow",Rect2(-12,-6,24,12),{"type":"shadow"})
	add_part("fox_tail",Rect2(-27,-31,24,20),{"type":"fox_tail"})
	add_part("apron",Rect2(-9,-34,18,23),{"type":"apron"})
	add_part("tree",Rect2(-55,-141,110,148),{"type":"tree"})
	for rotation in range(4):add_part("bin/%d"%rotation,Rect2(-21,-37,42,51),{"type":"bin","rotation":rotation})
	for shirt in SHIRTS:
		add_part("body/"+shirt+"/standing",Rect2(-13,-36,27,26),{"type":"body","shirt":shirt,"seated":false,"fwd":Vector2.ZERO,"side":Vector2.ZERO})
		for forward in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
			for mirror in [-1.0,1.0]:
				var across=Vector2(-forward.y,forward.x)
				var fwd=Vector2((forward.x-forward.y)*25*mirror,(forward.x+forward.y)*12.5)
				var side=Vector2((across.x-across.y)*25*mirror,(across.x+across.y)*12.5)
				var basis=basis_key(fwd,side);bases[basis]={"fwd":fwd,"side":side}
				add_part("body/"+shirt+"/"+basis,Rect2(-17,-36,35,28),{"type":"body","shirt":shirt,"seated":true,"fwd":fwd,"side":side})
	entries.sort_custom(func(a,b):return a.bounds.size.y>b.bounds.size.y if a.bounds.size.y!=b.bounds.size.y else a.key<b.key)
	var x=0;var y=0;var row_height=0;var area=0
	for entry in entries:
		var pixels=Vector2i(entry.bounds.size*BAKE_SCALE)
		if x+pixels.x>WIDTH:y+=row_height;x=0;row_height=0
		regions[entry.key]=Rect2(x,y,pixels.x,pixels.y);x+=pixels.x;row_height=maxi(row_height,pixels.y);area+=pixels.x*pixels.y
	size.y=y+row_height
	stats.merge({"parts":entries.size(),"width":size.x,"height":size.y,"retained_rgba_bytes_estimate":size.x*size.y*4,"packing_utilization":float(area)/(size.x*size.y)},true)
func add_part(key:String,bounds:Rect2,data:Dictionary):
	data["key"]=key;data["bounds"]=bounds;entries.append(data);rectangles[key]=bounds
static func basis_key(fwd:Vector2,side:Vector2)->String:
	return "%d,%d,%d,%d"%[roundi(fwd.x*2),roundi(fwd.y*2),roundi(side.x*2),roundi(side.y*2)]
func body_key(shirt:String,seated:bool,fwd:Vector2,side:Vector2)->String:
	if shirt not in SHIRTS:return ""
	if not seated:return "body/"+shirt+"/standing"
	var basis=basis_key(fwd,side)
	if not bases.has(basis) or not (bases[basis].fwd as Vector2).is_equal_approx(fwd) or not (bases[basis].side as Vector2).is_equal_approx(side):return ""
	return "body/"+shirt+"/"+basis
func limb_key(length:float,color,width:float)->String:
	var tint=Color(color)
	if is_equal_approx(length,ARM_LENGTH) and is_equal_approx(width,4.8):
		if tint.is_equal_approx(Color("efe5c7")):return "arm_cream"
		if tint.is_equal_approx(Color("c68b46")):return "arm_fox"
	if is_equal_approx(length,LEG_LENGTH) and is_equal_approx(width,4.0) and tint.is_equal_approx(Color("858366")):return "leg"
	return ""
func is_ready()->bool:return state=="ready" and texture!=null
func request(artist:Node2D):
	if state!="cold" or not artist.is_inside_tree():return
	if DisplayServer.get_name()=="headless":state="headless_fallback";stats.state=state;return
	if preload("res://scripts/cafe_prebaked_atlas.gd").try_load(self,"moving",size):return
	state="warming";stats.state=state;_started_us=Time.get_ticks_usec();_build.call_deferred(artist.get_tree())
func _viewport(tree:SceneTree)->SubViewport:
	var v=SubViewport.new();v.size=size;v.disable_3d=true;v.transparent_bg=true
	v.render_target_update_mode=SubViewport.UPDATE_ONCE;v.render_target_clear_mode=SubViewport.CLEAR_MODE_ALWAYS;tree.root.add_child(v);return v
func _build(tree:SceneTree):
	var script=load("res://scripts/moving_art_painter.gd")
	if script==null:_fail("Painter unavailable");return
	var viewport=_viewport(tree);var painter=script.new();painter.atlas=self;viewport.add_child(painter)
	await RenderingServer.frame_post_draw;await tree.process_frame
	var straight=_viewport(tree);var converter=TextureRect.new();converter.texture=viewport.get_texture();converter.size=Vector2(size);converter.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var shader=Shader.new();shader.code="shader_type canvas_item; render_mode unshaded, blend_disabled; void fragment(){vec4 c=texture(TEXTURE,UV);COLOR=vec4(c.a>0.0?c.rgb/c.a:vec3(0.0),c.a);}"
	var material=ShaderMaterial.new();material.shader=shader;converter.material=material;straight.add_child(converter)
	await RenderingServer.frame_post_draw
	var image=straight.get_texture().get_image()
	if image==null or image.is_empty() or image.get_size()!=size:viewport.queue_free();straight.queue_free();_fail("Empty native readback");return
	image.convert(Image.FORMAT_RGBA8);image.fix_alpha_edges();texture=ImageTexture.create_from_image(image)
	stats["retained_image_bytes"]=image.get_data().size();stats["warmup_ms"]=(Time.get_ticks_usec()-_started_us)/1000.0;stats["bake_draws"]=int(painter.bake_draws)
	state="ready";stats.state=state;viewport.queue_free();straight.queue_free()
func _fail(reason:String):
	state="failed_fallback";stats.state=state;stats["reason"]=reason;push_warning("Moving art cache uses original fallback: "+reason)
func draw_part(artist:Node2D,key:String,p:Vector2,scale=1.0):
	var rect:Rect2=rectangles[key]
	artist.draw_texture_rect_region(texture,Rect2(p+rect.position*scale,rect.size*scale),regions[key])
func draw_limb(artist:Node2D,key:String,start:Vector2,finish:Vector2):
	var direction=(finish-start).normalized();var across=Vector2(direction.y,-direction.x)
	var rect:Rect2=rectangles[key];var region:Rect2=regions[key]
	var points=PackedVector2Array();var uvs=PackedVector2Array()
	for uv in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
		var local=rect.position+rect.size*uv;points.append(start+across*local.x+direction*local.y);uvs.append((region.position+region.size*uv)/Vector2(size))
	artist.draw_polygon(points,PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE]),uvs,texture)
