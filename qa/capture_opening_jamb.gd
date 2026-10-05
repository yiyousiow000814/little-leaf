extends SceneTree
# Native production opening renderer, synthetic geometry only. No game Main,
# saved profile, service loop, or storage APIs are instantiated by this capture.
class Board extends "res://scripts/illustrated_cafe.gd":
 var sample_kind="door"
 var sample_width=1.0
 var phase_label="after"
 var records=[]
 var walls:Array=[{"id":1,"axis":"x","x":2,"z":2,"height":"full","material":"original"},{"id":2,"axis":"x","x":3,"z":2,"height":"full","material":"original"},{"id":3,"axis":"z","x":6,"z":2,"height":"full","material":"original"},{"id":4,"axis":"z","x":6,"z":3,"height":"full","material":"original"}]
 func _ready():set_process(false)
 func label(at:Vector2,text:String,size=18):draw_string(ThemeDB.fallback_font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color("516248"))
 func _draw():
  records.clear()
  draw_rect(Rect2(0,0,1600,1040),Color("e8dfbf"))
  label(Vector2(24,28),phase_label.to_upper()+" | "+sample_kind+" width="+str(sample_width)+" | top: committed, bottom: placement preview",20)
  var hosts=OpeningGeometry.shell_hosts("original",walls)
  hosts.append(OpeningGeometry.resolve_host("span:1,2",walls));hosts.append(OpeningGeometry.resolve_host("span:3,4",walls))
  for row in range(2):
   for col in range(4):
    var host=hosts[col];var length:float=host.a.distance_to(host.b)
    var attachment={"id":10,"kind":sample_kind,"host_id":host.host_id,"offset":length*.5,"width":sample_width,"paid_cost":0}
    # Use the exact free starter placement in its corresponding shell view.
    if col==1 and sample_kind=="door" and sample_width==1.0:attachment=OpeningGeometry.initial_attachments()[0]
    var opening=OpeningGeometry.aperture(attachment,walls)
    var center:Vector2=(opening.a+opening.b)*.5
    var anchor=Vector2(205+col*390,365+row*480)
    ui_scale=1.0;zoom=2.0;tile=Vector2(39,19.5)*zoom
    origin=anchor-Vector2((center.x-center.y)*tile.x,(center.x+center.y)*tile.y)
    var offset=float(attachment.offset);var start=maxf(0.0,offset-1.2);var finish=minf(length,offset+1.2)
    for panel in OpeningGeometry.solid_panels(host,walls,[attachment]):
     var a=maxf(start,float(panel.from));var b=minf(finish,float(panel.to))
     if b>a:OpeningArt.face(self,host,a,b,panel.bottom,panel.top,"e0e7d0","91a27d")
    OpeningArt.cap(self,host,start,finish)
    OpeningArt.threshold(self,opening)
    var alpha=.65 if row else 1.0;var tint=Color("c6e1ae") if row else Color.WHITE
    for part in ["start","middle","end"]:OpeningArt.casing(self,opening,part,alpha,tint)
    label(Vector2(25+col*390,442+row*480),str(host.host_id))
    records.append({"host":host.host_id,"kind":sample_kind,"width":sample_width,"preview":row==1,"top":opening.top,"bottom":opening.bottom,"a":str(opening.a),"b":str(opening.b),"normal":str(host.normal)})
var board
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(1600,1040)
 board=Board.new();board.phase_label=OS.get_environment("PHASE");root.add_child(board)
 var all=[]
 for sample in [["door",1.0,"starter"],["door",.76,"placed-door"],["window",.70,"window"]]:
  board.sample_kind=sample[0];board.sample_width=sample[1];board.queue_redraw()
  for frame in 5:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+board.phase_label+"-"+sample[2]+".png")
  all.append_array(board.records)
 FileAccess.open(OS.get_environment("OUTPUT")+"/"+board.phase_label+"-geometry.json",FileAccess.WRITE).store_string(JSON.stringify(all,"  "))
 print("OPENING_JAMB_NATIVE_RESULT ",JSON.stringify({"cases":all.size(),"synthetic":true,"player_save_used":false,"phase":board.phase_label}))
 board.queue_free();await process_frame;quit()
