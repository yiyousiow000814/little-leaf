extends SceneTree
## Synthetic character-only native sequence. No Main, accounts, save loader or simulation.
class ClockFixture extends Node:
 var animation_time=0.0
 var wall_detail=false
class Artist extends "res://scripts/rendering/illustrated_cafe.gd":
 var state={}
 var enabled=false
 func _ready():
  texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
  moving_atlas.request(self);head_atlas.request(self)
 func _process(_delta):pass
 func _draw():
  if not enabled:return
  canvas_stream.begin(self,true);retained_geometry.begin_frame();render_contacts.clear()
  rounded_seen_previous=rounded_seen_current;rounded_seen_current={}
  var ids=range(24)
  if state.get("reverse",false):ids.reverse()
  for index in ids:
   if state.get("removed",false) and index>=12:continue
   var species=index%3;var role=["chef","waiter","cleaner","cashier"][int(index/3)%4]
   var back=index>=12
   var pose={"seat_mix":float(state.get("seat_mix",0.0)),"view_back":back,"phase":float(state.get("phase",0.0))}
   art_transform(Vector2(130+(index%6)*205,170+int(index/6)*195),0,Vector2(2.4,2.4))
   var cursor=canvas_stream.cursor
   if state.get("double_submit",false):
    character(Vector2.ZERO,index,true,false,false,"standby",.1,Vector2(18,-28),Vector2(1,0),"none","none",pose,role)
    canvas_stream.cursor=cursor
   character(Vector2.ZERO,index,true,bool(state.get("moving",false)),bool(state.get("seated",false)),str(state.get("action","standby")),float(state.progress),Vector2(18,-28),Vector2(1,0),str(state.get("payload","none")),str(state.get("tool","none")),pose,role)
  art_transform(Vector2.ZERO);_finish_native_objects();canvas_stream.finish()
var artist
var clock_fixture
var frames=[]
var output=OS.get_environment("OUTPUT")
func _initialize():run.call_deferred()
func normalized(contacts):
 var values=[]
 for item in contacts:
  var copy=item.duplicate(true);copy.erase("native_owner");values.append(copy)
 values.sort_custom(func(a,b):return a.id<b.id)
 return values
func completed_native(node,counts):
 for child in node.get_children():
  if child is CanvasItem and not child.is_visible_in_tree():continue
  if child.get_script()==preload("res://scripts/rendering/cafe_native_draw_node.gd"):
   assert(child.paint_revision==child.painted_revision,"Visible native group not completed on first frame")
   counts.native_groups+=1
  elif child.get_script()==preload("res://scripts/rendering/cafe_shape_2d.gd"):
   assert(child.paint_revision==child.painted_revision,"Visible retained shape not completed on first frame")
   counts.shapes+=1
  completed_native(child,counts)
func capture(label,state):
 artist.state=state.duplicate(true);clock_fixture.animation_time=float(state.get("clock",.3))
 artist.enabled=true;artist.queue_redraw()
 await RenderingServer.frame_post_draw
 var completed={"native_groups":0,"shapes":0,"all_completed":true}
 completed_native(artist,completed)
 assert(completed.native_groups>0 and completed.shapes>0)
 var owners=[]
 for owner in artist.native_object_nodes.values():
  if owner.visible:owners.append_array(owner.contacts)
 var contacts=normalized(owners)
 assert(contacts.size()==(12 if state.get("removed",false) else 24))
 for contact in contacts:assert(contact.progress==float(state.progress))
 assert(normalized(artist.render_contacts)==contacts,"Emitted and current owner contacts differ")
 var img=root.get_texture().get_image();img.convert(Image.FORMAT_RGBA8)
 var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(img.get_data())
 var file="%02d-%s.png"%[frames.size(),label];assert(img.save_png(output.path_join(file))==OK)
 frames.append({"label":label,"first_completed_frame":true,"input":state,"completed":completed,"contacts":contacts,"file":file,"rgba_sha256":digest.finish().hex_encode()})
func run():
 assert(output!="" and "saveguard" in OS.get_user_data_dir())
 assert(DisplayServer.get_name()=="X11","Actual native pixels required")
 DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1360,880);seed(13017)
 clock_fixture=ClockFixture.new();root.add_child(clock_fixture)
 artist=Artist.new();artist.game=clock_fixture;root.add_child(artist)
 for wait_frame in 900:
  if artist.moving_atlas.is_ready() and artist.head_atlas.is_ready():break
  await process_frame
 assert(artist.moving_atlas.is_ready() and artist.head_atlas.is_ready(),"Existing moving/head atlases must be ready")
 await capture("first-deferred-latest",{"progress":.8,"double_submit":true})
 for step in 17:await capture("cycle-%02d"%step,{"progress":float(step)/16.0,"clock":float(step)/16.0*6.25})
 for state in [{"label":"blink-on","clock":0.0},{"label":"blink-off","clock":.2},{"label":"walking-a","moving":true,"phase":.2},{"label":"walking-b","moving":true,"phase":.7},{"label":"work-a","action":"taking_order"},{"label":"work-b","action":"taking_order"},{"label":"payload-on","payload":"plate"},{"label":"payload-off"},{"label":"tool-on","tool":"cloth"},{"label":"tool-off"},{"label":"seated-on","seated":true,"seat_mix":1.0},{"label":"seated-off"},{"label":"slots-reversed","reverse":true},{"label":"owners-removed","removed":true},{"label":"owners-returned"}]:
  state.progress=.2 if frames.size()%2==0 else .7
  var label=state.label;state.erase("label");await capture(label,state)
 assert(frames.size()==33)
 var report={"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"viewport":[1360,880],"fixture_seed":13017,"generated_profile":true,"save_calls":0,"game_instance_created":false,"smoke_only":false,"frames":frames,"scope":"33 actual first-completed native frames; 17 sampled phases spanning standby cycle, blink and boundary transitions; 24 actors covering3 species/4 roles/2 facings. Synthetic isolation, not service/FPS or visual acceptance."}
 FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 artist.queue_free();clock_fixture.queue_free();await process_frame
 print("STANDBY_RETENTION_CAPTURE ",JSON.stringify({"frames":frames.size(),"saves":0}));quit()
