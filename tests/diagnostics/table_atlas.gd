extends SceneTree
## Table-only cache regeneration: no game, model, profile or timing claim.
const Furniture=preload("res://scripts/furniture_static_atlas.gd")
const Moving=preload("res://scripts/moving_art_atlas.gd")
const Heads=preload("res://scripts/character_head_atlas.gd")
const Loader=preload("res://scripts/cafe_prebaked_atlas.gd")
var output=OS.get_environment("TABLE_ATLAS_OUTPUT")
var mode=OS.get_environment("TABLE_ATLAS_MODE")
var names=["furniture","moving","heads"]
var failures=[]
func _initialize():run.call_deferred()
func digest(image:Image):
 image.convert(Image.FORMAT_RGBA8)
 var h=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(image.get_data());return h.finish().hex_encode()
func run():
 assert(DisplayServer.get_name()!="headless" and output!="")
 var atlases=[Furniture.new(),Moving.new(),Heads.new()]
 for atlas in atlases:atlas.state="warming";atlas._build.call_deferred(self)
 for frame in 300:
  if atlases.all(func(a):return a.is_ready()):break
  await process_frame
 assert(atlases.all(func(a):return a.is_ready()),"Native atlas regeneration must finish")
 var regenerated=[];var imported=[];var requests=[]
 var region:Rect2i=Rect2i(atlases[0].regions["table_body/0"])
 for i in 3:
  var fresh:Image=atlases[i].texture.get_image();fresh.convert(Image.FORMAT_RGBA8)
  var texture=load("res://assets/cache/"+names[i]+"-atlas.png") as Texture2D
  assert(texture!=null)
  var old:Image=texture.get_image();old.convert(Image.FORMAT_RGBA8)
  regenerated.append(digest(fresh));imported.append(digest(old))
  if mode=="generate" and i==0:
   var masked=old.duplicate();masked.blit_rect(fresh,region,region.position)
   if masked.get_data()!=fresh.get_data():failures.append("Furniture changed outside owned table_body cell")
   if old.get_data()==fresh.get_data():failures.append("Table correction did not change baked pixels")
   old.get_region(region).save_png(output.path_join("table-before.png"))
   fresh.get_region(region).save_png(output.path_join("table-after.png"))
   assert(fresh.save_png(output.path_join("furniture-atlas.png"))==OK)
  elif fresh.get_data()!=old.get_data():failures.append(names[i]+" imported RGBA differs from regeneration")
  if mode=="verify":
   var cached=[Furniture.new(),Moving.new(),Heads.new()][i]
   if not Loader.try_load(cached,names[i],Vector2i(fresh.get_size())):failures.append(names[i]+" cache not loaded")
   else:
    requests.append({"name":names[i],"prebaked":cached.stats.prebaked,"bake_draws":cached.stats.bake_draws})
    if digest(cached.texture.get_image())!=regenerated[i]:failures.append(names[i]+" loaded cache differs")
 var receipt={"checks":3,"baseline_sha256":regenerated,"candidate_sha256":imported,"failures":failures,"mode":mode,"table_region":[region.position.x,region.position.y,region.size.x,region.size.y],"runtime_requests":requests,"engine":Engine.get_version_info().string,"display_server":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"player_save_used":false,"game_created":false}
 FileAccess.open(output.path_join(mode+".json"),FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
 print("TABLE_ATLAS_RESULT ",JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
