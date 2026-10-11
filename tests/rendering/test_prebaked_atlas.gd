extends SceneTree
## Imported lossless-resource bytes and runtime selection; no renderer claim.
const Loader = preload("res://scripts/cafe_prebaked_atlas.gd")
const Furniture = preload("res://scripts/furniture_static_atlas.gd")
const Moving = preload("res://scripts/moving_art_atlas.gd")
const Heads = preload("res://scripts/character_head_atlas.gd")
var checks = 0
var failures = []
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
		check(not image.has_mipmaps(),names[i]+" retains level-zero output")
		image.convert(Image.FORMAT_RGBA8)
		var hash = HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data())
		check(hash.finish().hex_encode() == info.rgba_sha256,names[i]+" imported RGBA matches native renderer reference")
		var wrong = [Furniture,Moving,Heads][i].new()
		check(not Loader.try_load(wrong,names[i],Vector2i.ONE) and wrong.state == "cold",names[i]+" dimension mismatch leaves fallback available")
	var mipmaps = Furniture.new();mipmaps.use_mipmaps_for_qa = true
	check(not Loader.try_load(mipmaps,"furniture",mipmaps.size) and mipmaps.state == "cold","QA mipmap path retains original bake")
	print("PREBAKED_ATLAS_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
