extends Node
## Untimed, zero-game-instance parity of three native atlases for one frozen source.
var SOURCE_COMMIT = OS.get_environment("LL_ATLAS_SOURCE")
var OUTPUT = OS.get_environment("LL_ATLAS_OUTPUT")
const Furniture = preload("res://scripts/furniture_static_atlas.gd")
const Moving = preload("res://scripts/moving_art_atlas.gd")
const Heads = preload("res://scripts/character_head_atlas.gd")
const NAMES = ["furniture", "moving", "heads"]
var failures = []
func _ready():
 get_tree().create_timer(90.0).timeout.connect(func():
  FileAccess.open(OUTPUT.path_join("capture-failed.json"),FileAccess.WRITE).store_string('{"reason":"native atlas parity exceeded 90 seconds"}')
  printerr("Native atlas parity timeout");get_tree().quit(2))
 run.call_deferred()
func wait_ready(atlases: Array) -> bool:
 var deadline = Time.get_ticks_msec() + 30000
 while Time.get_ticks_msec() < deadline:
  var ready = true
  for atlas in atlases:
   if atlas.state == "failed_fallback":return false
   ready = ready and atlas.is_ready()
  if ready:return true
  await get_tree().process_frame
 return false
func digest(atlas) -> String:
 var hash = HashingContext.new();hash.start(HashingContext.HASH_SHA256)
 hash.update(atlas.texture.get_image().get_data())
 return hash.finish().hex_encode()
func run():
 if DisplayServer.get_name() == "headless" or not "saveguard" in OS.get_user_data_dir():
  printerr("Native renderer and disposable saveguard profile are required");get_tree().quit(2);return
 var baseline = [Furniture.new(), Moving.new(), Heads.new()]
 for atlas in baseline:
  atlas.state = "warming"
  atlas._build.call_deferred(get_tree())
 if not await wait_ready(baseline):
  printerr("Regenerated atlas preparation failed or timed out");get_tree().quit(1);return
 var expected = []
 for i in range(baseline.size()):
  expected.append(digest(baseline[i]))
  if baseline[i].texture.get_image().save_png(OUTPUT.path_join(NAMES[i]+"-regenerated.png")) != OK:
   failures.append("Could not save regenerated " + NAMES[i])
 baseline.clear()
 # Capture retained imports independently before request() can fall back to regeneration.
 var actual = []
 var retained = []
 for i in range(3):
  var texture = load("res://assets/cache/"+NAMES[i]+"-atlas.png") as Texture2D
  if texture == null:
   failures.append("Retained import missing " + NAMES[i]);actual.append("");retained.append({"name":NAMES[i],"loaded":false});continue
  var img = texture.get_image();img.convert(Image.FORMAT_RGBA8)
  var h=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(img.get_data())
  actual.append(h.finish().hex_encode())
  retained.append({"name":NAMES[i],"loaded":true,"size":[img.get_width(),img.get_height()]})
  if img.save_png(OUTPUT.path_join(NAMES[i]+"-atlas.png")) != OK:failures.append("Could not save retained imported " + NAMES[i])
  if expected[i] != actual[i]:failures.append("Atlas " + NAMES[i] + " differs")
 var artist = Node2D.new();get_tree().root.add_child(artist)
 var candidate = [Furniture.new(), Moving.new(), Heads.new()]
 for atlas in candidate:atlas.request(artist)
 var request_ready = await wait_ready(candidate)
 var request_rows = []
 if not request_ready:failures.append("Runtime request failed or timed out")
 for i in range(candidate.size()):
  var prebaked = candidate[i].stats.get("prebaked",false)
  if not prebaked:failures.append("Not using imported prebaked " + NAMES[i])
  request_rows.append({"name":NAMES[i],"prebaked":prebaked,"state":candidate[i].state,"texture_size":[candidate[i].texture.get_width(),candidate[i].texture.get_height()] if candidate[i].texture != null else [],"rgba_sha256":digest(candidate[i]) if candidate[i].texture != null else ""})
 var receipt={"checks":3,"baseline_sha256":expected,"candidate_sha256":actual,"failures":failures,
  "retained_imports":retained,"runtime_requests":request_rows,"source_commit":SOURCE_COMMIT,"engine":Engine.get_version_info().string,"display_server":DisplayServer.get_name(),
  "adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
  "player_data_used":false,"game_instance_created":false,"timing_claim":false}
 FileAccess.open(OUTPUT.path_join("atlas-parity.json"),FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
 print("WELCOME_ATLAS_NATIVE_PARITY_RESULT ", JSON.stringify(receipt))
 get_tree().quit(0 if failures.is_empty() else 1)
