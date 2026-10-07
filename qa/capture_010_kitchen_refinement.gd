extends SceneTree
## Same-state native enlarged props, fresh intercepted synthetic startup only.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
class Props extends "res://scripts/illustrated_cafe.gd":
 var layout="master"
 var detail_rotation=0
 func _ready():set_process(false)
 func _process(_delta):pass
 func _draw():
  if layout=="detail":
   draw_rect(Rect2(0,0,1200,900),Color("e5e9d5"))
   draw_string(ThemeDB.fallback_font,Vector2(50,55),"R%d — native pan detail 12x / dispenser 10x"%detail_rotation,HORIZONTAL_ALIGNMENT_LEFT,-1,28,Color("466b57"))
   art_transform(Vector2(300,510),0,Vector2.ONE*12)
   furniture_art.draw_static_part(self,"stove_pan",Vector2.ZERO,detail_rotation)
   art_transform(Vector2(900,730),0,Vector2.ONE*10)
   furniture_art.draw_item(self,"beverage",Vector2.ZERO,detail_rotation,0)
   art_transform(Vector2.ZERO)
   return
  if layout=="native":
   draw_rect(Rect2(0,0,640,480),Color("e5e9d5"))
   draw_string(ThemeDB.fallback_font,Vector2(30,28),"Actual native 1x art — four rotations",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("466b57"))
   for rotation in range(4):
    draw_string(ThemeDB.fallback_font,Vector2(45,95+rotation*100),"R%d"%rotation,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("466b57"))
    for column in range(2):
     art_transform(Vector2(180+column*280,105+rotation*100),0,Vector2.ONE)
     furniture_art.draw_item(self,"stove" if column==0 else "beverage",Vector2.ZERO,rotation,0)
     art_transform(Vector2.ZERO)
   return
  draw_rect(Rect2(0,0,1800,1800),Color("e5e9d5"))
  draw_string(ThemeDB.fallback_font,Vector2(90,60),"Stove handle — four rotations",HORIZONTAL_ALIGNMENT_LEFT,-1,30,Color("466b57"))
  draw_string(ThemeDB.fallback_font,Vector2(990,60),"Dispenser cup stack — four rotations",HORIZONTAL_ALIGNMENT_LEFT,-1,30,Color("466b57"))
  for rotation in range(4):
   draw_string(ThemeDB.fallback_font,Vector2(50,260+rotation*425),"R%d"%rotation,HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color("466b57"))
   for column in range(2):
    art_transform(Vector2(450+column*900,350+rotation*425),0,Vector2.ONE*5.0)
    furniture_art.draw_item(self,"stove" if column==0 else "beverage",Vector2.ZERO,rotation,0)
    art_transform(Vector2.ZERO)
func _initialize():run.call_deferred()
func run():
 var out=OS.get_environment("OUTPUT")
 if out=="" or not "saveguard" in OS.get_user_data_dir() or DisplayServer.get_name()=="headless":printerr("CAPTURE SAVEGUARD FAILED");quit(2);return
 seed(1010);root.size=Vector2i(1800,1800)
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame
 game.model.operating_open=false;game.hide();game.ui.hide();game.illustration.hide()
 var sheet=Props.new();sheet.game=game;root.add_child(sheet)
 var records=[]
 for label in ["master","native","r0","r1","r2","r3"]:
  sheet.layout="detail" if label.begins_with("r") else label
  sheet.detail_rotation=int(label.substr(1)) if label.begins_with("r") else 0
  root.size=Vector2i(1200,900) if sheet.layout=="detail" else (Vector2i(640,480) if sheet.layout=="native" else Vector2i(1800,1800))
  sheet.queue_redraw()
  for frame in 12:await process_frame
  await RenderingServer.frame_post_draw
  var pixels=root.get_texture().get_image()
  assert(pixels.get_size()==root.size)
  assert(pixels.save_png(out.path_join(label+".png"))==OK)
  records.append({"label":label,"size":str(pixels.get_size())})
 FileAccess.open(out.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"captures":records,"art_scales":[1,5,10,12],"saves_intercepted":game.saves,"player_save_used":false,"renderer":RenderingServer.get_video_adapter_name()},"  "))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 sheet.queue_free();game.queue_free();await process_frame;quit()
