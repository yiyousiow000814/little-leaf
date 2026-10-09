extends Node
## Untimed full-scene HUD comparison; both passes use generated, frozen state.
const Hud=preload("res://scripts/cafe_hud.gd")
const Intro=preload("res://scripts/cafe_intro.gd")
const NAMES=["rail","wallet","mobile_purse","sign","decorate","decorate_done","staff","settings","cream_face","green_face","shop_frame"]
class CaptureGame extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=false;MinimalStart.apply(model)
 func _autosave():return
 func _save():return true
 func _setup_music():pass
var records=[]
var output=""
func _ready():
 get_tree().create_timer(90.0).timeout.connect(func():
  if output!="":FileAccess.open(output.path_join("capture-failed.json"),FileAccess.WRITE).store_string('{"reason":"native capture exceeded 90 seconds"}')
  printerr("Native HUD parity timeout");get_tree().quit(2))
 run.call_deferred()
func populate_raw_reference():
 # Exact original non-coin faithful PNG path: decode, generate mips, upload.
 # This comparison changes only texture representation, never layout or art.
 for name in NAMES:
  var image=Image.new()
  assert(image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/ui/fidelity_hud/"+name+".png"))==OK)
  image.generate_mipmaps()
  Hud.textures[name]=ImageTexture.create_from_image(image)
func shot(viewport,game,label,pass_index):
 for frame in 5:
  game._update_ui();await get_tree().process_frame
 await RenderingServer.frame_post_draw
 var file="%d-%dx%d-%s.png"%[pass_index,viewport.size.x,viewport.size.y,label]
 assert(viewport.get_texture().get_image().save_png(output.path_join(file))==OK)
 var controls={"wallet":game.compact_ui.hud.wallet,"pause":game.pause_button,"decorate":game.edit_button,"staff":game.compact_ui.staff_access,"settings":game.compact_ui.settings_button}
 var geometry={}
 for name in controls:
  var node=controls[name];var rect=node.get_global_rect()
  geometry[name]={"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"visible":node.is_visible_in_tree()}
 records.append({"file":file,"pass":pass_index,"state":label,"viewport":[viewport.size.x,viewport.size.y],"geometry":geometry,"save_writes_suppressed":game.save_writes_suppressed})
func run():
 output=OS.get_environment("OUTPUT")
 if output=="":output="/workspace/shared/hud-import-native-20261009-v2"
 if DisplayServer.get_name()=="headless" or not "saveguard" in OS.get_user_data_dir():
  printerr("Native renderer and disposable saveguard profile are required");get_tree().quit(2);return
 DirAccess.make_dir_recursive_absolute(output)
 for pass_index in [0,1,2,3]:
  var imported=pass_index in [1,2]
  for size in [Vector2i(1360,880),Vector2i(960,540),Vector2i(390,844),Vector2i(844,390)]:
   Hud.textures.clear()
   if not imported:populate_raw_reference()
   var viewport=SubViewport.new();viewport.size=size;viewport.disable_3d=true
   viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
   seed(42);Intro.shown_this_session=false
   var game=CaptureGame.new();viewport.add_child(game);game.cafe_intro.finish()
   game.paused=true;game.process_mode=Node.PROCESS_MODE_DISABLED
   await shot(viewport,game,"play",pass_index)
   game.settings.show();await shot(viewport,game,"settings",pass_index);game.settings.hide()
   game.compact_ui.staff_panel.show();await shot(viewport,game,"staff",pass_index);game.compact_ui._hide_popups()
   game._toggle_edit();game.compact_ui._set_tray_reveal(1)
   await shot(viewport,game,"decorate",pass_index)
   game.category_buttons["Decor"].pressed.emit();game.catalog_cards["plant"].pressed.emit()
   await shot(viewport,game,"selected-plant",pass_index)
   viewport.queue_free();await get_tree().process_frame
 var receipt={"records":records,"engine":Engine.get_version_info().string,"adapter":RenderingServer.get_video_adapter_name(),"player_data_used":false,"timing_claim":false,"reference":"Same candidate runtime with exact original non-coin raw PNG texture construction; coin path unchanged"}
 FileAccess.open(output.path_join("captures.json"),FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
 print("HUD_IMPORT_NATIVE_CAPTURE ",JSON.stringify({"captures":records.size(),"output":output}))
 await verify_atlas_parity()

const Furniture = preload("res://scripts/furniture_static_atlas.gd")
const Moving = preload("res://scripts/moving_art_atlas.gd")
const Heads = preload("res://scripts/character_head_atlas.gd")
var failures = []
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
func verify_atlas_parity():
 if DisplayServer.get_name() == "headless":
  printerr("Rendered atlas parity requires the approved native CI renderer")
  get_tree().quit(2);return
 var baseline = [Furniture.new(), Moving.new(), Heads.new()]
 for atlas in baseline:
  atlas.state = "warming"
  atlas._build.call_deferred(get_tree())
 if not await wait_ready(baseline):
  printerr("Baseline atlas preparation failed or timed out");get_tree().quit(1);return
 var expected = []
 for atlas in baseline:expected.append(digest(atlas))
 # Drop reference textures before the second set; both use identical render inputs.
 baseline.clear()
 var artist = Node2D.new();get_tree().root.add_child(artist)
 var candidate = [Furniture.new(), Moving.new(), Heads.new()]
 for atlas in candidate:atlas.request(artist)
 if not await wait_ready(candidate):
  printerr("Candidate atlas preparation failed or timed out");get_tree().quit(1);return
 var actual = []
 for atlas in candidate:actual.append(digest(atlas))
 for i in range(expected.size()):
  if expected[i] != actual[i]:failures.append("Atlas %d differs" % i)
  var output = self.output
  if output != "" and failures.is_empty():
   var filename = ["furniture", "moving", "heads"][i] + "-atlas.png"
   if candidate[i].texture.get_image().save_png(output.path_join(filename)) != OK:
    failures.append("Could not save " + filename)
 var receipt={"checks":3,"baseline_sha256":expected,"candidate_sha256":actual,"failures":failures}
 FileAccess.open(output.path_join("atlas-parity.json"),FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
 print("ATLAS_RENDER_PARITY_RESULT ", JSON.stringify(receipt))
 get_tree().quit(0 if failures.is_empty() else 1)
