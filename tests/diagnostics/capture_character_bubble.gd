extends SceneTree
# Native production-renderer comparison. Run once against baseline and once
# against the candidate with isolated profiles; no game saves are loaded.
class Board extends "res://scripts/illustrated_cafe.gd":
 var comparison_before=false
 var capture_scale=1.0
 var crowded=false
 func _ready():
  set_process(false)
  use_cached_heads=false;use_cached_moving_art=false
 func label(at:Vector2,text:String):
  draw_string(ThemeDB.fallback_font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("516248"))
 func actor(at:Vector2,species:int,mirror:float,back:bool,seat:float,moving:bool,staff:bool,role:String):
  var pose={"mirror":mirror,"view_back":back,"seat_mix":seat,"blend":.8 if moving else 0.0,"phase":.17}
  art_transform(at,0,Vector2(mirror,1)*capture_scale)
  character(Vector2.ZERO,species,staff,moving,seat>.0,"blocked" if staff else "ordering",0.0,Vector2(18,-28),Vector2(1,0),"none","none",pose,role)
  var anchor=_character_bubble_anchor(species,staff,moving,pose,role)
  if comparison_before:anchor.x*=mirror
  art_transform(at,0,Vector2.ONE*capture_scale)
  bubble(anchor,"!" if staff else "…")
  art_transform(Vector2.ZERO)
 func _draw():
  draw_rect(Rect2(0,0,1600,1200),Color("e8dfbf"))
  label(Vector2(22,28),("BEFORE" if comparison_before else "AFTER")+" | Production character + bubble | scale "+str(capture_scale))
  if crowded:
   label(Vector2(560,60),"Viewport edges and neighboring actors")
   actor(Vector2(40,172),0,-1,true,0,false,true,"chef")
   actor(Vector2(1560,172),0,1,false,0,false,true,"chef")
   actor(Vector2(40,1160),1,-1,false,1,false,false,"customer")
   actor(Vector2(1560,1160),1,1,true,1,false,false,"customer")
   for index in range(6):actor(Vector2(440+index*100,450),index%3,-1.0 if index%2 else 1.0,index%2==0,1,false,false,"customer")
   label(Vector2(510,490),"Ordinary spacing: all six bubbles readable")
   actor(Vector2(730,860),1,1,false,1,false,false,"customer")
   actor(Vector2(758,870),2,-1,true,1,false,false,"customer")
   label(Vector2(470,930),"Deliberate overlap: baseline has no collision avoidance")
   return
  var views=[[1.0,false,"Front-right"],[-1.0,false,"Front-left"],[1.0,true,"Back-right"],[-1.0,true,"Back-left"]]
  var cases=[[1,1.0,false,false,"customer","Seated fox"],[0,1.0,false,false,"customer","Seated rabbit"],[2,1.0,false,false,"customer","Seated bear"],[0,0.0,false,true,"chef","Standing chef"],[1,0.0,false,true,"waiter","Standing waiter"],[2,0.0,true,true,"cleaner","Moving / turn blend"]]
  for col_index in range(4):label(Vector2(190+col_index*360,60),views[col_index][2])
  for row_index in range(cases.size()):
   var data=cases[row_index]
   label(Vector2(20,115+row_index*175),data[5])
   for col_index in range(4):
    var view=views[col_index]
    actor(Vector2(240+col_index*360,230+row_index*175),data[0],view[0],view[1],data[1],data[2],data[3],data[4])
var board
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(1600,1200)
 board=Board.new();board.comparison_before=OS.get_environment("BUBBLE_BASELINE")=="1";root.add_child(board)
 for scale in [0.8,1.6]:
  board.capture_scale=scale;board.crowded=false;board.queue_redraw()
  for frame in 3:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+("before" if board.comparison_before else "after")+"-angles-"+str(scale)+".png")
 board.crowded=true;board.capture_scale=1.6;board.queue_redraw()
 for frame in 3:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+("before" if board.comparison_before else "after")+"-neighbors-edges.png")
 print("CHARACTER_BUBBLE_NATIVE_RESULT angles=48 neighbors_and_edges=true synthetic=true player_save_used=false")
 board.queue_free();await process_frame;quit()
