extends SceneTree
## Actual native renderer, synthetic state, intercepted startup/save calls.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
class Props extends "res://scripts/illustrated_cafe.gd":
 func _ready():set_process(false)
 func _process(_delta):pass
 func _draw():
  draw_rect(Rect2(0,0,1360,880),Color("e5e9d5"))
  for rotation in range(4):
   for column in range(2):
    art_transform(Vector2(310+column*680,175+rotation*205),0,Vector2.ONE*3.0)
    furniture_art.draw_item(self,"stove" if column==0 else "beverage",Vector2.ZERO,rotation,0)
    art_transform(Vector2.ZERO)
var game
var records=[]
var out=""
func _initialize():run.call_deferred()
func capture(label):
 game._update_ui();game.illustration.queue_redraw()
 for frame in 8:await process_frame
 await RenderingServer.frame_post_draw
 assert(root.get_texture().get_image().save_png(out.path_join(label+".png"))==OK)
 records.append({"label":label,"viewport":str(root.size),"zoom":game.illustration.zoom,"safe_rect":str(game.illustration.camera_safe_rect()),"saves_intercepted":game.saves})
func run():
 out=OS.get_environment("OUTPUT")
 if out=="" or not "saveguard" in OS.get_user_data_dir() or DisplayServer.get_name()=="headless":printerr("CAPTURE SAVEGUARD FAILED");quit(2);return
 seed(1010);root.size=Vector2i(1360,880)
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame
 game.model.operating_open=false
 for view in [Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390)]:
  root.size=view;game.editing=false;game.tray.hide();await process_frame
  game.illustration.fit_overview();await capture("%dx%d-play-fit"%[view.x,view.y])
  game.editing=true;game.tray.show();game.compact_ui._set_tray_reveal(1);await process_frame
  game.illustration.fit_overview();await capture("%dx%d-decorate-fit"%[view.x,view.y])
 root.size=Vector2i(1360,880);game.editing=false;game.tray.hide();await process_frame
 game.illustration.zoom=2.5;game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection()
 game.illustration.pan_offset+=Vector2(800,400)-game.illustration.iso(11,.5);game.illustration.update_projection(false)
 # Render-only synthetic prop beyond owned flooring tests foreground occlusion.
 game.model.items.append({"id":90001,"kind":"beverage","x":14,"z":0,"rot":0})
 game._rebuild_furniture();await capture("rear-tree-fixed-angle")
 game.hide();game.ui.hide();game.illustration.hide()
 var sheet=Props.new();sheet.game=game;root.add_child(sheet)
 for frame in 8:await process_frame
 await RenderingServer.frame_post_draw
 assert(root.get_texture().get_image().save_png(out.path_join("stove-juice-four-rotations.png"))==OK)
 FileAccess.open(out.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"records":records,"player_save_used":false,"renderer":RenderingServer.get_video_adapter_name()},"  "))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 sheet.queue_free();game.queue_free();await process_frame;quit()
