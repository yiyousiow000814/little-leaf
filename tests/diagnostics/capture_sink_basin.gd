extends SceneTree
## Enlarged native views rendered by the same sink and queue painters as play.
const Model=preload("res://scripts/cafe_model.gd")
const Dishes=preload("res://scripts/cafe_dishwashing.gd")
class FixtureGame extends Node:
 var model=Model.new()
 var dishwashing=Dishes.new()
 var service_guests={}
 var editing=false
class Sheet extends "res://scripts/illustrated_cafe.gd":
 var font=preload("res://assets/fonts/NotoSans-Regular.ttf")
 func _ready():set_process(false)
 func _process(_delta):pass
 func _draw():
  draw_rect(Rect2(0,0,1360,1024),Color("e5e9d5"))
  draw_string(font,Vector2(32,34),"Sink close-up · "+OS.get_environment("PHASE").capitalize(),HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color("29473c"))
  var sink=game.model.get_item(3)
  for rotation in range(4):
   draw_string(font,Vector2(32,115+rotation*220),"Rotation "+str(rotation*90)+"°",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("29473c"))
   for column in range(3):
    var count=[0,1,6][column];sink.rot=rotation;game.dishwashing.dishes.clear()
    for index in count:game.dishwashing.dishes[index+1]={"id":index+1,"sink_id":3,"elapsed":0.0}
    if rotation==0:draw_string(font,Vector2(245+column*380,64),["Empty basin","1 dirty dish","6 dirty dishes"][column],HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("426050"))
    art_transform(Vector2(300+column*380,250+rotation*220),0,Vector2.ONE*3.0)
    furniture_art.draw_item(self,"sink",Vector2.ZERO,rotation,3)
    _sink_dishes(3)
    art_transform(Vector2.ZERO)
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(1360,1024);DisplayServer.window_set_title("Little Leaf sink basin QA")
 var fixture=FixtureGame.new();fixture.model.reset_new();root.add_child(fixture)
 var sheet=Sheet.new();sheet.game=fixture;root.add_child(sheet)
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 var path=OS.get_environment("OUTPUT")+"/"+OS.get_environment("PHASE")+"-sink-rotations.png"
 var error=root.get_texture().get_image().save_png(path)
 assert(error==OK,"Save only the requested synthetic game viewport")
 print("SINK_NATIVE_CAPTURE ",JSON.stringify({"phase":OS.get_environment("PHASE"),"file":path,"rotations":4,"quantities":[0,1,6],"render_scale":3.0,"player_save_used":false}))
 quit()
