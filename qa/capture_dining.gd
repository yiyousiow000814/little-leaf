extends SceneTree
# Native production-art fixtures, with exact live seat docking and depth order.
# This renderer never creates the game model or reads/writes a player save.
class Board extends "res://scripts/illustrated_cafe.gd":
 var facing_forward=Vector2.RIGHT
 var pull_override=-1.0
 var chair_pull=.24
 var style="basic"
 var species=0
 var before=false
 var board_scale=2.0
 var endpoint=false
 var live_progress=-1.0
 func _ready():set_process(false);use_cached_heads=false;use_cached_moving_art=false
 func label(at:Vector2,text:String,size=17):draw_string(ThemeDB.fallback_font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color("516248"))
 func _table_guest_direction(_id:int)->Vector2:return -facing_forward
 func _dining_style(_id:int,_variant:String="")->String:return style
 func meal_progress(progress:float)->float:
  if before:return 1.0-progress
  var clock=clampf(progress,0,1)*4
  return 1.0-float(mini(4,int(clock)+(1 if fposmod(clock,1)>=.26 else 0)))/4.0
 func diner(at:Vector2,mirror:float,back:bool,progress:float,dirty=false):
  var vertical=-1.0 if back else 1.0
  facing_forward=(Vector2.UP if mirror>0 else Vector2.LEFT) if back else (Vector2.RIGHT if mirror>0 else Vector2.DOWN)
  var table=Vector2(39*mirror,19.5*vertical)
  var pull=0.0 if before or dirty else (chair_pull if pull_override<0 else pull_override)
  var chair_shift=Vector2(39*mirror,19.5*vertical)*pull
  var dock=Vector2(4.68*mirror,2.34*vertical)+chair_shift
  var pose={"mirror":mirror,"view_back":back,"seat_mix":1.0,"blend":0.0,"phase":0.0}
  var r=(0 if mirror>0 else 3) if back else (1 if mirror>0 else 2)
  # The chair's rear rail and the table use the live depth ordering.
  var entries=[{"depth":vertical*pull,"part":"seat"},{"depth":vertical*pull+(.38 if back else -.38),"part":"rail"},{"depth":vertical,"part":"table"},{"depth":vertical*(.12+pull)+.15,"part":"body"}]
  if not back and not before and not dirty:entries.append({"depth":1.02,"part":"overlay"})
  entries.sort_custom(func(x,y):return x.depth<y.depth)
  for entry in entries:
   if entry.part=="table":
    art_transform(at+table*board_scale,0,Vector2.ONE*board_scale)
    item("table",Vector2.ZERO,0,0);_plate(_table_surface_point(0),meal_progress(progress),dirty);_cup(_table_surface_point(0,true))
   elif entry.part in ["seat","rail"]:
    art_transform(at+chair_shift*board_scale,0,Vector2.ONE*board_scale)
    _chair(Vector2.ZERO,r,entry.part=="rail",style)
   else:
    var options=pose.duplicate()
    options["hide_reach"]=not back and not before and not dirty and entry.part=="body"
    options["reach_overlay"]=entry.part=="overlay"
    art_transform(at+dock*board_scale,0,Vector2(mirror,1)*board_scale)
    var plate=table-dock+_table_surface_point(0)
    character(Vector2.ZERO,species,false,false,true,"idle" if dirty else "eating",progress,Vector2(plate.x*mirror,plate.y),Vector2(1,0),"none","none",options,"customer")
  art_transform(Vector2.ZERO)
 func _draw():
  draw_rect(Rect2(0,0,1800,1200),Color("e8dfbf"))
  label(Vector2(20,27),("BEFORE 0.1.8" if before else "LOCAL DINING CANDIDATE")+" | "+["Rabbit","Fox","Bear"][species]+" | seat-relative place setting, shared chair tuck, rigid 8px spoon",19)
  var views=[[1.0,false,"Front-right"],[-1.0,false,"Front-left"],[1.0,true,"Back-right"],[-1.0,true,"Back-left"]]
  var phases=[1.0,1.235,1.4,1.61,1.95]
  var names=["Rest","Plate contact","Lift + morsel","Mouth / chew","Return"]
  if endpoint:phases=[.78,.805,.82,.92,1.0];names=["Last reach","Last scoop","Used during bite","Finish return","Checkout crockery"]
  for col in range(5):label(Vector2(180+col*335,63),names[col])
  for row in range(4):
   label(Vector2(12,125+row*260),views[row][2])
   for col in range(5):
    var at=Vector2(220+col*335+(35 if views[row][0]<0 else -35),245+row*260)
    var progress=phases[col] if endpoint else phases[col]/4.0
    if live_progress>=0:progress=live_progress
    diner(at,views[row][0],views[row][1],progress,endpoint and col==4)
  label(Vector2(20,1172),"Native GL Compatibility | synthetic seated geometry | no player save | scale "+str(board_scale),16)
var board
func _initialize():run.call_deferred()
func capture(name):
 board.queue_redraw()
 for frame in 3:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+name+".png")
func run():
 root.size=Vector2i(1800,1200)
 board=Board.new();board.before=OS.get_environment("BASELINE")=="1"
 if not board.before:board.chair_pull=float(load("res://scripts/dining_placement.gd").CHAIR_PULL)
 root.add_child(board)
 for species in range(3):
  board.species=species;board.endpoint=false
  await capture("dining-species-"+str(species))
  board.endpoint=true;await capture("end-species-"+str(species))
 for style in ["cottage","retro","refined"]:
  board.style=style;board.species=0;board.endpoint=false;await capture("dining-style-"+style)
 board.style="basic"
 board.species=0;board.endpoint=false;board.board_scale=1.0
 await capture("dining-game-scale")
 print("DINING_NATIVE_RESULT species=3 facings=4 bite_stages=5 endpoints=5 game_scale=true save_loaded=false")
 board.queue_free();await process_frame;quit()
