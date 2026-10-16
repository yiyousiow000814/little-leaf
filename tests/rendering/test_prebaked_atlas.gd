extends SceneTree
## Imported lossless-resource bytes and runtime selection; no renderer claim.
const Loader = preload("res://scripts/rendering/cafe_prebaked_atlas.gd")
const Furniture = preload("res://scripts/rendering/furniture_static_atlas.gd")
const Moving = preload("res://scripts/rendering/moving_art_atlas.gd")
const Heads = preload("res://scripts/rendering/character_head_atlas.gd")
const Pick = preload("res://scripts/rendering/cafe_character_pick_geometry.gd")
class CountingPick extends Pick:
	var readbacks=0
	func _read_texture_image(texture:Texture2D)->Image:
		readbacks+=1
		return super._read_texture_image(texture)
var checks = 0
var failures = []
var alpha_preparation = []
func check(ok, label):
	checks += 1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/prebaked_atlas_manifest.json"))
	var atlases = [Furniture.new(),Moving.new(),Heads.new()]
	var names = ["furniture","moving","heads"]
	for i in range(3):
		var atlas = atlases[i]
		var info = manifest.atlases[names[i]]
		check(Loader.try_load(atlas,names[i],Vector2i(info.width,info.height)),names[i]+" loads exact-size baked resource")
		check(atlas.is_ready() and atlas.stats.prebaked and atlas.stats.bake_draws == 0,names[i]+" ready without procedural bake")
		var image = atlas.texture.get_image()
		if names[i]=="furniture":
			var alpha:Image=atlas.hit_alpha_for(atlas.texture)
			check(alpha!=null and alpha.get_format()==Image.FORMAT_LA8,"furniture prepares owner-bound LA8 during asset loading")
			if alpha!=null:
				check(alpha.get_data_size()==info.width*info.height*2,"furniture alpha representation retains two bytes per pixel, not duplicate RGBA")
				var matches=true
				for y in range(0,image.get_height(),97):
					for x in range(0,image.get_width(),79):
						if alpha.get_pixel(x,y).a!=image.get_pixel(x,y).a:matches=false
				check(matches,"imported furniture alpha samples remain exact")
				var started=Time.get_ticks_usec()
				atlas.prepare_hit_alpha(image)
				alpha_preparation.append({"width":image.get_width(),"height":image.get_height(),"retained_bytes":atlas.hit_alpha_for(atlas.texture).get_data_size(),"cpu_image_prepare_ms":(Time.get_ticks_usec()-started)/1000.0,"display_server":DisplayServer.get_name(),"native_render_verified":false})
		check(not image.has_mipmaps(),names[i]+" retains level-zero output")
		image.convert(Image.FORMAT_RGBA8)
		var hash = HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data())
		check(hash.finish().hex_encode() == info.rgba_sha256,names[i]+" imported RGBA matches native renderer reference")
		var wrong = [Furniture,Moving,Heads][i].new()
		check(not Loader.try_load(wrong,names[i],Vector2i.ONE) and wrong.state == "cold",names[i]+" dimension mismatch leaves fallback available")
	var mipmaps = Furniture.new();mipmaps.use_mipmaps_for_qa = true
	check(not Loader.try_load(mipmaps,"furniture",mipmaps.size) and mipmaps.state == "cold","QA mipmap path retains original bake")
	alpha_owner_checks()
	print("PREBAKED_ATLAS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"alpha_preparation":alpha_preparation}))
	quit(0 if failures.is_empty() else 1)

func alpha_owner_checks():
	var source=Image.create(16,16,false,Image.FORMAT_RGBA8)
	for i in 256:source.set_pixel(i%16,i/16,Color(float((i*37)%256)/255.0,float((i*73)%256)/255.0,float((i*11)%256)/255.0,float(i)/255.0))
	var original=source.get_data()
	var counted=ImageTexture.create_from_image(source)
	var counted_atlas=Furniture.new();counted_atlas.size=source.get_size();counted_atlas.texture=counted
	check(counted_atlas.prepare_hit_alpha(source),"runtime preparation accepts the existing caller CPU image")
	var sample_pick=CountingPick.new()
	for i in 12:sample_pick._texture_alpha(counted,Vector2(3.25,7.75),{counted:counted_atlas.hit_alpha_for(counted)})
	check(sample_pick.readbacks==0,"repeated independent alpha queries borrow owner snapshot without readback")
	counted.emit_changed()
	sample_pick._texture_alpha(counted,Vector2(3.25,7.75),{})
	check(sample_pick.readbacks==1,"invalidated representation retains original uncached image fallback")
	var texture=ImageTexture.create_from_image(source)
	var atlas=Furniture.new();atlas.size=source.get_size();atlas.texture=texture
	check(atlas.prepare_hit_alpha(source),"runtime owner prepares from existing CPU source")
	var alpha:Image=atlas.hit_alpha_for(texture)
	check(source.get_data()==original and source.get_format()==Image.FORMAT_RGBA8,"alpha preparation cannot mutate source RGBA")
	var exact=true
	for i in 256:
		if source.get_pixel(i%16,i/16).a!=alpha.get_pixel(i%16,i/16).a:exact=false
	check(exact,"native LA8 conversion preserves every possible 8-bit alpha value")
	var pick=Pick.new()
	var matches=true
	for sample in [Vector2(-.5,-.5),Vector2(15.5,15.5),Vector2(3.25,7.75),Vector2(2.999,3.001),Vector2(0,0),Vector2(15,15)]:
		if pick._texture_alpha(texture,sample,{texture:source})!=pick._texture_alpha(texture,sample,{texture:alpha}):matches=false
	check(matches,"prepared alpha preserves exact bilinear and clamped-edge sampling")
	var stamp=atlas.hit_alpha_state()
	var replacement=source.duplicate();replacement.fill(Color.TRANSPARENT)
	texture.update(replacement)
	check(atlas.hit_alpha_for(texture)==null and atlas.hit_alpha_state()!=stamp,"in-place texture update invalidates alpha and query stamp")
	check(atlas.prepare_hit_alpha(replacement),"same texture can prepare a fresh exact snapshot")
	var next=ImageTexture.create_from_image(source)
	atlas.texture=next
	check(atlas.hit_alpha_for(texture)==null and atlas.hit_alpha_for(next)==null,"texture replacement cannot reuse old alpha")
	check(atlas.prepare_hit_alpha(source),"replacement prepares its own snapshot")
	stamp=atlas.hit_alpha_state();texture.emit_changed()
	check(atlas.hit_alpha_state()==stamp,"old texture signal is detached after replacement")
	next.set_size_override(Vector2i(8,8))
	check(atlas.hit_alpha_for(next)==null and atlas.hit_alpha_state()!=stamp,"size override cannot expose mismatched alpha despite no changed signal")
	next.set_size_override(Vector2i(16,16))
	check(not atlas.prepare_hit_alpha(Image.create(1,1,false,Image.FORMAT_RGBA8)) and atlas.hit_alpha_for(next)==null,"failed preparation clears earlier alpha rather than leaving stale data")
	atlas.prepare_hit_alpha(source)
	var owner_ref=weakref(atlas);var image_ref=weakref(atlas.hit_alpha_for(next))
	atlas=null;alpha=null
	check(owner_ref.get_ref()==null and image_ref.get_ref()==null,"owner destruction releases alpha without texture callback cycle")
