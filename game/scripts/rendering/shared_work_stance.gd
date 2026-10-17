extends RefCounted
## Display-only placement for compatible contacts already selected by service.
## No routes, task grants, service clocks or saved reservations are owned here.
const Approach=preload("res://scripts/gameplay/floor_cleaning_approach.gd")
const Motion=preload("res://scripts/rendering/illustrated_motion.gd")
const CleaningPose=preload("res://scripts/rendering/cleaning_tool_pose.gd")
const TableContact=preload("res://scripts/rendering/table_work_contact.gd")
const Claims=preload("res://scripts/gameplay/cafe_work_claims.gd")
const HEAD_DIAMETER=Vector2(26.2,25.4) # Existing intact character head ellipse.
const BODY_GAP=.60 # Two existing .30 placement bodies, not a routing collision.

static func separation(left:Vector2,right:Vector2)->float:
 var projected=Motion.project(left-right)/HEAD_DIAMETER
 return minf(projected.length(),left.distance_to(right)/BODY_GAP)

static func solve(entries:Array,model,previous:Dictionary={},prior_domains:Dictionary={},preferred:Dictionary={})->Dictionary:
 var choices={};var offsets={};var domains={};var metrics={"candidate_checks":0,"domain_reuses":0,"group_size":entries.size(),"passes":2}
 for entry in entries:
  var options=[]
  var signature=[model.get_instance_id(),model.revision,entry.center,entry.contact,entry.kind,entry.action,entry.natural,entry.get("table_geometry",{})]
  var domain=prior_domains.get(entry.key,{})
  if domain.get("signature",[])==signature:
   options=domain.choices.duplicate();metrics.domain_reuses+=1
  else:
   var edge=.5+Approach.CELL_MARGIN if str(entry.kind)=="display" else .5-Approach.CELL_MARGIN;var near=.5-model.STAFF_PLACEMENT_RADIUS
   for x in [-edge,-near,0.0,near,edge]:
    for y in [-edge,-near,0.0,near,edge]:
     var offset=Vector2(x,y)
     metrics.candidate_checks+=1
     if _valid(entry,offset,model):options.append(offset)
   if entry.has("table_geometry"):
    var tangent=(entry.contact-entry.center).normalized().orthogonal()
    for side in [-edge,-near,0.0,near,edge]:
     var offset=entry.natural+tangent*side
     metrics.candidate_checks+=1
     if _valid(entry,offset,model) and not options.has(offset):options.append(offset)
   metrics.candidate_checks+=1
   if _valid(entry,entry.natural,model) and not options.has(entry.natural):options.append(entry.natural)
   domain={"signature":signature.duplicate(true),"choices":options.duplicate()}
  domains[entry.key]=domain
  choices[entry.key]=options
  var current:Vector2=previous.get(entry.key,entry.natural)
  if not options.has(current):
   metrics.candidate_checks+=1
   if _valid(entry,current,model):options.append(current)
  if str(entry.kind)=="display" and entry.has("lookahead"):
   var direction:Vector2=(entry.lookahead-entry.center).normalized()
   var unsafe=false
   for other in entries:
    if other.key==entry.key:continue
    var held:Vector2=previous.get(other.key,other.natural)
    if _swept_separation(entry.center+current,entry.lookahead+entry.natural,other.center+held,other.get("lookahead",other.center)+held)<1.0:unsafe=true;break
   if unsafe and direction.length_squared()>.01:
    # Do not add visual catch-up speed toward a colleague while releasing a
    # shared stance. Retain the longitudinal offset and sidestep first.
    options=options.filter(func(candidate):return (candidate-current).dot(direction)<=.000001)
    choices[entry.key]=options
  # A display-only departing participant seeks normal drawing again. A still
  # productive contact keeps its proven position instead of crossing a peer.
  offsets[entry.key]=preferred.get(entry.key,current) if str(entry.kind)!="display" else current
  if not options.has(offsets[entry.key]):offsets[entry.key]=options[0] if not options.is_empty() else current
 if not _clear(entries,choices,offsets) or entries.any(func(entry):return entry.has("lookahead")):_optimise(entries,choices,offsets,{},preferred if not preferred.is_empty() else previous)
 return {"offsets":offsets,"choices":choices,"domains":domains,"metrics":metrics,"clear":_clear(entries,choices,offsets)}

static func step(entries:Array,model,placement:Dictionary,previous:Dictionary,delta:float,motion=null)->Dictionary:
 var choices={};var offsets={};var goals=placement.offsets;var evaluations=0;var previews=0
 for entry in entries:
  var current:Vector2=previous.get(entry.key,Vector2.ZERO);var options=[]
  var support_allowance=minf(TableContact.INK_MARGIN,TableContact.support_gap(entry,current,motion.sample(entry.key) if motion!=null else {})) if entry.has("table_geometry") else 0.0
  for goal in placement.choices.get(entry.key,[]):
   evaluations+=1
   var next=current.move_toward(goal,maxf(0.0,delta)*1.5)
   if not options.has(next) and _transition_valid(entry,current,next,model,support_allowance):
    if entry.has("table_geometry") and motion!=null:
     previews+=1
     if TableContact.support_gap(entry,next,motion.preview(entry.key,entry.center+next,delta))<support_allowance-.000001:continue
    options.append(next)
  if _transition_valid(entry,current,current,model,support_allowance) and not options.has(current):
   var clear=true
   if entry.has("table_geometry") and motion!=null:
    previews+=1;clear=TableContact.support_gap(entry,current,motion.preview(entry.key,entry.center+current,delta))>=support_allowance-.000001
   if clear:options.append(current)
  choices[entry.key]=options
  var desired=current.move_toward(goals.get(entry.key,current),maxf(0.0,delta)*1.5)
  offsets[entry.key]=desired if options.has(desired) else (options[0] if not options.is_empty() else current)
 _optimise(entries,choices,offsets,goals)
 return {"offsets":offsets,"candidate_steps":evaluations,"motion_previews":previews,"clear":_clear(entries,choices,offsets)}

static func _optimise(entries:Array,choices:Dictionary,offsets:Dictionary,goals:Dictionary={},reference:Dictionary={}):
 var ordered=entries.duplicate()
 ordered.sort_custom(func(a,b):return choices[a.key].size()<choices[b.key].size() if choices[a.key].size()!=choices[b.key].size() else str(a.claim.get("task",[a.key]))<str(b.claim.get("task",[b.key])))
 # The same bounded coordinate solve handles settled contacts and their next
 # display step. No search tree, routing calls, task delays or collision grants.
 for pass_index in 2:
  for entry in ordered:
   var best:Vector2=offsets[entry.key];var score=_cost(entry,best,entries,offsets,goals,reference)
   for candidate in choices[entry.key]:
    var value=_cost(entry,candidate,entries,offsets,goals,reference)
    if value<score-.000001:best=candidate;score=value
   offsets[entry.key]=best

static func _clear(entries:Array,choices:Dictionary,offsets:Dictionary)->bool:
 for a in entries.size():
  if choices[entries[a].key].is_empty() or not choices[entries[a].key].has(offsets[entries[a].key]):return false
  for b in range(a+1,entries.size()):
   if Claims.conflicts(entries[a].claim,entries[b].claim) or separation(entries[a].center+offsets[entries[a].key],entries[b].center+offsets[entries[b].key])<1.0-.00001:return false
 return true

static func _blocked_by(entry:Dictionary,start:Vector2,finish:Vector2,model)->String:
 return Approach.blocked_by(model,start,finish,entry.get("clearance_items"))

static func _geometry_valid(entry:Dictionary,offset:Vector2,model)->bool:
 var shown:Vector2=entry.center+offset
 if entry.has("table_geometry"):
  if not TableContact.envelope(entry,offset):return false
 elif str(entry.kind)!="display" and Vector2i(shown.floor())!=Vector2i(entry.center.floor()):return false
 if absf(offset.x)>.55+.000001 or absf(offset.y)>.55+.000001:return false
 return _blocked_by(entry,entry.center,shown,model)==""

static func _valid(entry:Dictionary,offset:Vector2,model)->bool:
 if not _geometry_valid(entry,offset,model):return false
 var shown:Vector2=entry.center+offset
 if entry.has("table_geometry"):return TableContact.contact(entry,offset) and TableContact.support_gap(entry,offset)>=TableContact.INK_MARGIN
 if str(entry.kind)=="display":return true
 var distance=shown.distance_to(entry.contact)
 var limit=entry.center.distance_to(entry.contact)
 if entry.claim.get("resource",["item"])[0]=="item" and str(entry.kind)=="table":limit=minf(limit,(entry.center+entry.natural).distance_to(entry.contact)+.15)
 elif str(entry.kind)=="floor_disposal":limit=.65
 return distance<=limit+.000001 and _floor_reach_valid(entry,shown)

static func _transition_valid(entry:Dictionary,current:Vector2,next:Vector2,model,support_allowance:float=0.0)->bool:
 if not _geometry_valid(entry,next,model) or _blocked_by(entry,entry.center+current,entry.center+next,model)!="":return false
 if entry.has("table_geometry"):
  # An existing accepted single-worker inset may already touch a support.
  # Added displacement may only escape that overlap, never deepen it.
  return TableContact.support_gap(entry,next)>=support_allowance-.000001
 return _floor_reach_valid(entry,entry.center+next)

static func _floor_reach_valid(entry:Dictionary,shown:Vector2)->bool:
 var action=str(entry.get("action",""))
 if action not in ["sweeping","mopping"]:return true
 var heading:Vector2=entry.contact-entry.center
 var back=heading.x+heading.y<0.0;var mirror=-1.0 if heading.x-heading.y<0.0 else 1.0
 var near=Vector2(7,-24) if back else Vector2(-7,-24)
 var far=Vector2(-6,-26.5) if back else Vector2(6,-26.5)
 var original_ground=Motion.project(entry.contact-entry.center)*Vector2(mirror,1)
 var ground=Motion.project(entry.contact-shown)*Vector2(mirror,1)
 # The stroke extrema bound the original rigid-arm/long-handle construction.
 # Separation cannot make a handle longer than the existing center stance.
 for phase in [0.0,.25,.75]:
  var original=CleaningPose.floor_pose(near,far,original_ground,back,phase,action=="sweeping")
  var pose=CleaningPose.floor_pose(near,far,ground,back,phase,action=="sweeping")
  if pose.shaft_top.distance_to(pose.brush)>original.shaft_top.distance_to(original.brush)+.000001:return false
  if action=="sweeping" and pose.far_hand.distance_to(pose.pan)>original.far_hand.distance_to(original.pan)+.000001:return false
 return true

static func _cost(entry:Dictionary,offset:Vector2,entries:Array,offsets:Dictionary,goals:Dictionary={},reference:Dictionary={})->float:
 var shown:Vector2=entry.center+offset
 var score=offset.distance_squared_to(goals[entry.key]) if goals.has(entry.key) else shown.distance_squared_to(entry.contact)+offset.distance_squared_to(entry.natural)*.1
 if reference.has(entry.key) and str(entry.kind)!="display":score+=offset.distance_squared_to(reference[entry.key])*10.0
 for other in entries:
  if other.key==entry.key:continue
  var gap=separation(shown,other.center+offsets[other.key])
  score+=maxf(0.0,1.0-gap)*10000.0
  if goals.is_empty() and (entry.has("lookahead") or other.has("lookahead")):
   var future=_swept_separation(shown,entry.get("lookahead",entry.center)+offset,other.center+offsets[other.key],other.get("lookahead",other.center)+offsets[other.key])
   score+=maxf(0.0,1.0-future)*100.0
 return score

static func _swept_separation(a:Vector2,next_a:Vector2,b:Vector2,next_b:Vector2)->float:
 var relative=a-b;var later=next_a-next_b
 var body=Geometry2D.get_closest_point_to_segment(Vector2.ZERO,relative,later).length()/BODY_GAP
 var heads=Geometry2D.get_closest_point_to_segment(Vector2.ZERO,Motion.project(relative)/HEAD_DIAMETER,Motion.project(later)/HEAD_DIAMETER).length()
 return minf(body,heads)
