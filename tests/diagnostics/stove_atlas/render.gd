extends SceneTree
const Classes=[preload("res://scripts/furniture_static_atlas.gd"),preload("res://scripts/moving_art_atlas.gd"),preload("res://scripts/character_head_atlas.gd")]
var atlases=[]
func _initialize():run.call_deferred()
func run():
 var names=["furniture","moving","heads"]
 for cls in Classes:
  var atlas=cls.new();atlas.state="warming";atlas._started_us=Time.get_ticks_usec();atlases.append(atlas);atlas._build(self)
 for frame in range(600):
  await process_frame
  if atlases.all(func(a):return a.is_ready()):break
 var hashes=[];var cached=[];var matches=[];var failed=[]
 for i in range(3):
  if not atlases[i].is_ready():failed.append(names[i]+":"+atlases[i].state);continue
  var image=atlases[i].texture.get_image();image.convert(Image.FORMAT_RGBA8)
  var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data());hashes.append(hash.finish().hex_encode())
  var reference=Image.load_from_file("res://assets/cache/"+names[i]+"-atlas.png");reference.convert(Image.FORMAT_RGBA8)
  hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(reference.get_data());cached.append(hash.finish().hex_encode())
  matches.append(image.get_data()==reference.get_data())
  image.save_png("res://native-"+names[i]+"-atlas.png")
 var report={"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"checks":hashes.size(),"failures":failed,"rgba_sha256":hashes,"cached_rgba_sha256":cached,"matches_existing_cache":matches}
 var output=FileAccess.open("res://atlas-render-result.json",FileAccess.WRITE);output.store_string(JSON.stringify(report));output.close()
 print("ATLAS_RENDER_RESULT ",JSON.stringify(report));quit(0 if failed.is_empty() else 1)
