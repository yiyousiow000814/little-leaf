extends SceneTree
const WIDTH=1360
const HEIGHT=880
const N_PAIRS=6
const WARM=12
const SAMPLES=36
var begin_us:=0
var enabled:=false
var samples:=PackedInt64Array()
var invalid:=false
class GroundNode extends "res://scripts/rendering/illustrated_cafe.gd":
	var park:=false
	func _ready():set_process(false)
	func _process(_delta):pass
	func _draw():pass
	func _parking_owned()->bool:return park
	func place(camera:Vector2,ratio:float,parking:bool)->bool:
		origin=camera;zoom=ratio;tile=Vector2(39.0,19.5)*ratio;park=parking
		return background_cache.update(self,origin,Vector2.ZERO)
func _initialize():run.call_deferred()
func pre():
	if not enabled:return
	if begin_us!=0:invalid=true
	begin_us=Time.get_ticks_usec()
func post():
	var finish_us:=Time.get_ticks_usec()
	if not enabled:return
	if begin_us<=0 or finish_us<=begin_us:invalid=true
	else:samples.append(finish_us-begin_us)
	begin_us=0
func settled(frames:int):
	for i in range(frames):await RenderingServer.frame_post_draw
func fail():quit(3)
func run():
	if DisplayServer.get_name()!="X11" or not RenderingServer.get_video_adapter_name().to_lower().contains("llvmpipe") or "dummy" in RenderingServer.get_current_rendering_driver_name():fail();return
	root.size=Vector2i(WIDTH,HEIGHT)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if DisplayServer.window_get_vsync_mode()!=DisplayServer.VSYNC_DISABLED:fail();return
	Engine.max_fps=0
	var a=GroundNode.new();var b=GroundNode.new();b.background_cache.prototype_ground_batches=true
	root.add_child(a);root.add_child(b);b.hide()
	a.ground_art._build_pavement();b.ground_art._build_pavement()
	RenderingServer.frame_pre_draw.connect(pre);RenderingServer.frame_post_draw.connect(post)
	await settled(3)
	if root.size!=Vector2i(WIDTH,HEIGHT):fail();return
	var frames=[]
	# Locate one actual batch entry/exit in a one-pixel horizontal pan.
	var edge:=0
	var previous_count:=-1
	var baseline_rebuilds:=-1
	for x in range(510,851):
		if not b.place(Vector2(x,260),1.0,false):fail();return
		if baseline_rebuilds<0:baseline_rebuilds=b.background_cache.rebuilds
		elif b.background_cache.rebuilds!=baseline_rebuilds:fail();return
		var count:int=b.background_cache.ground_triangles_submitted
		if previous_count>=0 and count!=previous_count:
			edge=x
			break
		previous_count=count
	if edge==0:fail();return
	var poses=[
		[Vector2(680,260),1.0,false],[Vector2(edge-1,260),1.0,false],[Vector2(edge,260),1.0,false],
		[Vector2(680,260),.5,false],[Vector2(680,260),1.55,false],
		[Vector2(1300,-610),1.0,false],[Vector2(680,260),1.0,true]]
	for i in range(poses.size()):
		var v=poses[i]
		a.show();b.hide()
		if not a.place(v[0],v[1],v[2]) or not b.place(v[0],v[1],v[2]):fail();return
		await settled(1)
		var control=root.get_texture().get_image();control.convert(Image.FORMAT_RGBA8)
		a.hide();b.show();await settled(1)
		var candidate=root.get_texture().get_image();candidate.convert(Image.FORMAT_RGBA8)
		var same=control.get_size()==Vector2i(WIDTH,HEIGHT) and candidate.get_size()==control.get_size() and control.get_data()==candidate.get_data()
		if i==0:
			var colors={}
			for y in range(40,HEIGHT,90):
				for x in range(40,WIDTH,100):colors[control.get_pixel(x,y)]=true
			same=same and colors.size()>=8
		if not same:fail();return
		frames.append(true)
	a.show();b.hide()
	if not a.place(Vector2(680,260),1.0,false) or not b.place(Vector2(680,260),1.0,false):fail();return
	var original:int=a.background_cache.meshes[0].surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()/3
	var reduced:int=b.background_cache.ground_triangles_submitted
	var branches:Array=b.background_cache.ground_batches
	var chunks:=0
	for row in branches:
		if row.shown:chunks+=1
	var counters={"original_triangles":original,"candidate_triangles":reduced,"candidate_chunks":chunks,"original_chunks":1}
	var rng:=RandomNumberGenerator.new();rng.seed=389740
	var schedule=[]
	for block in range(N_PAIRS):
		schedule.append("ABBA" if rng.randi_range(0,1)==0 else "BAAB")
	var slots=[]
	for order in schedule:
		for label in order:
			a.visible=label=="A";b.visible=not a.visible
			await settled(WARM)
			samples.clear();enabled=true
			await settled(SAMPLES)
			enabled=false
			if invalid or begin_us!=0 or samples.size()!=SAMPLES:fail();return
			slots.append({"label":label,"us":Array(samples)})
	var output=FileAccess.open(OS.get_environment("LL_GROUND_AB_RAW"),FileAccess.WRITE)
	if output==null:fail();return
	output.store_string(JSON.stringify({"pairs_exact_rgba":frames.size(),"schedule":schedule,"slots":slots,"counts":counters,"renderer":"X11_llvmpipe_compatibility"}))
	output.close();quit()
