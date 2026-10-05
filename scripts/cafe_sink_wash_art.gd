extends RefCounted
## Read-only sink animation: one active dish, fixed basin/tap contacts, no jobs.
const Geometry=preload("res://scripts/kitchen_worktop_geometry.gd")
const ARM=10.5
const HALF_ARM=ARM*.5
const INSET=.55
static func actual_surface(at:Vector2,height:float,rotation:int)->Vector2:
 var q=at.rotated(posmod(rotation,4)*PI/2)
 return Vector2((q.x-q.y)*34,(q.x+q.y)*17-height)
static func state(game,sink_id:int)->Dictionary:
 if game==null or not "dishwashing" in game or not "staff_states" in game:return {}
 var sink=game.model.get_item(sink_id)
 if sink.is_empty():return {}
 var face=game.model.cell_center(game.model.workface_cell(sink))
 for worker in game.staff_states:
  if worker.get("role")!="cleaner" or worker.get("job_kind")!="wash" or int(worker.get("station_id",-1))!=sink_id or worker.get("art_action")!="washing" or (worker.pos as Vector2).distance_to(face)>.04:continue
  var dish=game.dishwashing.entry(worker)
  if dish.is_empty():continue
  var seconds=clampf(float(worker.job_elapsed),0,20)
  return {"seconds":seconds,"count":game.dishwashing.count_at(sink_id),"rotation":int(sink.rot),"water":not bool(game.get("paused")) and not bool(game.get("editing")) and seconds>0 and seconds<20,"worker":worker}
 return {}
static func basis(rotation:int,tilt:float)->Transform2D:
 var axes=[]
 for screen in [Vector2.RIGHT,Vector2.DOWN]:
  var flat=Vector2(screen.x/68.0+screen.y/34.0,screen.y/34.0-screen.x/68.0).rotated(-rotation*PI/2)
  var height=-flat.y*sin(tilt)*30.0
  flat.y*=cos(tilt)
  axes.append(actual_surface(flat,height,rotation))
 return Transform2D(axes[0],axes[1],Vector2.ZERO)
static func geometry(rotation:int,seconds:float,count:int)->Dictionary:
 var lift=smoothstep(0,.8,seconds);var lower=smoothstep(19.35,20.0,seconds)
 var initial_height=Geometry.height(Geometry.SINK_STACK_HEIGHT)+maxi(0,count-1)*2.2
 var z=lerpf(Geometry.SINK_BASIN_CENTER.y,.30,lift);z=lerpf(z,.08,lower)
 var height=lerpf(initial_height,22.5,lift);height=lerpf(height,Geometry.height(Geometry.SINK_STACK_HEIGHT),lower)
 var tilt=deg_to_rad(28)*lift*(1.0-lower)
 var center=actual_surface(Vector2(0,z),height,rotation)
 var plate_basis=basis(rotation,tilt)
 var cycle=fposmod(maxf(0,seconds-.8),1.15)/1.15
 var scrub=Vector2(sin(cycle*TAU)*2.0,cos(cycle*TAU)*.85)
 var rinsing=smoothstep(17.3,18.7,seconds)
 scrub*=1.0-rinsing
 var water_height=height-(.10-z)/maxf(.1,cos(tilt))*sin(tilt)*30.0
 var outlet=Geometry.surface(Vector2(0,.10),Geometry.SINK_TAP_OUTLET_HEIGHT,rotation)
 var contact=actual_surface(Vector2(0,.10),water_height,rotation)
 return {"center":center,"basis":plate_basis,"transform":Transform2D(plate_basis.x,plate_basis.y,center),"scrub_local":scrub,"scrub":center+plate_basis*scrub,"outlet":outlet,"water_contact":contact,"height":height,"foam":smoothstep(.8,1.8,seconds)*(1.0-smoothstep(17.3,19.1,seconds)),"dirt":1.0-smoothstep(3,17,seconds),"seconds":seconds,"lower":lower,"lift":lift,"stage":"lift" if seconds<.8 else ("scrub" if seconds<17.3 else ("rinse" if seconds<19.35 else "lower"))}
static func nearest_rim(shoulder:Vector2,center:Vector2,plate_basis:Transform2D)->Vector2:
 var best=center;var distance=INF
 for i in range(48):
  var t=i*TAU/48.0;var at=center+plate_basis*Vector2(cos(t)*12.4,sin(t)*5.1)
  if at.distance_squared_to(shoulder)<distance:best=at;distance=at.distance_squared_to(shoulder)
 return best
static func arm(shoulder:Vector2,target:Vector2,bend_side:float=1.0)->Dictionary:
 var delta=target-shoulder;var distance=clampf(delta.length(),.2,ARM-.02)
 var axis=delta.normalized() if delta.length()>.001 else Vector2.DOWN
 var hand=shoulder+axis*distance
 # Each arm keeps one IK branch through lift, scrub and lowering. Choosing
 # the branch from target.y flips the elbow when the wrist crosses a shoulder.
 var bend=Vector2(-axis.y,axis.x)*bend_side
 var elbow=shoulder+axis*distance*.5+bend*sqrt(maxf(0,HALF_ARM*HALF_ARM-distance*distance*.25))
 return {"shoulder":shoulder,"elbow":elbow,"hand":hand,"target":target,"error":hand.distance_to(target)}
static func grip(shoulder:Vector2,center:Vector2,plate_basis:Transform2D,reference:Dictionary)->Vector2:
 if reference.is_empty():return nearest_rim(shoulder,center,plate_basis)
 var ref_basis:Transform2D=reference.basis;var ref_center:Vector2=reference.center
 var local=ref_basis.affine_inverse()*(nearest_rim(shoulder,ref_center,ref_basis)-ref_center)
 return center+plate_basis*local
static func pose(near:Vector2,far:Vector2,center:Vector2,plate_basis:Transform2D,seconds:float,reference:Dictionary={})->Dictionary:
 var ready=smoothstep(.25,.8,seconds)*(1.0-smoothstep(19.45,20,seconds))
 var cycle=fposmod(maxf(0,seconds-.8),1.15)/1.15
 var local=Vector2(sin(cycle*TAU)*2,cos(cycle*TAU)*.85)*(1.0-smoothstep(17.3,18.7,seconds))
 var scrub=center+plate_basis*local
 var anchor:Vector2=reference.get("center",scrub)
 var use_near=near.distance_squared_to(anchor)<=far.distance_squared_to(anchor)
 var working=near if use_near else far;var supporting=far if use_near else near
 var pickup=grip(working,center,plate_basis,reference)
 var work=arm(working,pickup.lerp(scrub,ready),1.0 if use_near else -1.0);var support=arm(supporting,grip(supporting,center,plate_basis,reference),-1.0 if use_near else 1.0)
 return {"use_near":use_near,"work":work,"support":support,"near":work if use_near else support,"far":support if use_near else work,"contact":ready>.98,"stage":"scrub" if seconds<17.3 else "rinse"}
static func draw_water(artist,state:Dictionary,g:Dictionary):
 if not bool(state.get("water",false)):return
 var seconds=float(g.seconds);var from:Vector2=g.outlet+Vector2(0,.7);var to:Vector2=g.water_contact
 artist.line(from,to,Color(.52,.77,.82,.62),1.3)
 artist.line(from+Vector2(-.3,0),to+Vector2(-.3,0),Color(.86,.96,.91,.80),.5)
 for i in range(4):
  var part=fposmod(seconds*1.8+i*.25,1.0)
  artist.line(from.lerp(to,part),from.lerp(to,minf(1,part+.09)),Color(.95,1,.95,.82),.65)
 # A tiny splash belongs exactly to the active dish's water contact.
 for i in range(3):
  var phase=fposmod(seconds*2+i*.33,1.0)
  var at=to+Vector2((i-1)*(1+phase)*1.2,-sin(phase*PI)*1.8)
  artist.ellipse(at,Vector2(.55,.35),Color(.86,.97,.91,.60*(1-phase)))
static func draw_foam(artist,g:Dictionary):
 var amount=float(g.foam)
 if amount<=.001:return
 var center:Vector2=g.center;var plate_basis:Transform2D=g.basis
 for i in range(7):
  var angle=i*TAU/7.0+float(g.seconds)*.9
  var local:Vector2=g.scrub_local+Vector2(cos(angle)*3.0,sin(angle)*1.2)
  var at=center+plate_basis*local
  artist.ellipse(at,Vector2(.70+(i%2)*.25,.40),Color(.90,.96,.86,amount*.70))
