extends SceneTree
class Fixture extends Node:
 var wall_detail=false
 var animation_time=0.0
class Recorder extends "res://scripts/rendering/illustrated_cafe.gd":
 var commands=[]
 func paint_native_object(target:Node2D,callback:Callable)->void:
  commands=[]
  super.paint_native_object(target,callback)
  target.set_meta("proof_commands",commands.duplicate(true))
 func _ready():pass
 func _process(_delta):pass
 func _draw():pass
 func retain_native_body_group(_callback:Callable,_shape:Array,_placement:Transform2D)->bool:return false
 func art_draw_set_transform_matrix(value:Transform2D):native_command_transform=value
 func art_draw_mesh(mesh:Mesh,texture:Texture2D=null,xf:Transform2D=Transform2D.IDENTITY,tint:Color=Color.WHITE):
  commands.append(["art_draw_mesh",native_command_transform,[mesh,texture,xf,tint]].duplicate(true))
 func art_draw_polygon(points:PackedVector2Array,colors:PackedColorArray,uvs:PackedVector2Array=PackedVector2Array(),texture:Texture2D=null):
  commands.append(["art_draw_polygon",native_command_transform,[points,colors,uvs,texture]].duplicate(true))
 func art_draw_colored_polygon(points:PackedVector2Array,tint:Color,uvs:PackedVector2Array=PackedVector2Array(),texture:Texture2D=null):
  commands.append(["art_draw_colored_polygon",native_command_transform,[points,tint,uvs,texture]].duplicate(true))
 func art_draw_polyline(points:PackedVector2Array,tint:Color,width:float=-1.0,antialiased:bool=false):
  commands.append(["art_draw_polyline",native_command_transform,[points,tint,width,antialiased]].duplicate(true))
 func art_draw_multiline(points:PackedVector2Array,tint:Color,width:float=-1.0,antialiased:bool=false):
  commands.append(["art_draw_multiline",native_command_transform,[points,tint,width,antialiased]].duplicate(true))
 func art_draw_line(start:Vector2,finish:Vector2,tint:Color,width:float=-1.0,antialiased:bool=false):
  commands.append(["art_draw_line",native_command_transform,[start,finish,tint,width,antialiased]].duplicate(true))
 func art_draw_rect(rect:Rect2,tint:Color,filled:bool=true,width:float=-1.0,antialiased:bool=false):
  commands.append(["art_draw_rect",native_command_transform,[rect,tint,filled,width,antialiased]].duplicate(true))
 func art_draw_texture_rect_region(texture:Texture2D,rect:Rect2,source:Rect2,tint:Color=Color.WHITE,transpose:bool=false,clip_uv:bool=true):
  commands.append(["art_draw_texture_rect_region",native_command_transform,[texture,rect,source,tint,transpose,clip_uv]].duplicate(true))
 func art_draw_circle(pos:Vector2,radius:float,tint:Color,filled:bool=true,width:float=-1.0,antialiased:bool=false):
  commands.append(["art_draw_circle",native_command_transform,[pos,radius,tint,filled,width,antialiased]].duplicate(true))
 func art_draw_string(font:Font,pos:Vector2,text:String,alignment:HorizontalAlignment=HORIZONTAL_ALIGNMENT_LEFT,width:float=-1,font_size:int=16,tint:Color=Color.WHITE,justification_flags:int=3,direction:TextServer.Direction=TextServer.DIRECTION_AUTO,orientation:TextServer.Orientation=TextServer.ORIENTATION_HORIZONTAL,oversampling:float=0.0):
  commands.append(["art_draw_string",native_command_transform,[font,pos,text,alignment,width,font_size,tint,justification_flags,direction,orientation,oversampling]].duplicate(true))
var checks=0
var failures=[]
func check(value,label):
 checks+=1
 if not value and not failures.has(label):failures.append(label)
func _initialize():run.call_deferred()
func submit(art,t,state={}):
 art.canvas_stream.active=true;art.canvas_stream.cursor=0
 var pose={"seat_mix":float(state.get("seat_mix",1.0 if bool(state.get("seated",false)) else 0.0))}
 art.character(Vector2.ZERO,int(state.get("id",0)),bool(state.get("staff",true)),bool(state.get("moving",false)),bool(state.get("seated",false)),str(state.get("action","standby")),t,Vector2(18,-28),Vector2(1,0),str(state.get("payload","none")),str(state.get("tool","none")),pose,"waiter")
func compare_completed(art,owner,t):
 var expected=owner.paint.get_bound_arguments().duplicate(true)
 expected[8]=t;expected[11].progress=t
 var reference=art.NativeDrawNode.new()
 art.paint_native_object(reference,art._paint_native_character.bindv(expected))
 check(owner.get_meta("proof_commands")==reference.get_meta("proof_commands"),"Completed native commands equal an unnormalized live-progress paint")
 var actual_contact=owner.contacts[0].duplicate(true);var expected_contact=reference.contacts[0].duplicate(true)
 actual_contact.erase("native_owner");expected_contact.erase("native_owner")
 check(actual_contact==expected_contact,"All completed contact fields equal unnormalized live-progress paint")
 reference.free()
func run():
 var art=Recorder.new();var fixture=Fixture.new();art.game=fixture
 art.use_retained_geometry=false;art.use_cached_heads=false;art.use_cached_moving_art=false;art.use_native_object_nodes=false
 for species in 3:
  for back in [false,true]:
   for role in ["chef","waiter","cleaner","cashier"]:
    var reference=[];var reference_contact={}
    for step in 17:
     var t=float(step)/16.0
     var options={"role":role,"shirt":"739c7f","action":"standby","progress":t,"payload":"none","tool":"none","reach":Vector2(18,-28),"seat_mix":0.0,"blink":false,"chef_hat":role=="chef"}
     art.commands=[];art.art_transform(Vector2.ZERO)
     var contact=art._paint_native_character(Vector2.ZERO,species,true,false,species,back,0.0,"standby",t,Vector2(18,-28),"none",options)
     check(contact.progress==t,"Live contact progress preserves input")
     contact.erase("progress")
     if step==0:reference=art.commands.duplicate(true);reference_contact=contact.duplicate(true)
     else:
      check(art.commands==reference,"Standby phase leaves exact command stream unchanged")
      check(contact==reference_contact,"Only contact progress changes over standby phase")
 # Exercise real deferred native-owner completion with a recording artist.
 art.use_native_object_nodes=true;art.use_retained_head_nodes=false;root.add_child(art)
 art.canvas_stream.active=true
 submit(art,.1)
 var owner=art.native_object_nodes[0]
 check(owner.contacts.is_empty() and owner.painted_revision==-1,"First frame has no fabricated completed contacts")
 submit(art,.8)
 check(owner.paint_revision==1,"Metadata-only update before first deferred draw retains one revision")
 await process_frame;await process_frame
 check(owner.contacts.size()==1 and owner.contacts[0].progress==.8,"Deferred first draw uses latest live progress")
 compare_completed(art,owner,.8)
 var revision=owner.paint_revision;var draws=owner.draw_count
 for step in 17:
  var t=float(step)/16.0;submit(art,t)
  check(owner.contacts.size()==1 and owner.contacts[0].progress==t,"Completed contacts refresh immediately without waiting for redraw")
  await process_frame
  check(owner.paint_revision==revision and owner.draw_count==draws,"Stationary standby clock does not repaint")
  compare_completed(art,owner,t)
 # Every boundary outside the exact predicate must preserve ordinary invalidation.
 for state in [{"moving":true},{"seated":true},{"payload":"plate"},{"tool":"cloth"},{"action":"taking_order"},{"staff":false},{"seat_mix":.01}]:
  submit(art,.2,state);var before=owner.paint_revision
  submit(art,.7,state)
  check(owner.paint_revision>before and is_nan(owner.contact_progress),"Predicate boundary keeps real progress in draw key")
  await process_frame;await process_frame
  check(owner.contacts.size()==1 and owner.contacts[0].progress==.7,"Boundary contacts retain current progress")
  compare_completed(art,owner,.7)
 submit(art,.3);await process_frame;await process_frame
 var before_blink=owner.paint_revision;fixture.animation_time=.2;submit(art,.4)
 check(owner.paint_revision>before_blink,"Blink transition still invalidates visual commands")
 await process_frame;await process_frame
 # Replace slot0 before its queued character paint and then return a different actor.
 submit(art,.25);art.canvas_stream.cursor=0
 art.retain_native_local_object(func():return {},["test-other-owner"],Transform2D.IDENTITY)
 check(is_nan(owner.contact_progress) and owner.contacts.is_empty(),"Slot reassignment clears standby metadata and old contacts")
 submit(art,.9,{"id":7});await process_frame;await process_frame
 check(owner.contacts.size()==1 and owner.contacts[0].id==7 and owner.contacts[0].progress==.9,"Reassigned slot publishes only current actor metadata")
 var observed=weakref(owner);art.free();fixture.free()
 check(observed.get_ref()==null,"Owner and scalar metadata release with artist")
 var report={"checks":checks,"failures":failures,"scope":"Exact procedural command parity over17 phases,3 species,2 facings,4 roles; procedural/native command and contact parity, deferred transitions and ownership; no pixels"}
 if OS.get_environment("OUTPUT")!="":FileAccess.open(OS.get_environment("OUTPUT"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("STANDBY_NATIVE_RETENTION_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
