extends RefCounted
## Presentation-only register and short gestures. Reads progress; never settles.
static func guest_action(guest:Dictionary,service:Dictionary={})->String:
 if not guest.get("mobility",{}).is_empty():return "walking"
 if guest.phase=="paying":return "paying"
 if guest.phase=="checkout_wait":return "idle"
 if not bool(guest.get("seated",false)):return "walking"
 # Service phases describe what the kitchen owes this guest, not a job
 # performed by the guest. Waiting diners must never inherit a chef tool.
 if guest.phase=="cooking":return "waiting_meal"
 if guest.phase=="drinking":
  var cup_ready=bool(service.get("drink_done",false)) and str(service.get("drink_owner",""))=="table" and not bool(service.get("dishes_collected",false))
  return "drinking" if cup_ready else "waiting_drink"
 if guest.phase=="eating":
  # Match the tabletop renderer's legacy fallback only when ownership is
  # absent. An explicit kitchen/staff/cleared owner must never look served.
  var plate_ready=str(service.get("plate_owner","table"))=="table" and not bool(service.get("dishes_collected",false))
  return "eating" if plate_ready else "waiting_meal"
 return str(guest.phase)
static func guest_progress(game,guest:Dictionary)->float:
 if guest.phase!="paying":return 0.0
 for staff in game.staff_states:
  if staff.job_kind=="take_payment" and int(staff.job_guest_id)==int(guest.id) and int(staff.job_token)==int(guest.checkout_token):return clampf(float(staff.job_elapsed)/game.Checkout.PAYMENT_SECONDS,0,1)
 return 0.0
static func contact_surface(rotation:int,cashier:bool)->Vector2:
 var q=Vector2(0,-.35 if cashier else .35).rotated(posmod(rotation,4)*PI/2)
 return Vector2((q.x-q.y)*34,(q.x+q.y)*17-(30.0 if cashier else 31.2))
static func payment_inset(heading:Vector2,rotation:int,cashier:bool)->float:
 # Solve short-arm contact by approaching the near counter edge, never by
 # stretching a limb. This is a bounded presentation stance only.
 var d=heading.normalized();var mirror=-1.0 if d.x-d.y<0 else 1.0;var back=d.x+d.y<0
 var axis=Vector2((d.x-d.y)*39*mirror,(d.x+d.y)*19.5)
 var surface=contact_surface(rotation,cashier);surface.x*=mirror
 var near=Vector2(7,-24) if back else Vector2(-7,-24)
 var far=Vector2(-6,-26.5) if back else Vector2(6,-26.5)
 var best=.5
 var found=false
 for shoulder in [near,far]:
  var offset=surface-shoulder;var aa=axis.length_squared();var bb=2.0*axis.dot(offset);var cc=offset.length_squared()-10.5*10.5
  var disc=bb*bb-4.0*aa*cc
  if aa<.001 or disc<0:continue
  for t in [(-bb+sqrt(disc))/(2.0*aa),(-bb-sqrt(disc))/(2.0*aa)]:
   var inset=1.0-t
   if inset>=.20 and inset<=.58 and (not found or inset<best):best=inset;found=true
 return best
static func payment_pose(near:Vector2,far:Vector2,reach:Vector2,progress:float,cashier:bool)->Dictionary:
 var use_near=absf(near.distance_to(reach)-10.5)<=absf(far.distance_to(reach)-10.5)
 var shoulder=near if use_near else far
 var rest=Vector2(1,10).angle();var aim=(reach-shoulder).angle()
 var raised=smoothstep(.06,.32,progress)*(1.0-smoothstep(.78,.98,progress))
 var tap=sin(clampf((progress-.40)/.24,0,1)*TAU)*.035 if cashier else 0.0
 var hand=shoulder+Vector2.from_angle(lerp_angle(rest,aim,raised)+tap)*10.5
 return {"use_near":use_near,"hand":hand,"contact":progress>=.32 and progress<=.78,"target":reach,"length":10.5}
static func hand_prop(artist,hand:Vector2,progress:float,cashier:bool):
 if cashier or progress<.12 or progress>.88:return
 var corners=[hand+Vector2(-2.5,-1.5),hand+Vector2(2.5,-1.5),hand+Vector2(2.5,1.5),hand+Vector2(-2.5,1.5)]
 artist.rounded_poly(corners,.6,"e5c889")
 artist.line(hand+Vector2(-1.8,-.4),hand+Vector2(1.8,-.4),"889e82",.65)
static func draw_register(f,artist:Node2D,p:Vector2,rotation:int,id:int):
 f.a=artist;f.origin=p;f.turn=posmod(rotation,4)
 # Checkout uses a plain customer-facing panel, not the generic storage
 # cabinet's doors/handles. Keep its footprint, height, palette and terminal
 # orientation; no drawer seam is painted through the rear views either.
 f.box(0,0,.90,.76,1,29,"e7d7ad","b7a77e","968965","b7a77e")
 f.box(0,-.10,.43,.38,29,33,"8faaa0","759487","637f73")
 f.box(0,-.34,.22,.08,29,30,"c8d5bc","8ca092","728a7d")
 f.top_ellipse(0,-.35,30,.037,.020,"e4d99e")
 f.box(0,.32,.22,.12,29,31,"d4c995","a2976c","8b835f")
 f.top_ellipse(0,.35,31.2,.045,.024,"779d88")
 var state=register_visual_state(artist,id)
 var light=state.light;var recent=state.recent
 # Local -Z is the employee side. Keep the keys on that side of the
 # employee-facing screen, with both seated on the existing till base.
 # The receipt leaves the customer side of the terminal. In employee views
 # it is behind the tall screen, just as the keys are on its near side.
 # Keep those pieces in depth order instead of painting the paper last.
 var employee_visible=Vector2(0,-1).rotated(f.turn*PI/2).dot(Vector2.ONE)>0
 var parts=["receipt","screen","keys"] if employee_visible else ["keys","screen","receipt"]
 for part in parts:
  if part=="keys":
   for x in [-.085,0,.085]:
    for z in [-.22,-.15]:
     # A shallow side and smaller face separate the keys from the till base
     # without changing their centers or the short cashier contact gesture.
     f.top_ellipse(x,z,33.15,.027,.020,"637f73")
     f.top_ellipse(x,z,33.4,.024,.017,"eee1bd")
     f.top_ellipse(x-.004,z-.003,33.43,.012,.006,"f6eaca")
   f.top_ellipse(.145,-.1,33.3,.024,.024,light)
  elif part=="receipt":
   if recent:
    var extension=.12
    f.face([f.point(-.05,.15,33.25),f.point(.07,.15,33.25),f.point(.07,.15+extension,33.25),f.point(-.05,.15+extension,33.25)],"fff5d8",.25)
  else:
   f.box(0,.035,.34,.10,33,39,"a4bbb0","668476","567064")
   if employee_visible:
    # The inset remains on the employee-facing plane. Soft marks suggest
    # an LCD readout; they are decoration, never a second payment authority.
    f.face([f.point(-.13,-.021,34),f.point(.13,-.021,34),f.point(.13,-.021,37.8),f.point(-.13,-.021,37.8)],"526f62",.5)
    f.face([f.point(-.112,-.022,34.45),f.point(.112,-.022,34.45),f.point(.112,-.022,37.35),f.point(-.112,-.022,37.35)],"d4e1b7",.35)
    for x in [-.075,-.015,.045]:
     f.edge(f.point(x,-.023,36.45),f.point(x+.038,-.023,36.45),"779d88",.65)
    f.edge(f.point(-.075,-.023,35.3),f.point(.075,-.023,35.3),"a4bbb0",.45)
 return true

static func register_visual_state(artist:Node2D,id:int)->Dictionary:
 var recent=false;var paying=false
 if "game" in artist and is_instance_valid(artist.game):
  var game=artist.game
  for staff in game.staff_states:
   if staff.job_kind=="take_payment" and int(staff.station_id)==id and staff.art_action=="taking_payment":paying=true
  for guest in game.model.customers:
   if guest.paid and int(guest.get("checkout_register_id",-1))==id and guest.phase=="leaving" and float(guest.elapsed)<1.2:recent=true
 var light="79ac78" if recent else ("e2c973" if paying else "526f62")
 return {"light":light,"recent":recent}
