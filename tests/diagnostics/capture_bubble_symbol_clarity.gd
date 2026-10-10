extends SceneTree
# Isolated native production art, no player profile or running simulation.
class Board extends "res://scripts/illustrated_cafe.gd":
 var phase=""
 var scale_label=""
 var capture_scale=1.0
 var warning=false
 var edges=false
 func _ready():
  set_process(false);use_cached_heads=false;use_cached_moving_art=false
 func label(at:Vector2,text:String):draw_string(ThemeDB.fallback_font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("516248"))
 func actor(bubble_center:Vector2,mirror:float,back:bool):
  var species=0 if warning else 1
  var pose={"mirror":mirror,"view_back":back,"seat_mix":0.0 if warning else 1.0,"blend":0.0,"phase":0.0}
  var anchor=_character_bubble_anchor(species,warning,false,pose,"chef")
  var at=bubble_center-anchor*capture_scale
  art_transform(at,0,Vector2(mirror,1)*capture_scale)
  character(Vector2.ZERO,species,warning,false,not warning,"blocked" if warning else "ordering",0.0,Vector2(18,-28),Vector2(1,0),"none","none",pose,"chef")
  art_transform(at,0,Vector2.ONE*capture_scale)
  bubble(anchor,"!" if warning else "…")
  art_transform(Vector2.ZERO)
 func _draw():
  draw_rect(Rect2(0,0,1600,1000),Color("819874"))
  label(Vector2(20,28),phase+" | "+scale_label+" | scale "+str(snappedf(capture_scale,.001)))
  if edges:
   var x=13.4*capture_scale+2;var y=10.4*capture_scale+2
   for center in [Vector2(x,y),Vector2(1600-x,y),Vector2(x,1000-13.4*capture_scale-2),Vector2(1600-x,1000-13.4*capture_scale-2)]:
    art_transform(center,0,Vector2.ONE*capture_scale);bubble(Vector2.ZERO,"!" if warning else "…");art_transform(Vector2.ZERO)
   return
  var views=[[1.0,false,"Front-right"],[-1.0,false,"Front-left"],[1.0,true,"Back-right"],[-1.0,true,"Back-left"]]
  for index in range(4):
   label(Vector2(150+index*400,65),views[index][2])
   actor(Vector2(200+index*400,250),views[index][0],views[index][1])
var board
var report={"synthetic":true,"player_save_used":false,"samples":[]}
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(1360,880)
 board=Board.new();root.add_child(board);await process_frame
 board.update_projection()
 var limits=board.camera_zoom_limits();var unit=board.ui_scale
 var sizes=[["minimum",unit*limits.x],["default",unit*1.15],["maximum",unit*limits.y],["reported-close",3.8]]
 report.camera_reference={"viewport":[1360,880],"ui_scale":unit,"zoom_limits":str(limits),"note":"Production camera formulas with default 104px HUD inset; display scale includes ui_scale"}
 root.size=Vector2i(1600,1000);board.phase=OS.get_environment("PHASE")
 for size in sizes:
  board.capture_scale=size[1];board.scale_label=size[0]
  for warning in [false,true]:
   board.warning=warning;board.edges=false;board.queue_redraw()
   for frame in 3:await process_frame
   await RenderingServer.frame_post_draw
   var name=board.phase+"-"+str(size[0])+"-"+("warning" if warning else "ordering")
   root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+name+".png")
   report.samples.append({"name":name,"scale":size[1],"four_facings":true})
 board.edges=true;board.scale_label="viewport edges";board.capture_scale=sizes[2][1]
 for warning in [false,true]:
  board.warning=warning;board.queue_redraw()
  for frame in 3:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+board.phase+"-edges-"+("warning" if warning else "ordering")+".png")
 FileAccess.open(OS.get_environment("OUTPUT")+"/"+board.phase+"-capture.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("BUBBLE_CLARITY_NATIVE_RESULT ",JSON.stringify(report))
 board.queue_free();await process_frame;quit()
